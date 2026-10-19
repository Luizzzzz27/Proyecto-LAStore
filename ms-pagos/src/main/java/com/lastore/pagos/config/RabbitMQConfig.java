package com.lastore.pagos.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.beans.factory.annotation.Qualifier;

@Configuration
public class RabbitMQConfig {
    public static final String EXCHANGE = "ex.lastore.eventos";
    public static final String APROBADA = "q.lastore.cotizacion.aprobada";
    public static final String CANCELADA = "q.lastore.cotizacion.cancelada";
    public static final String PAGO_ANULADO = "q.lastore.pago.anulado";
    public static final String RK_APROBADA = "rk.cotizacion.aprobada";
    public static final String RK_CANCELADA = "rk.cotizacion.cancelada";
    public static final String RK_PAGO_ANULADO = "rk.pago.anulado";

    @Bean public Queue cotizacionAprobada() { return new Queue(APROBADA, true); }
    @Bean public Queue cotizacionCancelada() { return new Queue(CANCELADA, true); }
    @Bean public Queue pagoAnulado() { return new Queue(PAGO_ANULADO, true); }
    @Bean public DirectExchange eventosExchange() { return new DirectExchange(EXCHANGE, true, false); }

    @Bean public Binding aprobadaBinding(@Qualifier("cotizacionAprobada") Queue queue, DirectExchange eventosExchange) {
        return BindingBuilder.bind(queue).to(eventosExchange).with(RK_APROBADA);
    }
    @Bean public Binding canceladaBinding(@Qualifier("cotizacionCancelada") Queue queue, DirectExchange eventosExchange) {
        return BindingBuilder.bind(queue).to(eventosExchange).with(RK_CANCELADA);
    }
    @Bean public Binding pagoAnuladoBinding(@Qualifier("pagoAnulado") Queue queue, DirectExchange eventosExchange) {
        return BindingBuilder.bind(queue).to(eventosExchange).with(RK_PAGO_ANULADO);
    }
}