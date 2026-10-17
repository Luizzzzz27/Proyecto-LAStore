package com.lastore.pagos.config;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {
    public static final String COLA_COTIZACION_APROBADA = "q.lastore.cotizacion.aprobada";

    @Bean
    public Queue colaCotizacionAprobada() {
        return new Queue(COLA_COTIZACION_APROBADA, true);
    }
}