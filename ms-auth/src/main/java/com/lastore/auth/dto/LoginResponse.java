package com.lastore.auth.dto;

public class LoginResponse {
    private Long id;
    private String username;
    private String nombreCompleto;
    private String rol;
    private String mensaje;
    private String token;

    public LoginResponse() { }
    public LoginResponse(Long id, String username, String nombreCompleto, String rol, String mensaje, String token) {
        this.id = id; this.username = username; this.nombreCompleto = nombreCompleto;
        this.rol = rol; this.mensaje = mensaje; this.token = token;
    }
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getNombreCompleto() { return nombreCompleto; }
    public void setNombreCompleto(String nombreCompleto) { this.nombreCompleto = nombreCompleto; }
    public String getRol() { return rol; }
    public void setRol(String rol) { this.rol = rol; }
    public String getMensaje() { return mensaje; }
    public void setMensaje(String mensaje) { this.mensaje = mensaje; }
    public String getToken() { return token; }
    public void setToken(String token) { this.token = token; }
}