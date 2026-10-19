package com.lastore.reparaciones.messaging;

import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.service.TicketStateService;

@Component
public class PagoAnuladoListener {
    private final TicketStateService stateService;

    public PagoAnuladoListener(TicketStateService stateService) { this.stateService = stateService; }

    @RabbitListener(queues = RabbitMQConfig.PAGO_ANULADO)
    public void recibir(String mensaje) { stateService.anularDesdePago(Long.parseLong(mensaje)); }
}