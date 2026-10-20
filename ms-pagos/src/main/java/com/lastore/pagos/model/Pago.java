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

    @PrePersist
    public void asignarFechaRegistro() {
        if (fechaRegistro == null) fechaRegistro = LocalDateTime.now();
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
}
