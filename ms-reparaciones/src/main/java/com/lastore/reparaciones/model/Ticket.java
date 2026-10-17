package com.lastore.reparaciones.model;

import java.math.BigDecimal;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "ticket")
public class Ticket {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "cliente_id", nullable = false)
    private Long clienteId;

    @Column(name = "tipo_equipo", nullable = false, length = 50)
    private String tipoEquipo;

    @Column(name = "marca_modelo", nullable = false, length = 100)
    private String marcaModelo;

    @Column(name = "falla_reportada", nullable = false, length = 255)
    private String fallaReportada;

    @Column(name = "estado_cotizacion", nullable = false, length = 50)
    private String estadoCotizacion = "PENDIENTE_ENVIO";

    @Column(name = "monto_total", nullable = false, precision = 10, scale = 2)
    private BigDecimal montoTotal = BigDecimal.ZERO;

    public Ticket() { }

    public Ticket(Long id, Long clienteId, String tipoEquipo, String marcaModelo, String fallaReportada,
                  String estadoCotizacion, BigDecimal montoTotal) {
        this.id = id;
        this.clienteId = clienteId;
        this.tipoEquipo = tipoEquipo;
        this.marcaModelo = marcaModelo;
        this.fallaReportada = fallaReportada;
        this.estadoCotizacion = estadoCotizacion;
        this.montoTotal = montoTotal;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getClienteId() { return clienteId; }
    public void setClienteId(Long clienteId) { this.clienteId = clienteId; }
    public String getTipoEquipo() { return tipoEquipo; }
    public void setTipoEquipo(String tipoEquipo) { this.tipoEquipo = tipoEquipo; }
    public String getMarcaModelo() { return marcaModelo; }
    public void setMarcaModelo(String marcaModelo) { this.marcaModelo = marcaModelo; }
    public String getFallaReportada() { return fallaReportada; }
    public void setFallaReportada(String fallaReportada) { this.fallaReportada = fallaReportada; }
    public String getEstadoCotizacion() { return estadoCotizacion; }
    public void setEstadoCotizacion(String estadoCotizacion) { this.estadoCotizacion = estadoCotizacion; }
    public BigDecimal getMontoTotal() { return montoTotal; }
    public void setMontoTotal(BigDecimal montoTotal) { this.montoTotal = montoTotal; }
}