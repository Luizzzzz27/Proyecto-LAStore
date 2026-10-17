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

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
    throw "No se encontró el repositorio de la Fase 1 en $ProjectRoot"
}

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

Write-Utf8File (Join-Path $ProjectRoot 'fase2-lastore-db.sql') @'
USE db_lastore_clientes;
CREATE TABLE IF NOT EXISTS cliente (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    dni_ruc VARCHAR(15) NOT NULL UNIQUE,
    nombres VARCHAR(100) NOT NULL,
    telefono VARCHAR(20),
    correo VARCHAR(100)
);

USE db_lastore_reparaciones;
CREATE TABLE IF NOT EXISTS ticket (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cliente_id BIGINT NOT NULL,
    tipo_equipo VARCHAR(50) NOT NULL,
    marca_modelo VARCHAR(100) NOT NULL,
    falla_reportada VARCHAR(255) NOT NULL,
    estado_cotizacion VARCHAR(50) NOT NULL DEFAULT 'PENDIENTE_ENVIO',
    monto_total DECIMAL(10,2) NOT NULL DEFAULT 0.00
);

USE db_lastore_pagos;
CREATE TABLE IF NOT EXISTS pago (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    ticket_id BIGINT NOT NULL,
    monto_pago DECIMAL(10,2) NOT NULL,
    estado_pago VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE'
);
'@

function New-ServicePom {
    param([string]$Service, [bool]$WithAmqp)
    $amqpDependency = if ($WithAmqp) { @'
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-amqp</artifactId></dependency>
'@ } else { '' }
    $pom = @"
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
    <groupId>com.lastore</groupId>
    <artifactId>$Service</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>$Service</name>
    <properties>
        <java.version>17</java.version>
        <maven-jar-plugin.version>3.4.2</maven-jar-plugin.version>
        <spring-cloud.version>2024.0.2</spring-cloud.version>
    </properties>
    <dependencies>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
        <dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-netflix-eureka-client</artifactId></dependency>
$amqpDependency        <dependency><groupId>com.mysql</groupId><artifactId>mysql-connector-j</artifactId><scope>runtime</scope></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
    </dependencies>
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>`${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>
    <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build>
</project>
"@
    Write-Utf8File (Join-Path $ProjectRoot "$Service\pom.xml") $pom
}

New-ServicePom 'ms-clientes' $false
New-ServicePom 'ms-reparaciones' $true
New-ServicePom 'ms-pagos' $true

Write-Utf8File (Join-Path $ProjectRoot 'ms-clientes\src\main\java\com\lastore\clientes\ClientesApplication.java') @'
package com.lastore.clientes;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ClientesApplication {
    public static void main(String[] args) {
        SpringApplication.run(ClientesApplication.class, args);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-clientes\src\main\java\com\lastore\clientes\model\Cliente.java') @'
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
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-clientes\src\main\java\com\lastore\clientes\repository\ClienteRepository.java') @'
package com.lastore.clientes.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.clientes.model.Cliente;

public interface ClienteRepository extends JpaRepository<Cliente, Long> { }
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-clientes\src\main\java\com\lastore\clientes\controller\ClienteController.java') @'
package com.lastore.clientes.controller;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import com.lastore.clientes.model.Cliente;
import com.lastore.clientes.repository.ClienteRepository;

@RestController
@RequestMapping("/api/v1/clientes")
public class ClienteController {
    private final ClienteRepository clienteRepository;

    public ClienteController(ClienteRepository clienteRepository) {
        this.clienteRepository = clienteRepository;
    }

    @GetMapping
    public List<Cliente> listar() { return clienteRepository.findAll(); }

    @GetMapping("/{id}")
    public Cliente obtener(@PathVariable Long id) {
        return clienteRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Cliente no encontrado"));
    }

    @PostMapping
    public ResponseEntity<Cliente> crear(@RequestBody Cliente cliente) {
        cliente.setId(null);
        return ResponseEntity.status(HttpStatus.CREATED).body(clienteRepository.save(cliente));
    }

    @PutMapping("/{id}")
    public Cliente actualizar(@PathVariable Long id, @RequestBody Cliente datos) {
        Cliente cliente = obtener(id);
        cliente.setDniRuc(datos.getDniRuc());
        cliente.setNombres(datos.getNombres());
        cliente.setTelefono(datos.getTelefono());
        cliente.setCorreo(datos.getCorreo());
        return clienteRepository.save(cliente);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        Cliente cliente = obtener(id);
        clienteRepository.delete(cliente);
        return ResponseEntity.noContent().build();
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-clientes\src\main\resources\application.yml') @'
server:
  port: 8082
spring:
  application:
    name: ms-clientes
  datasource:
    url: jdbc:mysql://localhost:3306/db_lastore_clientes?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
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

Write-Utf8File (Join-Path $ProjectRoot 'ms-reparaciones\src\main\java\com\lastore\reparaciones\ReparacionesApplication.java') @'
package com.lastore.reparaciones;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ReparacionesApplication {
    public static void main(String[] args) {
        SpringApplication.run(ReparacionesApplication.class, args);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-reparaciones\src\main\java\com\lastore\reparaciones\model\Ticket.java') @'
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
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-reparaciones\src\main\java\com\lastore\reparaciones\repository\TicketRepository.java') @'
package com.lastore.reparaciones.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.reparaciones.model.Ticket;

public interface TicketRepository extends JpaRepository<Ticket, Long> { }
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-reparaciones\src\main\java\com\lastore\reparaciones\config\RabbitMQConfig.java') @'
package com.lastore.reparaciones.config;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {
    public static final String COLA_COTIZACION_APROBADA = "q.lastore.cotizacion.aprobada";

    @Bean
    public Queue colaCotizacionAprobada() {
        return new Queue(COLA_COTIZACION_APROBADA, true);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-reparaciones\src\main\java\com\lastore\reparaciones\controller\TicketController.java') @'
package com.lastore.reparaciones.controller;

import java.math.BigDecimal;
import java.util.List;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;

@RestController
@RequestMapping("/api/v1/tickets")
public class TicketController {
    private final TicketRepository ticketRepository;
    private final RabbitTemplate rabbitTemplate;

    public TicketController(TicketRepository ticketRepository, RabbitTemplate rabbitTemplate) {
        this.ticketRepository = ticketRepository;
        this.rabbitTemplate = rabbitTemplate;
    }

    @GetMapping
    public List<Ticket> listar() { return ticketRepository.findAll(); }

    @GetMapping("/{id}")
    public Ticket obtener(@PathVariable Long id) {
        return ticketRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Ticket no encontrado"));
    }

    @PostMapping
    public ResponseEntity<Ticket> crear(@RequestBody Ticket ticket) {
        ticket.setId(null);
        if (ticket.getEstadoCotizacion() == null || ticket.getEstadoCotizacion().isBlank()) {
            ticket.setEstadoCotizacion("PENDIENTE_ENVIO");
        }
        if (ticket.getMontoTotal() == null) ticket.setMontoTotal(BigDecimal.ZERO);
        return ResponseEntity.status(HttpStatus.CREATED).body(ticketRepository.save(ticket));
    }

    @PutMapping("/{id}")
    public Ticket actualizar(@PathVariable Long id, @RequestBody Ticket datos) {
        Ticket ticket = obtener(id);
        ticket.setClienteId(datos.getClienteId());
        ticket.setTipoEquipo(datos.getTipoEquipo());
        ticket.setMarcaModelo(datos.getMarcaModelo());
        ticket.setFallaReportada(datos.getFallaReportada());
        ticket.setEstadoCotizacion(datos.getEstadoCotizacion());
        ticket.setMontoTotal(datos.getMontoTotal());
        return ticketRepository.save(ticket);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        Ticket ticket = obtener(id);
        ticketRepository.delete(ticket);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{id}/aprobar-cotizacion")
    public ResponseEntity<Ticket> aprobarCotizacion(@PathVariable Long id) {
        Ticket ticket = obtener(id);
        ticket.setEstadoCotizacion("APROBADA");
        Ticket guardado = ticketRepository.save(ticket);
        if (guardado.getMontoTotal() != null && guardado.getMontoTotal().compareTo(BigDecimal.ZERO) > 0) {
            String mensaje = guardado.getId() + ":" + guardado.getMontoTotal().toPlainString();
            rabbitTemplate.convertAndSend(RabbitMQConfig.COLA_COTIZACION_APROBADA, mensaje);
        }
        return ResponseEntity.ok(guardado);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-reparaciones\src\main\resources\application.yml') @'
server:
  port: 8083
spring:
  application:
    name: ms-reparaciones
  datasource:
    url: jdbc:mysql://localhost:3306/db_lastore_reparaciones?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
    username: root
    password: Laga_1127
    driver-class-name: com.mysql.cj.jdbc.Driver
  jpa:
    hibernate:
      ddl-auto: update
    open-in-view: false
  rabbitmq:
    host: localhost
    port: 5672
    username: guest
    password: guest
eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\java\com\lastore\pagos\PagosApplication.java') @'
package com.lastore.pagos;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.amqp.rabbit.annotation.EnableRabbit;

@EnableRabbit
@SpringBootApplication
public class PagosApplication {
    public static void main(String[] args) {
        SpringApplication.run(PagosApplication.class, args);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\java\com\lastore\pagos\model\Pago.java') @'
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
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\java\com\lastore\pagos\repository\PagoRepository.java') @'
package com.lastore.pagos.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.pagos.model.Pago;

public interface PagoRepository extends JpaRepository<Pago, Long> { }
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\java\com\lastore\pagos\config\RabbitMQConfig.java') @'
package com.lastore.pagos.config;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {
    public static final String COLA_COTIZACION_APROBADA = "q.lastore.cotizacion.aprobada";

    @Bean
    public Queue colaCotizacionAprobada() {
        return new Queue(COLA_COTIZACION_APROBADA, true);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\java\com\lastore\pagos\messaging\RabbitMQListener.java') @'
package com.lastore.pagos.messaging;

import java.math.BigDecimal;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;

@Component
public class RabbitMQListener {
    private static final Logger LOGGER = LoggerFactory.getLogger(RabbitMQListener.class);
    private final PagoRepository pagoRepository;

    public RabbitMQListener(PagoRepository pagoRepository) {
        this.pagoRepository = pagoRepository;
    }

    @RabbitListener(queues = RabbitMQConfig.COLA_COTIZACION_APROBADA)
    public void recibirCotizacionAprobada(String mensaje) {
        String[] valores = mensaje.split(":");
        if (valores.length != 2) {
            throw new IllegalArgumentException("Formato de mensaje inválido: " + mensaje);
        }
        Long ticketId = Long.parseLong(valores[0]);
        BigDecimal montoTotal = new BigDecimal(valores[1]);
        Pago pago = pagoRepository.save(new Pago(null, ticketId, montoTotal, "PENDIENTE"));
        LOGGER.info("Cobro pendiente creado: pagoId={}, ticketId={}, monto={}",
            pago.getId(), pago.getTicketId(), pago.getMontoPago());
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\java\com\lastore\pagos\controller\PagoController.java') @'
package com.lastore.pagos.controller;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;

@RestController
@RequestMapping("/api/v1/pagos")
public class PagoController {
    private final PagoRepository pagoRepository;

    public PagoController(PagoRepository pagoRepository) {
        this.pagoRepository = pagoRepository;
    }

    @GetMapping
    public List<Pago> listar() { return pagoRepository.findAll(); }

    @GetMapping("/{id}")
    public Pago obtener(@PathVariable Long id) {
        return pagoRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Pago no encontrado"));
    }

    @PostMapping
    public ResponseEntity<Pago> crear(@RequestBody Pago pago) {
        pago.setId(null);
        if (pago.getEstadoPago() == null || pago.getEstadoPago().isBlank()) pago.setEstadoPago("PENDIENTE");
        return ResponseEntity.status(HttpStatus.CREATED).body(pagoRepository.save(pago));
    }

    @PutMapping("/{id}")
    public Pago actualizar(@PathVariable Long id, @RequestBody Pago datos) {
        Pago pago = obtener(id);
        pago.setTicketId(datos.getTicketId());
        pago.setMontoPago(datos.getMontoPago());
        pago.setEstadoPago(datos.getEstadoPago());
        return pagoRepository.save(pago);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        Pago pago = obtener(id);
        pagoRepository.delete(pago);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{id}/procesar")
    public ResponseEntity<Pago> procesar(@PathVariable Long id) {
        Pago pago = obtener(id);
        pago.setEstadoPago("PAGADO");
        return ResponseEntity.ok(pagoRepository.save(pago));
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\resources\application.yml') @'
server:
  port: 8084
spring:
  application:
    name: ms-pagos
  datasource:
    url: jdbc:mysql://localhost:3306/db_lastore_pagos?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
    username: root
    password: Laga_1127
    driver-class-name: com.mysql.cj.jdbc.Driver
  jpa:
    hibernate:
      ddl-auto: update
    open-in-view: false
  rabbitmq:
    host: localhost
    port: 5672
    username: guest
    password: guest
eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
'@

$thisScript = $MyInvocation.MyCommand.Path
$destinationScript = Join-Path $ProjectRoot 'fase2-lastore.ps1'
if ($thisScript -and ([System.IO.Path]::GetFullPath($thisScript) -ne [System.IO.Path]::GetFullPath($destinationScript))) {
    Copy-Item -LiteralPath $thisScript -Destination $destinationScript -Force
}

foreach ($service in @('ms-clientes', 'ms-reparaciones', 'ms-pagos')) {
    Write-Host "`n=== Compilando $service ===" -ForegroundColor Cyan
    Invoke-Captured ('"' + $mavenCommand + '" clean install -DskipTests') (Join-Path $ProjectRoot $service)
}

Invoke-Captured 'git add .' $ProjectRoot
$beforeOutput = cmd /d /s /c "git -C `"$ProjectRoot`" rev-list --all --count 2>&1"
$before = if ($LASTEXITCODE -eq 0) { [int](($beforeOutput | Select-Object -Last 1).Trim()) } else { 0 }
$stagedOutput = cmd /d /s /c "git -C `"$ProjectRoot`" diff --cached --quiet 2>&1"
if ($LASTEXITCODE -ne 0) {
    Invoke-Captured 'git commit -m "feat(fase2): add ms-clientes, ms-reparaciones and ms-pagos with rabbitmq integration and full CRUD"' $ProjectRoot
}
$afterOutput = cmd /d /s /c "git -C `"$ProjectRoot`" rev-list --all --count 2>&1"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar el historial de commits.' }
$after = [int](($afterOutput | Select-Object -Last 1).Trim())
if ($after -lt $before) { throw 'El historial Git no pudo verificarse correctamente.' }

Write-Host "`nFASE 2 COMPLETADA" -ForegroundColor Green
Write-Host 'Proyectos compilados: ms-clientes, ms-reparaciones, ms-pagos'
Write-Host "Commits en el repositorio: $after"
