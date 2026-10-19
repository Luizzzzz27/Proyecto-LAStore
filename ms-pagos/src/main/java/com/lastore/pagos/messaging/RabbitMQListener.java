package com.lastore.pagos.messaging;

import java.math.BigDecimal;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.service.PagoStateService;

@Component
public class RabbitMQListener {
    private final PagoStateService stateService;

    public RabbitMQListener(PagoStateService stateService) { this.stateService = stateService; }

    @RabbitListener(queues = RabbitMQConfig.APROBADA)
    public void recibirCotizacionAprobada(String mensaje) {
        String[] valores = mensaje.split(":");
        if (valores.length != 2) throw new IllegalArgumentException("Formato de mensaje inválido: " + mensaje);
        stateService.aprobar(Long.parseLong(valores[0]), new BigDecimal(valores[1]));
    }

    @RabbitListener(queues = RabbitMQConfig.CANCELADA)
    public void recibirCotizacionCancelada(String mensaje) {
        stateService.cancelarCotizacion(Long.parseLong(mensaje));
    }
}