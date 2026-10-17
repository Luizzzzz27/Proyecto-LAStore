package com.lastore.pagos.model;

import java.math.BigDecimal;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
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
}