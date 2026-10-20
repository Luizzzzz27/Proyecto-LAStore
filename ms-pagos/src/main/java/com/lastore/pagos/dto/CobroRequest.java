package com.lastore.pagos.dto;

import java.math.BigDecimal;

public class CobroRequest {
    private BigDecimal montoAbono;
    private String metodoPago;
    private String referenciaPago;

    public CobroRequest() { }
    public CobroRequest(BigDecimal montoAbono, String metodoPago, String referenciaPago) {
        this.montoAbono = montoAbono;
        this.metodoPago = metodoPago;
        this.referenciaPago = referenciaPago;
    }
    public BigDecimal getMontoAbono() { return montoAbono; }
    public void setMontoAbono(BigDecimal montoAbono) { this.montoAbono = montoAbono; }
    public String getMetodoPago() { return metodoPago; }
    public void setMetodoPago(String metodoPago) { this.metodoPago = metodoPago; }
    public String getReferenciaPago() { return referenciaPago; }
    public void setReferenciaPago(String referenciaPago) { this.referenciaPago = referenciaPago; }
}
