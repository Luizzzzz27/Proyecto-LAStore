package com.lastore.pagos.messaging;

import java.math.BigDecimal;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;

@Component
public class RabbitMQListener {
    private static final Logger LOGGER = LoggerFactory.getLogger(RabbitMQListener.class);
    private static final String ESTADO_PENDIENTE = "PENDIENTE";
    private final PagoRepository pagoRepository;

    public RabbitMQListener(PagoRepository pagoRepository) {
        this.pagoRepository = pagoRepository;
    }

    @RabbitListener(queues = RabbitMQConfig.COLA_COTIZACION_APROBADA)
    public void recibirCotizacionAprobada(String mensaje) {
        String[] valores = mensaje.split(":");
        if (valores.length != 2) {
            throw new IllegalArgumentException("Formato de mensaje inválido: " + mensaje);
        }

        Long ticketId = Long.parseLong(valores[0]);
        BigDecimal montoTotal = new BigDecimal(valores[1]);

        if (pagoRepository.findByTicketIdAndEstadoPago(ticketId, ESTADO_PENDIENTE).isPresent()) {
            LOGGER.info("Ya existe un pago pendiente para el ticketId={}; no se creará un duplicado", ticketId);
            return;
        }

        Pago pago = pagoRepository.save(new Pago(null, ticketId, montoTotal, ESTADO_PENDIENTE));
        LOGGER.info("Cobro pendiente creado: pagoId={}, ticketId={}, monto={}",
            pago.getId(), pago.getTicketId(), pago.getMontoPago());
    }
}