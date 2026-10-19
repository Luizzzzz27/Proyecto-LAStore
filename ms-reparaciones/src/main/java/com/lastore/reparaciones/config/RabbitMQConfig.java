package com.lastore.reparaciones.config;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {
    public static final String APROBADA = "q.lastore.cotizacion.aprobada";
    public static final String CANCELADA = "q.lastore.cotizacion.cancelada";
    public static final String PAGO_ANULADO = "q.lastore.pago.anulado";

    @Bean public Queue cotizacionAprobada() { return new Queue(APROBADA, true); }
    @Bean public Queue cotizacionCancelada() { return new Queue(CANCELADA, true); }
    @Bean public Queue pagoAnulado() { return new Queue(PAGO_ANULADO, true); }
}