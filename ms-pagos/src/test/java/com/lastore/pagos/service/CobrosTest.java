package com.lastore.pagos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import java.math.BigDecimal;
import java.util.Optional;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.server.ResponseStatusException;
import com.lastore.pagos.dto.CobroRequest;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;
import com.lastore.pagos.controller.PagoController;
import com.lastore.pagos.controller.ApiExceptionHandler;

class CobrosTest {
    private final PagoRepository repository = mock(PagoRepository.class);
    private final PagoStateService service = new PagoStateService(repository, mock(RabbitTemplate.class));
    private Pago pago;
    @BeforeEach void preparar() {
        pago = new Pago(1L, 12L, new BigDecimal("100.00"), "PENDIENTE");
        when(repository.findForUpdateById(1L)).thenReturn(Optional.of(pago));
        when(repository.save(any(Pago.class))).thenAnswer(c -> c.getArgument(0));
    }
    @Test void abonoParcialYSaldoCompletoConDosMetodos() {
        service.procesar(1L, new CobroRequest(new BigDecimal("40.00"), "YAPE_PLIN", "Adelanto"));
        assertThat(pago.getEstadoPago()).isEqualTo("PARCIAL");
        assertThat(pago.getSaldoPendiente()).isEqualByComparingTo("60");
        service.procesar(1L, new CobroRequest(new BigDecimal("60.00"), "EFECTIVO", "Saldo"));
        assertThat(pago.getEstadoPago()).isEqualTo("PAGADO");
        assertThat(pago.getMontoPagado()).isEqualByComparingTo("100");
        assertThat(pago.getSaldoPendiente()).isZero();
        assertThat(pago.getMetodoPago()).isEqualTo("YAPE_PLIN / EFECTIVO");
        assertThat(pago.getReferenciaPago()).contains("Adelanto", "Saldo");
    }
    @Test void rechazaAbonosInvalidosSinGuardar() {
        for (String valor : List.of("0", "-1", "101", "0.001")) {
            assertThatThrownBy(() -> service.procesar(1L, new CobroRequest(new BigDecimal(valor), "EFECTIVO", null)))
                .isInstanceOf(ResponseStatusException.class);
        }
        verify(repository, never()).save(any());
        assertThat(pago.getMontoPagado()).isZero();
    }
    @Test void rechazaMetodoAusenteOInvalido() {
        assertThatThrownBy(() -> service.procesar(1L, new CobroRequest(BigDecimal.TEN, null, null))).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> service.procesar(1L, new CobroRequest(BigDecimal.TEN, "OTRO", null))).isInstanceOf(ResponseStatusException.class);
        verify(repository, never()).save(any());
    }
    @Test void estadosFinalizadosNoSeCobranOtraVez() {
        for (String estado : List.of("PAGADO", "ANULADO")) {
            pago.setEstadoPago(estado);
            assertThatThrownBy(() -> service.procesar(1L, null)).isInstanceOf(ResponseStatusException.class);
        }
    }
    @Test void pagadoHistoricoSinMontoAbonadoConservaTotal() {
        pago.setEstadoPago("PAGADO");
        assertThat(pago.getMontoPagado()).isEqualByComparingTo("100");
        service.anular(1L);
        assertThat(pago.getMontoPagado()).isEqualByComparingTo("100");
        assertThat(pago.getSaldoPendiente()).isZero();
    }
    @Test void reaprobacionNoDuplicaNiPierdeAdelanto() {
        service.procesar(1L, new CobroRequest(new BigDecimal("40"), "TARJETA", null));
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(pago));
        service.aprobar(12L, new BigDecimal("120"));
        assertThat(pago.getMontoPagado()).isEqualByComparingTo("40");
        assertThat(pago.getSaldoPendiente()).isEqualByComparingTo("80");
        assertThat(pago.getEstadoPago()).isEqualTo("PARCIAL");
        verify(repository, times(2)).save(pago);
    }
    @Test void cancelacionParcialConservaAbonado() {
        service.procesar(1L, new CobroRequest(new BigDecimal("40"), "TARJETA", null));
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(pago));
        service.cancelarCotizacion(12L);
        assertThat(pago.getEstadoPago()).isEqualTo("ANULADO");
        assertThat(pago.getMontoPagado()).isEqualByComparingTo("40");
        assertThat(pago.getSaldoPendiente()).isZero();
    }
    @Test void endpointSinBodyCobraTotalConEfectivo() throws Exception {
        MockMvcBuilders.standaloneSetup(new PagoController(repository, service))
            .setControllerAdvice(new ApiExceptionHandler()).build()
            .perform(put("/api/v1/pagos/1/procesar")).andExpect(status().isOk());
        assertThat(pago.getEstadoPago()).isEqualTo("PAGADO");
        assertThat(pago.getMetodoPago()).isEqualTo("EFECTIVO");
    }
    @Test void endpointBodyVacioExigeMetodoYMonto() throws Exception {
        MockMvcBuilders.standaloneSetup(new PagoController(repository, service))
            .setControllerAdvice(new ApiExceptionHandler()).build()
            .perform(put("/api/v1/pagos/1/procesar").contentType(MediaType.APPLICATION_JSON).content("{}"))
            .andExpect(status().isBadRequest());
    }
    @Test void abonosNoAcumulanErrorDecimal() {
        pago.setMonto(new BigDecimal("0.30"));
        service.procesar(1L, new CobroRequest(new BigDecimal("0.10"), "EFECTIVO", null));
        service.procesar(1L, new CobroRequest(new BigDecimal("0.20"), "EFECTIVO", null));
        assertThat(pago.getMontoPagado()).isEqualByComparingTo("0.30");
        assertThat(pago.getEstadoPago()).isEqualTo("PAGADO");
    }
}
