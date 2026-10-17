[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Users\Luis\Desktop\6to ciclo\DAW 2\Proyecto-LAStore'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Captured {
    param([string]$Command, [string]$WorkingDirectory)
    Push-Location -LiteralPath $WorkingDirectory
    try {
        cmd /d /s /c "$Command 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "Falló el comando: $Command (código $LASTEXITCODE)" }
    }
    finally { Pop-Location }
}

New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null

# Maven portátil: reutiliza una distribución del wrapper si existe; de lo contrario la descarga localmente.
$mavenCommand = Get-ChildItem -Path "$env:USERPROFILE\.m2\wrapper\dists" -Filter mvn.cmd -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $mavenCommand) {
    $toolsDirectory = Join-Path $ProjectRoot '.tools'
    $mavenHome = Join-Path $toolsDirectory 'apache-maven-3.9.9'
    $mavenCommand = Join-Path $mavenHome 'bin\mvn.cmd'
    if (-not (Test-Path -LiteralPath $mavenCommand)) {
        New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
        $archive = Join-Path $toolsDirectory 'apache-maven-3.9.9-bin.zip'
        Invoke-WebRequest -Uri 'https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip' -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $toolsDirectory -Force
        Remove-Item -LiteralPath $archive -Force
    }
}

Write-Utf8File (Join-Path $ProjectRoot '.gitignore') @'
# Java / Maven
target/
*.class
*.jar
*.war
.mvn/timing.properties

# Eclipse / STS
.classpath
.project
.settings/
.metadata/
.factorypath

# IntelliJ / VS Code
.idea/
*.iml
.vscode/

# Node / Angular
node_modules/
dist/
.angular/
npm-debug.log*

# Sistema / herramientas locales
.DS_Store
Thumbs.db
.tools/
'@

Write-Utf8File (Join-Path $ProjectRoot 'init-lastore-db.sql') @'
CREATE DATABASE IF NOT EXISTS db_lastore_auth;
CREATE DATABASE IF NOT EXISTS db_lastore_clientes;
CREATE DATABASE IF NOT EXISTS db_lastore_reparaciones;
CREATE DATABASE IF NOT EXISTS db_lastore_pagos;

USE db_lastore_auth;
CREATE TABLE IF NOT EXISTS usuario (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    nombre_completo VARCHAR(120) NOT NULL,
    rol VARCHAR(30) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);
'@

$commonPomStart = @'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.4.12</version>
        <relativePath/>
    </parent>
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-eureka-server\pom.xml') ($commonPomStart + @'
    <groupId>com.lastore</groupId>
    <artifactId>ms-eureka-server</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>ms-eureka-server</name>
    <properties>
        <java.version>17</java.version>
        <maven-jar-plugin.version>3.4.2</maven-jar-plugin.version>
        <spring-cloud.version>2024.0.2</spring-cloud.version>
    </properties>
    <dependencies>
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
    <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build>
</project>
'@)

Write-Utf8File (Join-Path $ProjectRoot 'ms-eureka-server\src\main\java\com\lastore\eureka\EurekaServerApplication.java') @'
package com.lastore.eureka;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;

@EnableEurekaServer
@SpringBootApplication
public class EurekaServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(EurekaServerApplication.class, args);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-eureka-server\src\main\resources\application.yml') @'
spring:
  application:
    name: ms-eureka-server
server:
  port: 8761
eureka:
  client:
    register-with-eureka: false
    fetch-registry: false
  server:
    enable-self-preservation: false
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-api-gateway\pom.xml') ($commonPomStart + @'
    <groupId>com.lastore</groupId>
    <artifactId>ms-api-gateway</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>ms-api-gateway</name>
    <properties>
        <java.version>17</java.version>
        <maven-jar-plugin.version>3.4.2</maven-jar-plugin.version>
        <spring-cloud.version>2024.0.2</spring-cloud.version>
    </properties>
    <dependencies>
        <dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-gateway</artifactId></dependency>
        <dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-netflix-eureka-client</artifactId></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
    </dependencies>
    <dependencyManagement><dependencies><dependency>
        <groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-dependencies</artifactId>
        <version>${spring-cloud.version}</version><type>pom</type><scope>import</scope>
    </dependency></dependencies></dependencyManagement>
    <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build>
</project>
'@)

Write-Utf8File (Join-Path $ProjectRoot 'ms-api-gateway\src\main\java\com\lastore\gateway\ApiGatewayApplication.java') @'
package com.lastore.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ApiGatewayApplication {
    public static void main(String[] args) {
        SpringApplication.run(ApiGatewayApplication.class, args);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-api-gateway\src\main\resources\application.yml') @'
server:
  port: 8080
spring:
  application:
    name: ms-api-gateway
  cloud:
    gateway:
      routes:
        - id: ms-auth
          uri: lb://ms-auth
          predicates:
            - Path=/api/v1/auth/**
        - id: ms-clientes
          uri: lb://ms-clientes
          predicates:
            - Path=/api/v1/clientes/**
        - id: ms-reparaciones
          uri: lb://ms-reparaciones
          predicates:
            - Path=/api/v1/tickets/**
        - id: ms-pagos
          uri: lb://ms-pagos
          predicates:
            - Path=/api/v1/pagos/**
      globalcors:
        add-to-simple-url-handler-mapping: true
        cors-configurations:
          '[/**]':
            allowedOrigins:
              - http://localhost:4200
              - http://127.0.0.1:4200
            allowedMethods: [GET, POST, PUT, DELETE, OPTIONS]
            allowedHeaders: '*'
eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\pom.xml') ($commonPomStart + @'
    <groupId>com.lastore</groupId>
    <artifactId>ms-auth</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>ms-auth</name>
    <properties>
        <java.version>17</java.version>
        <maven-jar-plugin.version>3.4.2</maven-jar-plugin.version>
        <spring-cloud.version>2024.0.2</spring-cloud.version>
    </properties>
    <dependencies>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-security</artifactId></dependency>
        <dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-netflix-eureka-client</artifactId></dependency>
        <dependency><groupId>com.mysql</groupId><artifactId>mysql-connector-j</artifactId><scope>runtime</scope></dependency>
        <dependency><groupId>com.h2database</groupId><artifactId>h2</artifactId><scope>test</scope></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
        <dependency><groupId>org.springframework.security</groupId><artifactId>spring-security-test</artifactId><scope>test</scope></dependency>
    </dependencies>
    <dependencyManagement><dependencies><dependency>
        <groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-dependencies</artifactId>
        <version>${spring-cloud.version}</version><type>pom</type><scope>import</scope>
    </dependency></dependencies></dependencyManagement>
    <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build>
</project>
'@)

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\AuthApplication.java') @'
package com.lastore.auth;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class AuthApplication {
    public static void main(String[] args) {
        SpringApplication.run(AuthApplication.class, args);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\config\SecurityConfig.java') @'
package com.lastore.auth.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class SecurityConfig {
    @Bean
    public BCryptPasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http.csrf(csrf -> csrf.disable())
            .authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
        return http.build();
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\model\Usuario.java') @'
package com.lastore.auth.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "usuario")
public class Usuario {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 50)
    private String username;

    @Column(nullable = false, length = 255)
    private String password;

    @Column(name = "nombre_completo", nullable = false, length = 120)
    private String nombreCompleto;

    @Column(nullable = false, length = 30)
    private String rol;

    @Column(nullable = false)
    private boolean activo = true;

    public Usuario() { }

    public Usuario(Long id, String username, String password, String nombreCompleto, String rol, boolean activo) {
        this.id = id;
        this.username = username;
        this.password = password;
        this.nombreCompleto = nombreCompleto;
        this.rol = rol;
        this.activo = activo;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
    public String getNombreCompleto() { return nombreCompleto; }
    public void setNombreCompleto(String nombreCompleto) { this.nombreCompleto = nombreCompleto; }
    public String getRol() { return rol; }
    public void setRol(String rol) { this.rol = rol; }
    public boolean isActivo() { return activo; }
    public void setActivo(boolean activo) { this.activo = activo; }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\repository\UsuarioRepository.java') @'
package com.lastore.auth.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.auth.model.Usuario;

public interface UsuarioRepository extends JpaRepository<Usuario, Long> {
    Optional<Usuario> findByUsername(String username);
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\dto\LoginRequest.java') @'
package com.lastore.auth.dto;

public class LoginRequest {
    private String username;
    private String password;

    public LoginRequest() { }
    public LoginRequest(String username, String password) { this.username = username; this.password = password; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\dto\LoginResponse.java') @'
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
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\dto\ErrorResponse.java') @'
package com.lastore.auth.dto;

public class ErrorResponse {
    private String mensaje;
    public ErrorResponse() { }
    public ErrorResponse(String mensaje) { this.mensaje = mensaje; }
    public String getMensaje() { return mensaje; }
    public void setMensaje(String mensaje) { this.mensaje = mensaje; }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\config\DataInitializer.java') @'
package com.lastore.auth.config;

import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;
import com.lastore.auth.model.Usuario;
import com.lastore.auth.repository.UsuarioRepository;

@Component
public class DataInitializer implements CommandLineRunner {
    private final UsuarioRepository usuarioRepository;
    private final BCryptPasswordEncoder passwordEncoder;

    public DataInitializer(UsuarioRepository usuarioRepository, BCryptPasswordEncoder passwordEncoder) {
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(String... args) {
        if (usuarioRepository.count() == 0) {
            usuarioRepository.save(new Usuario(null, "admin", passwordEncoder.encode("admin123"),
                "Luis Gonzales - Administrador LA Store", "ADMIN", true));
            usuarioRepository.save(new Usuario(null, "tecnico", passwordEncoder.encode("tecnico123"),
                "Especialista Soporte Técnico", "TECNICO", true));
        }
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\java\com\lastore\auth\controller\AuthController.java') @'
package com.lastore.auth.controller;

import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.lastore.auth.dto.ErrorResponse;
import com.lastore.auth.dto.LoginRequest;
import com.lastore.auth.dto.LoginResponse;
import com.lastore.auth.model.Usuario;
import com.lastore.auth.repository.UsuarioRepository;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final UsuarioRepository usuarioRepository;
    private final BCryptPasswordEncoder passwordEncoder;

    public AuthController(UsuarioRepository usuarioRepository, BCryptPasswordEncoder passwordEncoder) {
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody LoginRequest request) {
        if (request == null || isBlank(request.getUsername()) || isBlank(request.getPassword())) {
            return ResponseEntity.badRequest().body(new ErrorResponse("Username y password son obligatorios"));
        }
        return usuarioRepository.findByUsername(request.getUsername().trim())
            .filter(Usuario::isActivo)
            .filter(user -> passwordEncoder.matches(request.getPassword(), user.getPassword()))
            .<ResponseEntity<?>>map(user -> ResponseEntity.ok(new LoginResponse(user.getId(), user.getUsername(),
                user.getNombreCompleto(), user.getRol(), "Autenticación exitosa en LA Store", UUID.randomUUID().toString())))
            .orElseGet(() -> ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("Credenciales inválidas o usuario inactivo")));
    }

    @GetMapping("/usuarios")
    public List<Usuario> listar() { return usuarioRepository.findAll(); }

    @GetMapping("/usuarios/{id}")
    public ResponseEntity<?> obtener(@PathVariable Long id) {
        return usuarioRepository.findById(id).<ResponseEntity<?>>map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse("Usuario no encontrado")));
    }

    @PostMapping("/usuarios")
    public ResponseEntity<?> crear(@RequestBody Usuario usuario) {
        if (usuario == null || isBlank(usuario.getUsername()) || isBlank(usuario.getPassword())
                || isBlank(usuario.getNombreCompleto()) || isBlank(usuario.getRol())) {
            return ResponseEntity.badRequest().body(new ErrorResponse("Username, password, nombreCompleto y rol son obligatorios"));
        }
        if (usuarioRepository.findByUsername(usuario.getUsername().trim()).isPresent()) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse("El username ya existe"));
        }
        usuario.setId(null);
        usuario.setUsername(usuario.getUsername().trim());
        usuario.setPassword(passwordEncoder.encode(usuario.getPassword()));
        return ResponseEntity.status(HttpStatus.CREATED).body(usuarioRepository.save(usuario));
    }

    @PutMapping("/usuarios/{id}")
    public ResponseEntity<?> actualizar(@PathVariable Long id, @RequestBody Usuario datos) {
        return usuarioRepository.findById(id).<ResponseEntity<?>>map(usuario -> {
            if (!isBlank(datos.getUsername())) usuario.setUsername(datos.getUsername().trim());
            if (!isBlank(datos.getNombreCompleto())) usuario.setNombreCompleto(datos.getNombreCompleto());
            if (!isBlank(datos.getRol())) usuario.setRol(datos.getRol());
            usuario.setActivo(datos.isActivo());
            if (!isBlank(datos.getPassword())) usuario.setPassword(passwordEncoder.encode(datos.getPassword()));
            return ResponseEntity.ok(usuarioRepository.save(usuario));
        }).orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse("Usuario no encontrado")));
    }

    @DeleteMapping("/usuarios/{id}")
    public ResponseEntity<?> eliminar(@PathVariable Long id) {
        if (!usuarioRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse("Usuario no encontrado"));
        }
        usuarioRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private boolean isBlank(String value) { return value == null || value.isBlank(); }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\main\resources\application.yml') @'
server:
  port: 8081
spring:
  application:
    name: ms-auth
  datasource:
    url: jdbc:mysql://localhost:3306/db_lastore_auth?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
    username: root
    password: Laga_1127
    driver-class-name: com.mysql.cj.jdbc.Driver
  jpa:
    hibernate:
      ddl-auto: update
    open-in-view: false
eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\test\resources\application.yml') @'
spring:
  datasource:
    url: jdbc:h2:mem:lastore_test;MODE=MySQL;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE
    driver-class-name: org.h2.Driver
    username: sa
    password:
  jpa:
    hibernate:
      ddl-auto: create-drop
eureka:
  client:
    enabled: false
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-auth\src\test\java\com\lastore\auth\repository\UsuarioCrudTest.java') @'
package com.lastore.auth.repository;

import static org.assertj.core.api.Assertions.assertThat;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import com.lastore.auth.model.Usuario;

@DataJpaTest
class UsuarioCrudTest {
    @Autowired
    private UsuarioRepository usuarioRepository;
    private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

    @Test
    void insertarUsuarioConPasswordCifrada() {
        Usuario guardado = usuarioRepository.saveAndFlush(nuevoUsuario("nuevo", "clave123"));
        assertThat(guardado.getId()).isNotNull();
        assertThat(guardado.getPassword()).isNotEqualTo("clave123");
        assertThat(passwordEncoder.matches("clave123", guardado.getPassword())).isTrue();
    }

    @Test
    void actualizarUsuarioExistente() {
        Usuario guardado = usuarioRepository.saveAndFlush(nuevoUsuario("actualizar", "original"));
        guardado.setNombreCompleto("Nombre actualizado");
        guardado.setRol("ADMIN");
        Usuario actualizado = usuarioRepository.saveAndFlush(guardado);
        assertThat(usuarioRepository.findById(actualizado.getId())).get()
            .extracting(Usuario::getNombreCompleto, Usuario::getRol)
            .containsExactly("Nombre actualizado", "ADMIN");
    }

    @Test
    void eliminarUsuario() {
        Usuario guardado = usuarioRepository.saveAndFlush(nuevoUsuario("eliminar", "clave"));
        usuarioRepository.deleteById(guardado.getId());
        usuarioRepository.flush();
        assertThat(usuarioRepository.findById(guardado.getId())).isEmpty();
    }

    @Test
    void listarUsuariosYValidarHashBcrypt() {
        usuarioRepository.saveAndFlush(nuevoUsuario("lista1", "secreto1"));
        usuarioRepository.saveAndFlush(nuevoUsuario("lista2", "secreto2"));
        List<Usuario> usuarios = usuarioRepository.findAll();
        assertThat(usuarios).hasSize(2);
        assertThat(passwordEncoder.matches("secreto1", usuarioRepository.findByUsername("lista1").orElseThrow().getPassword())).isTrue();
        assertThat(passwordEncoder.matches("secreto2", usuarioRepository.findByUsername("lista2").orElseThrow().getPassword())).isTrue();
    }

    private Usuario nuevoUsuario(String username, String rawPassword) {
        return new Usuario(null, username, passwordEncoder.encode(rawPassword), "Usuario de prueba", "TECNICO", true);
    }
}
'@

# Copia este automatizador al entregable antes de versionar.
$thisScript = $MyInvocation.MyCommand.Path
$destinationScript = Join-Path $ProjectRoot 'fase1-lastore.ps1'
if ($thisScript -and ([System.IO.Path]::GetFullPath($thisScript) -ne [System.IO.Path]::GetFullPath($destinationScript))) {
    Copy-Item -LiteralPath $thisScript -Destination $destinationScript -Force
}

Invoke-Captured 'git init' $ProjectRoot

$services = @('ms-eureka-server', 'ms-api-gateway', 'ms-auth')
foreach ($service in $services) {
    Write-Host "`n=== Compilando $service ===" -ForegroundColor Cyan
    $servicePath = Join-Path $ProjectRoot $service
    Invoke-Captured ('"' + $mavenCommand + '" clean test install') $servicePath
}

Invoke-Captured 'git add .' $ProjectRoot
$commitCountOutput = cmd /d /s /c "git -C `"$ProjectRoot`" rev-list --all --count 2>&1"
$commitCount = if ($LASTEXITCODE -eq 0) { [int](($commitCountOutput | Select-Object -Last 1).Trim()) } else { 0 }
$commitMessage = 'feat(fase1): add eureka, gateway with cors, and ms-auth with bcrypt login and crud tests'
$staged = cmd /d /s /c "git -C `"$ProjectRoot`" diff --cached --quiet 2>&1"
$hasStagedChanges = $LASTEXITCODE -ne 0
if ($hasStagedChanges) {
    Invoke-Captured ('git commit -m "' + $commitMessage + '"') $ProjectRoot
}
$finalCommitCountOutput = cmd /d /s /c "git -C `"$ProjectRoot`" rev-list --all --count 2>&1"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar el historial de commits.' }
$finalCommitCount = [int](($finalCommitCountOutput | Select-Object -Last 1).Trim())
if ($finalCommitCount -le $commitCount -and $hasStagedChanges) { throw 'El commit esperado no fue creado.' }

Write-Host "`nFASE 1 COMPLETADA" -ForegroundColor Green
Write-Host "Proyectos compilados: $($services -join ', ')"
Write-Host "Commits en el repositorio: $finalCommitCount"
