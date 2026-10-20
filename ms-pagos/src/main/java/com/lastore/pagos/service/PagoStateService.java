package com.lastore.pagos.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Arrays;
import java.util.LinkedHashSet;
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
import com.lastore.pagos.dto.CobroRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

@Service
public class PagoStateService {
    private static final Logger LOGGER = LoggerFactory.getLogger(PagoStateService.class);
    private static final String PENDIENTE = "PENDIENTE";
    private static final String PAGADO = "PAGADO";
    private static final String PARCIAL = "PARCIAL";
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
        if (existentes.stream().filter(p -> p.getMontoPagado().signum() > 0 && PARCIAL.equals(p.getEstadoPago())).count() > 1) {
            LOGGER.error("Ticket {} contiene varios cobros con abonos; requiere conciliación y se conservan intactos", ticketId);
            return;
        }
        existentes = existentes.stream().sorted(java.util.Comparator.comparing(Pago::getMontoPagado).reversed()).toList();
        for (Pago pago : existentes) {
            if (PENDIENTE.equals(pago.getEstadoPago()) || PARCIAL.equals(pago.getEstadoPago())) {
                if (principal == null) {
                    principal = pago;
                    if (montoTotal.compareTo(principal.getMontoPagado()) < 0) {
                        LOGGER.warn("Ticket {}: se conserva el cobro porque el nuevo total es menor al abonado", ticketId);
                        return;
                    }
                    principal.setMontoPago(montoTotal);
                    recalcularEstado(principal);
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
            if (PENDIENTE.equals(pago.getEstadoPago()) || PARCIAL.equals(pago.getEstadoPago())) {
                pago.setEstadoPago(ANULADO);
                pagoRepository.save(pago);
            }
        }
    }

    public Pago anularPago(Pago pago) {
        pago.setMontoPagado(pago.getMontoPagado());
        pago.setEstadoPago(ANULADO);
        Pago guardado = pagoRepository.save(pago);
        rabbitTemplate.convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_PAGO_ANULADO, String.valueOf(guardado.getTicketId()));
        return guardado;
    }

    private Pago bloquear(Long id) {
        return pagoRepository.findForUpdateById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Pago no encontrado"));
    }

    @Transactional
    public Pago anular(Long id) { return anularPago(bloquear(id)); }

    @Transactional
    public Pago procesar(Long id, CobroRequest solicitud) {
        Pago pago = bloquear(id);
        if (!PENDIENTE.equals(pago.getEstadoPago()) && !PARCIAL.equals(pago.getEstadoPago())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Solo se pueden cobrar pagos pendientes o parciales");
        }
        BigDecimal abono = solicitud == null ? pago.getSaldoPendiente() : solicitud.getMontoAbono();
        String metodo = solicitud == null ? "EFECTIVO" : solicitud.getMetodoPago();
        if (metodo == null || !Set.of("EFECTIVO", "YAPE_PLIN", "TRANSFERENCIA", "TARJETA").contains(metodo)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Seleccione un método de pago válido");
        }
        abono = validarMonto(abono);
        if (abono.compareTo(pago.getSaldoPendiente()) > 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El abono no puede superar el saldo pendiente");
        }
        String referencia = solicitud == null ? null : solicitud.getReferenciaPago();
        if (referencia != null && referencia.length() > 500) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La referencia no puede superar 500 caracteres");
        }
        pago.setMontoPagado(pago.getMontoPagado().add(abono));
        LinkedHashSet<String> metodos = new LinkedHashSet<>();
        if (pago.getMetodoPago() != null && !pago.getMetodoPago().isBlank()) {
            metodos.addAll(Arrays.asList(pago.getMetodoPago().split(" / ")));
        }
        metodos.add(metodo);
        pago.setMetodoPago(String.join(" / ", metodos));
        String nota = "S/ " + abono.toPlainString() + " - " + metodo
            + (referencia == null || referencia.isBlank() ? "" : ": " + referencia.trim());
        pago.setReferenciaPago(pago.getReferenciaPago() == null || pago.getReferenciaPago().isBlank()
            ? nota : pago.getReferenciaPago() + "\n" + nota);
        recalcularEstado(pago);
        return pagoRepository.save(pago);
    }

    private BigDecimal validarMonto(BigDecimal monto) {
        if (monto == null || monto.signum() <= 0 || monto.compareTo(new BigDecimal("99999999.99")) > 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El monto debe ser mayor a cero");
        }
        try { return monto.setScale(2, RoundingMode.UNNECESSARY); }
        catch (ArithmeticException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El monto debe tener como máximo dos decimales");
        }
    }

    private void recalcularEstado(Pago pago) {
        pago.setEstadoPago(pago.getMontoPagado().signum() == 0 ? PENDIENTE
            : pago.getMontoPagado().compareTo(pago.getMonto()) >= 0 ? PAGADO : PARCIAL);
    }

    public Pago crear(Pago pago) {
        pago.setId(null);
        pago.setMonto(validarMonto(pago.getMonto()));
        pago.setMontoPagado(BigDecimal.ZERO);
        pago.setEstadoPago(PENDIENTE);
        pago.setMetodoPago(null);
        pago.setReferenciaPago(null);
        return pagoRepository.save(pago);
    }

    @Transactional
    public Pago actualizar(Long id, Pago datos) {
        Pago pago = bloquear(id);
        if (PAGADO.equals(pago.getEstadoPago()) || ANULADO.equals(pago.getEstadoPago())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "No se puede editar un pago finalizado");
        }
        BigDecimal total = validarMonto(datos.getMonto());
        if (total.compareTo(pago.getMontoPagado()) < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El total no puede ser menor al monto abonado");
        }
        if (!java.util.Objects.equals(pago.getTicketId(), datos.getTicketId())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "No se puede cambiar el ticket de un cobro");
        }
        pago.setMonto(total);
        recalcularEstado(pago);
        return pagoRepository.save(pago);
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
