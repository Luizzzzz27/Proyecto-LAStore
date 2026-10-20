package com.lastore.reparaciones.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class ClienteDirectoryClientTest {
    @Test void clienteRealPermiteContinuar() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://clientes");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("http://clientes/api/v1/clientes/1")).andRespond(withStatus(HttpStatus.OK));
        new ClienteDirectoryClient(builder.build()).validar(1L);
        server.verify();
    }
    @Test void clienteInexistenteProduce400ConMensaje() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://clientes");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("http://clientes/api/v1/clientes/15")).andRespond(withStatus(HttpStatus.NOT_FOUND));
        assertThatThrownBy(() -> new ClienteDirectoryClient(builder.build()).validar(15L))
            .isInstanceOfSatisfying(ResponseStatusException.class, ex -> {
                org.assertj.core.api.Assertions.assertThat(ex.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
                org.assertj.core.api.Assertions.assertThat(ex.getReason()).isEqualTo(ClienteDirectoryClient.CLIENTE_INVALIDO);
            });
    }
    @Test void clienteObligatorioNoConsultaRed() {
        ClienteDirectoryClient client = new ClienteDirectoryClient(RestClient.create());
        assertThatThrownBy(() -> client.validar(null)).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> client.validar(0L)).isInstanceOf(ResponseStatusException.class);
    }
    @Test void directorioCaidoNoPermiteGuardarSinValidacion() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://clientes");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("http://clientes/api/v1/clientes/1")).andRespond(withStatus(HttpStatus.INTERNAL_SERVER_ERROR));
        assertThatThrownBy(() -> new ClienteDirectoryClient(builder.build()).validar(1L))
            .isInstanceOfSatisfying(ResponseStatusException.class, ex ->
                org.assertj.core.api.Assertions.assertThat(ex.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE));
    }
}
