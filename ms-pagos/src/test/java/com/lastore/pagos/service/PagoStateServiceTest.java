package com.lastore.pagos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;

class PagoStateServiceTest {
    private final PagoRepository repository = mock(PagoRepository.class);
    private final RabbitTemplate rabbit = mock(RabbitTemplate.class);
    private final PagoStateService service = new PagoStateService(repository, rabbit);

    @Test void aprobacionReutilizaPrimerPendienteYAnulaDuplicado() {
        Pago primero = new Pago(1L, 12L, BigDecimal.TEN, "PENDIENTE");
        Pago duplicado = new Pago(2L, 12L, BigDecimal.TEN, "PENDIENTE");
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(primero, duplicado));
        service.aprobar(12L, new BigDecimal("150.50"));
        assertThat(primero.getMontoPago()).isEqualByComparingTo("150.50");
        assertThat(duplicado.getEstadoPago()).isEqualTo("ANULADO");
        verify(repository, times(2)).save(any(Pago.class));
    }

    @Test void pagoCobradoImpideNuevoPendiente() {
        Pago pagado = new Pago(1L, 12L, BigDecimal.TEN, "PAGADO");
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(pagado));
        service.aprobar(12L, BigDecimal.TEN);
        verify(repository, never()).save(any(Pago.class));
    }

    @Test void cancelacionAnulaSoloPendientes() {
        Pago pendiente = new Pago(1L, 12L, BigDecimal.TEN, "PENDIENTE");
        Pago pagado = new Pago(2L, 12L, BigDecimal.TEN, "PAGADO");
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(pendiente, pagado));
        service.cancelarCotizacion(12L);
        assertThat(pendiente.getEstadoPago()).isEqualTo("ANULADO");
        assertThat(pagado.getEstadoPago()).isEqualTo("PAGADO");
    }

    @Test void anulacionDePagoNotificaReparaciones() {
        Pago pago = new Pago(1L, 12L, BigDecimal.TEN, "PENDIENTE");
        when(repository.save(pago)).thenReturn(pago);
        service.anularPago(pago);
        assertThat(pago.getEstadoPago()).isEqualTo("ANULADO");
        verify(rabbit).convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_PAGO_ANULADO, "12");
    }
}