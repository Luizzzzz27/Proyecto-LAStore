package com.lastore.reparaciones.service;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ClienteDirectoryClient {
    public static final String CLIENTE_INVALIDO = "El cliente seleccionado no existe en el directorio de LA Store";
    private final RestClient client;

    public ClienteDirectoryClient(@Qualifier("clienteRestClient") RestClient client) { this.client = client; }

    public void validar(Long clienteId) {
        if (clienteId == null || clienteId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, CLIENTE_INVALIDO);
        }
        try {
            client.get().uri("/api/v1/clientes/{id}", clienteId).retrieve().toBodilessEntity();
        } catch (HttpClientErrorException.NotFound ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, CLIENTE_INVALIDO);
        } catch (RestClientException ex) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "No se pudo validar el cliente. Intente nuevamente cuando el directorio esté disponible.");
        }
    }
}
