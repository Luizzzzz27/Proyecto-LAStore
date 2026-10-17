package com.lastore.clientes.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "cliente")
public class Cliente {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "dni_ruc", nullable = false, unique = true, length = 15)
    private String dniRuc;

    @Column(nullable = false, length = 100)
    private String nombres;

    @Column(length = 20)
    private String telefono;

    @Column(length = 100)
    private String correo;

    public Cliente() { }

    public Cliente(Long id, String dniRuc, String nombres, String telefono, String correo) {
        this.id = id;
        this.dniRuc = dniRuc;
        this.nombres = nombres;
        this.telefono = telefono;
        this.correo = correo;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getDniRuc() { return dniRuc; }
    public void setDniRuc(String dniRuc) { this.dniRuc = dniRuc; }
    public String getNombres() { return nombres; }
    public void setNombres(String nombres) { this.nombres = nombres; }
    public String getTelefono() { return telefono; }
    public void setTelefono(String telefono) { this.telefono = telefono; }
    public String getCorreo() { return correo; }
    public void setCorreo(String correo) { this.correo = correo; }
}