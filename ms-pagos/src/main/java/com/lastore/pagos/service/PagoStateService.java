package com.lastore.pagos.service;

import java.math.BigDecimal;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;

@Service
public class PagoStateService {
    private static final Logger LOGGER = LoggerFactory.getLogger(PagoStateService.class);
    private static final String PENDIENTE = "PENDIENTE";
    private static final String PAGADO = "PAGADO";
    private static final String ANULADO = "ANULADO";
    private final PagoRepository pagoRepository;
    private final RabbitTemplate rabbitTemplate;

    public PagoStateService(PagoRepository pagoRepository, RabbitTemplate rabbitTemplate) {
        this.pagoRepository = pagoRepository;
        this.rabbitTemplate = rabbitTemplate;
    }

    @Transactional
    public void aprobar(Long ticketId, BigDecimal montoTotal) {
        if (montoTotal == null || montoTotal.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("El monto aprobado debe ser mayor a cero");
        }
        List<Pago> existentes = pagoRepository.findByTicketIdOrderByIdAsc(ticketId);
        if (existentes.stream().anyMatch(pago -> PAGADO.equals(pago.getEstadoPago()))) {
            LOGGER.info("Ticket {} ya tiene un pago cobrado; se ignora nueva aprobación", ticketId);
            return;
        }
        Pago principal = null;
        for (Pago pago : existentes) {
            if (PENDIENTE.equals(pago.getEstadoPago())) {
                if (principal == null) {
                    principal = pago;
                    principal.setMontoPago(montoTotal);
                    pagoRepository.save(principal);
                } else {
                    pago.setEstadoPago(ANULADO);
                    pagoRepository.save(pago);
                }
            }
        }
        if (principal == null) {
            Pago nuevo = pagoRepository.save(new Pago(null, ticketId, montoTotal, PENDIENTE));
            LOGGER.info("Pago pendiente {} creado para ticket {}", nuevo.getId(), ticketId);
        } else {
            LOGGER.info("Pago pendiente {} actualizado para ticket {}", principal.getId(), ticketId);
        }
    }

    @Transactional
    public void cancelarCotizacion(Long ticketId) {
        for (Pago pago : pagoRepository.findByTicketIdOrderByIdAsc(ticketId)) {
            if (PENDIENTE.equals(pago.getEstadoPago())) {
                pago.setEstadoPago(ANULADO);
                pagoRepository.save(pago);
            }
        }
    }

    public Pago anularPago(Pago pago) {
        pago.setEstadoPago(ANULADO);
        Pago guardado = pagoRepository.save(pago);
        rabbitTemplate.convertAndSend(RabbitMQConfig.PAGO_ANULADO, String.valueOf(guardado.getTicketId()));
        return guardado;
    }

    @Transactional
    public void limpiarDuplicadosPendientes() {
        Set<Long> vistos = new HashSet<>();
        for (Pago pago : pagoRepository.findAll()) {
            if (PENDIENTE.equals(pago.getEstadoPago()) && !vistos.add(pago.getTicketId())) {
                pago.setEstadoPago(ANULADO);
                pagoRepository.save(pago);
                LOGGER.info("Pago pendiente duplicado {} anulado para ticket {}", pago.getId(), pago.getTicketId());
            }
        }
    }
}