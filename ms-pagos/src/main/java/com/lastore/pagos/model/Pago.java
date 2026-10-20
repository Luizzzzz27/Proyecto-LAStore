package com.lastore.pagos.model;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "pago")
public class Pago {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "ticket_id", nullable = false)
    private Long ticketId;

    @Column(name = "monto_pago", nullable = false, precision = 10, scale = 2)
    private BigDecimal montoPago;

    @Column(name = "estado_pago", nullable = false, length = 20)
    private String estadoPago = "PENDIENTE";

    @Column(name = "fecha_registro", updatable = false)
    private LocalDateTime fechaRegistro;

    @Column(name = "metodo_pago", length = 50)
    private String metodoPago;

    @Column(name = "monto_pagado", precision = 10, scale = 2)
    private BigDecimal montoPagado;

    @Column(name = "referencia_pago", columnDefinition = "TEXT")
    private String referenciaPago;

    @PrePersist
    public void asignarFechaRegistro() {
        if (fechaRegistro == null) fechaRegistro = LocalDateTime.now();
        if (montoPagado == null) montoPagado = getMontoPagado();
    }

    public Pago() { }

    public Pago(Long id, Long ticketId, BigDecimal montoPago, String estadoPago) {
        this.id = id;
        this.ticketId = ticketId;
        this.montoPago = montoPago;
        this.estadoPago = estadoPago;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getTicketId() { return ticketId; }
    public void setTicketId(Long ticketId) { this.ticketId = ticketId; }
    public BigDecimal getMontoPago() { return montoPago; }
    public void setMontoPago(BigDecimal montoPago) { this.montoPago = montoPago; }
    public String getEstadoPago() { return estadoPago; }
    public void setEstadoPago(String estadoPago) { this.estadoPago = estadoPago; }
    public LocalDateTime getFechaRegistro() { return fechaRegistro; }
    public void setFechaRegistro(LocalDateTime fechaRegistro) { this.fechaRegistro = fechaRegistro; }
    public String getMetodoPago() { return metodoPago; }
    public void setMetodoPago(String metodoPago) { this.metodoPago = metodoPago; }
    // Alias público: conserva monto_pago y los consumidores anteriores de montoPago.
    public BigDecimal getMonto() { return montoPago == null ? BigDecimal.ZERO : montoPago; }
    public void setMonto(BigDecimal monto) { this.montoPago = monto; }
    public BigDecimal getMontoPagado() {
        return montoPagado != null ? montoPagado : ("PAGADO".equals(estadoPago) ? getMonto() : BigDecimal.ZERO);
    }
    public void setMontoPagado(BigDecimal montoPagado) { this.montoPagado = montoPagado; }
    public BigDecimal getSaldoPendiente() {
        return "PAGADO".equals(estadoPago) || "ANULADO".equals(estadoPago)
            ? BigDecimal.ZERO : getMonto().subtract(getMontoPagado()).max(BigDecimal.ZERO);
    }
    public String getReferenciaPago() { return referenciaPago; }
    public void setReferenciaPago(String referenciaPago) { this.referenciaPago = referenciaPago; }
}
