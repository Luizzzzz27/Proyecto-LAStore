package com.lastore.reparaciones.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;

class TicketStateServiceTest {
    private final TicketRepository repository = mock(TicketRepository.class);
    private final RabbitTemplate rabbit = mock(RabbitTemplate.class);
    private final TicketStateService service = new TicketStateService(repository, rabbit);

    @Test void crearAprobadaPublicaCobro() {
        when(repository.save(any(Ticket.class))).thenAnswer(call -> {
            Ticket ticket = call.getArgument(0);
            ticket.setId(12L);
            return ticket;
        });
        Ticket ticket = new Ticket(null, 1L, "Laptop", "X", "Falla", "APROBADA", new BigDecimal("150.50"));
        service.crear(ticket);
        verify(rabbit).convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_APROBADA, "12:150.50");
    }

    @Test void editarARechazadaCancelaCobro() {
        Ticket ticket = new Ticket(12L, 1L, "Laptop", "X", "Falla", "APROBADA", new BigDecimal("150.50"));
        when(repository.findById(12L)).thenReturn(Optional.of(ticket));
        when(repository.save(any(Ticket.class))).thenAnswer(call -> call.getArgument(0));
        Ticket datos = new Ticket(12L, 1L, "Laptop", "X", "Falla", "RECHAZADA", new BigDecimal("150.50"));
        service.actualizar(12L, datos);
        verify(rabbit).convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_CANCELADA, "12");
    }

    @Test void anularConservaRegistroYPublicaCancelacion() {
        Ticket ticket = new Ticket(12L, 1L, "Laptop", "X", "Falla", "ENVIADA", BigDecimal.TEN);
        when(repository.findById(12L)).thenReturn(Optional.of(ticket));
        when(repository.save(any(Ticket.class))).thenAnswer(call -> call.getArgument(0));
        assertThat(service.anular(12L).getEstadoCotizacion()).isEqualTo("ANULADA");
        verify(repository).save(ticket);
        verify(rabbit).convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_CANCELADA, "12");
    }
}