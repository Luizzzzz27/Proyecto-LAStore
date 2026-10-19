package com.lastore.reparaciones.model;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

public enum EstadoCotizacion {
    PENDIENTE_ENVIO, ENVIADA, APROBADA, RECHAZADA, ANULADA;

    public static EstadoCotizacion desde(String value) {
        try { return EstadoCotizacion.valueOf(value); }
        catch (IllegalArgumentException | NullPointerException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Estado de cotización inválido: " + value);
        }
    }

    public void validarTransicion(EstadoCotizacion siguiente) {
        if (this == ANULADA && siguiente != ANULADA) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Una cotización anulada no puede reactivarse");
        }
    }
}