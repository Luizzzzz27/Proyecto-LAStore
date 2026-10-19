[CmdletBinding()]
param([string]$ProjectRoot = 'C:\Users\Luis\Desktop\6to ciclo\DAW 2\Proyecto-LAStore')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Source([string]$RelativePath, [string]$Content) {
    $path = Join-Path $ProjectRoot $RelativePath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Captured([string]$Executable, [string[]]$Arguments, [string]$Directory) {
    Push-Location -LiteralPath $Directory
    try {
        & $Executable @Arguments 2>&1 | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0) { throw "$Executable terminó con código $LASTEXITCODE" }
    } finally { Pop-Location }
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) { throw "Repositorio no encontrado: $ProjectRoot" }
$maven = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.m2\wrapper\dists') -Filter mvn.cmd -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $maven) { $maven = (Get-Command mvn.cmd -ErrorAction SilentlyContinue).Source }
if (-not $maven) { throw 'Maven no está disponible.' }

# Windows bloquea los JAR en ejecución; detener solo las instancias identificadas antes de mvn clean.
foreach ($service in @(@{Name='ms-reparaciones';Port=8083}, @{Name='ms-pagos';Port=8084})) {
    $connection = Get-NetTCPConnection -LocalPort $service.Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($connection) {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($connection.OwningProcess)" -ErrorAction SilentlyContinue
        if ($processInfo -and $processInfo.Name -match '^java(w)?\.exe$' -and $processInfo.CommandLine -like "*$($service.Name)*") {
            Stop-Process -Id $connection.OwningProcess -Force
            Start-Sleep -Seconds 2
        } else {
            throw "Puerto $($service.Port) ocupado por un proceso no identificado como $($service.Name)."
        }
    }
}

Write-Source 'ms-reparaciones\src\main\java\com\lastore\reparaciones\config\RabbitMQConfig.java' @'
package com.lastore.reparaciones.config;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {
    public static final String APROBADA = "q.lastore.cotizacion.aprobada";
    public static final String CANCELADA = "q.lastore.cotizacion.cancelada";
    public static final String PAGO_ANULADO = "q.lastore.pago.anulado";

    @Bean public Queue cotizacionAprobada() { return new Queue(APROBADA, true); }
    @Bean public Queue cotizacionCancelada() { return new Queue(CANCELADA, true); }
    @Bean public Queue pagoAnulado() { return new Queue(PAGO_ANULADO, true); }
}
'@

Write-Source 'ms-reparaciones\src\main\java\com\lastore\reparaciones\model\EstadoCotizacion.java' @'
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
'@

Write-Source 'ms-reparaciones\src\main\java\com\lastore\reparaciones\service\TicketStateService.java' @'
package com.lastore.reparaciones.service;

import java.math.BigDecimal;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.model.EstadoCotizacion;
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;

@Service
public class TicketStateService {
    private final TicketRepository ticketRepository;
    private final RabbitTemplate rabbitTemplate;

    public TicketStateService(TicketRepository ticketRepository, RabbitTemplate rabbitTemplate) {
        this.ticketRepository = ticketRepository;
        this.rabbitTemplate = rabbitTemplate;
    }

    public Ticket obtener(Long id) {
        return ticketRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Ticket no encontrado"));
    }

    public Ticket crear(Ticket ticket) {
        ticket.setId(null);
        if (ticket.getEstadoCotizacion() == null || ticket.getEstadoCotizacion().isBlank()) {
            ticket.setEstadoCotizacion(EstadoCotizacion.PENDIENTE_ENVIO.name());
        }
        EstadoCotizacion.desde(ticket.getEstadoCotizacion());
        if (ticket.getMontoTotal() == null) ticket.setMontoTotal(BigDecimal.ZERO);
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public Ticket actualizar(Long id, Ticket datos) {
        Ticket ticket = obtener(id);
        EstadoCotizacion anterior = EstadoCotizacion.desde(ticket.getEstadoCotizacion());
        EstadoCotizacion siguiente = EstadoCotizacion.desde(datos.getEstadoCotizacion());
        anterior.validarTransicion(siguiente);
        ticket.setClienteId(datos.getClienteId());
        ticket.setTipoEquipo(datos.getTipoEquipo());
        ticket.setMarcaModelo(datos.getMarcaModelo());
        ticket.setFallaReportada(datos.getFallaReportada());
        ticket.setEstadoCotizacion(siguiente.name());
        ticket.setMontoTotal(datos.getMontoTotal());
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public Ticket aprobar(Long id) {
        Ticket ticket = obtener(id);
        EstadoCotizacion.desde(ticket.getEstadoCotizacion()).validarTransicion(EstadoCotizacion.APROBADA);
        ticket.setEstadoCotizacion(EstadoCotizacion.APROBADA.name());
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public Ticket anular(Long id) {
        Ticket ticket = obtener(id);
        ticket.setEstadoCotizacion(EstadoCotizacion.ANULADA.name());
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public void anularDesdePago(Long ticketId) {
        ticketRepository.findById(ticketId).ifPresent(ticket -> {
            ticket.setEstadoCotizacion(EstadoCotizacion.ANULADA.name());
            ticketRepository.save(ticket);
        });
    }

    public void sincronizarEstadoConPagos(Ticket ticket) {
        EstadoCotizacion estado = EstadoCotizacion.desde(ticket.getEstadoCotizacion());
        if (estado == EstadoCotizacion.APROBADA) {
            if (ticket.getMontoTotal() != null && ticket.getMontoTotal().compareTo(BigDecimal.ZERO) > 0) {
                rabbitTemplate.convertAndSend(RabbitMQConfig.APROBADA,
                    ticket.getId() + ":" + ticket.getMontoTotal().toPlainString());
            } else {
                rabbitTemplate.convertAndSend(RabbitMQConfig.CANCELADA, String.valueOf(ticket.getId()));
            }
        } else {
            rabbitTemplate.convertAndSend(RabbitMQConfig.CANCELADA, String.valueOf(ticket.getId()));
        }
    }
}
'@

Write-Source 'ms-reparaciones\src\main\java\com\lastore\reparaciones\controller\TicketController.java' @'
package com.lastore.reparaciones.controller;

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
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;
import com.lastore.reparaciones.service.TicketStateService;

@RestController
@RequestMapping("/api/v1/tickets")
public class TicketController {
    private final TicketRepository ticketRepository;
    private final TicketStateService stateService;

    public TicketController(TicketRepository ticketRepository, TicketStateService stateService) {
        this.ticketRepository = ticketRepository;
        this.stateService = stateService;
    }

    @GetMapping public List<Ticket> listar() { return ticketRepository.findAll(); }
    @GetMapping("/{id}") public Ticket obtener(@PathVariable Long id) { return stateService.obtener(id); }
    @PostMapping public ResponseEntity<Ticket> crear(@RequestBody Ticket ticket) {
        return ResponseEntity.status(HttpStatus.CREATED).body(stateService.crear(ticket));
    }
    @PutMapping("/{id}") public Ticket actualizar(@PathVariable Long id, @RequestBody Ticket datos) {
        return stateService.actualizar(id, datos);
    }
    @PutMapping("/{id}/aprobar-cotizacion") public ResponseEntity<Ticket> aprobar(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.aprobar(id));
    }
    @PutMapping("/{id}/anular") public ResponseEntity<Ticket> anular(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.anular(id));
    }
    @DeleteMapping("/{id}") public ResponseEntity<Ticket> eliminarLogicamente(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.anular(id));
    }
}
'@

Write-Source 'ms-reparaciones\src\main\java\com\lastore\reparaciones\messaging\PagoAnuladoListener.java' @'
package com.lastore.reparaciones.messaging;

import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.service.TicketStateService;

@Component
public class PagoAnuladoListener {
    private final TicketStateService stateService;

    public PagoAnuladoListener(TicketStateService stateService) { this.stateService = stateService; }

    @RabbitListener(queues = RabbitMQConfig.PAGO_ANULADO)
    public void recibir(String mensaje) { stateService.anularDesdePago(Long.parseLong(mensaje)); }
}
'@

Write-Source 'ms-pagos\src\main\java\com\lastore\pagos\config\RabbitMQConfig.java' @'
package com.lastore.pagos.config;

import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {
    public static final String APROBADA = "q.lastore.cotizacion.aprobada";
    public static final String CANCELADA = "q.lastore.cotizacion.cancelada";
    public static final String PAGO_ANULADO = "q.lastore.pago.anulado";

    @Bean public Queue cotizacionAprobada() { return new Queue(APROBADA, true); }
    @Bean public Queue cotizacionCancelada() { return new Queue(CANCELADA, true); }
    @Bean public Queue pagoAnulado() { return new Queue(PAGO_ANULADO, true); }
}
'@

Write-Source 'ms-pagos\src\main\java\com\lastore\pagos\repository\PagoRepository.java' @'
package com.lastore.pagos.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.pagos.model.Pago;

public interface PagoRepository extends JpaRepository<Pago, Long> {
    Optional<Pago> findByTicketIdAndEstadoPago(Long ticketId, String estadoPago);
    List<Pago> findByTicketIdOrderByIdAsc(Long ticketId);
}
'@

Write-Source 'ms-pagos\src\main\java\com\lastore\pagos\service\PagoStateService.java' @'
package com.lastore.pagos.service;

import java.math.BigDecimal;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;

@Service
public class PagoStateService {
    private static final Logger LOGGER = LoggerFactory.getLogger(PagoStateService.class);
    private static final String PENDIENTE = "PENDIENTE";
    private static final String PAGADO = "PAGADO";
    private static final String ANULADO = "ANULADO";
    private final PagoRepository pagoRepository;
    private final RabbitTemplate rabbitTemplate;

    public PagoStateService(PagoRepository pagoRepository, RabbitTemplate rabbitTemplate) {
        this.pagoRepository = pagoRepository;
        this.rabbitTemplate = rabbitTemplate;
    }

    @Transactional
    public void aprobar(Long ticketId, BigDecimal montoTotal) {
        if (montoTotal == null || montoTotal.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("El monto aprobado debe ser mayor a cero");
        }
        List<Pago> existentes = pagoRepository.findByTicketIdOrderByIdAsc(ticketId);
        if (existentes.stream().anyMatch(pago -> PAGADO.equals(pago.getEstadoPago()))) {
            LOGGER.info("Ticket {} ya tiene un pago cobrado; se ignora nueva aprobación", ticketId);
            return;
        }
        Pago principal = null;
        for (Pago pago : existentes) {
            if (PENDIENTE.equals(pago.getEstadoPago())) {
                if (principal == null) {
                    principal = pago;
                    principal.setMontoPago(montoTotal);
                    pagoRepository.save(principal);
                } else {
                    pago.setEstadoPago(ANULADO);
                    pagoRepository.save(pago);
                }
            }
        }
        if (principal == null) {
            Pago nuevo = pagoRepository.save(new Pago(null, ticketId, montoTotal, PENDIENTE));
            LOGGER.info("Pago pendiente {} creado para ticket {}", nuevo.getId(), ticketId);
        } else {
            LOGGER.info("Pago pendiente {} actualizado para ticket {}", principal.getId(), ticketId);
        }
    }

    @Transactional
    public void cancelarCotizacion(Long ticketId) {
        for (Pago pago : pagoRepository.findByTicketIdOrderByIdAsc(ticketId)) {
            if (PENDIENTE.equals(pago.getEstadoPago())) {
                pago.setEstadoPago(ANULADO);
                pagoRepository.save(pago);
            }
        }
    }

    public Pago anularPago(Pago pago) {
        pago.setEstadoPago(ANULADO);
        Pago guardado = pagoRepository.save(pago);
        rabbitTemplate.convertAndSend(RabbitMQConfig.PAGO_ANULADO, String.valueOf(guardado.getTicketId()));
        return guardado;
    }

    @Transactional
    public void limpiarDuplicadosPendientes() {
        Set<Long> vistos = new HashSet<>();
        for (Pago pago : pagoRepository.findAll()) {
            if (PENDIENTE.equals(pago.getEstadoPago()) && !vistos.add(pago.getTicketId())) {
                pago.setEstadoPago(ANULADO);
                pagoRepository.save(pago);
                LOGGER.info("Pago pendiente duplicado {} anulado para ticket {}", pago.getId(), pago.getTicketId());
            }
        }
    }
}
'@

Write-Source 'ms-pagos\src\main\java\com\lastore\pagos\messaging\RabbitMQListener.java' @'
package com.lastore.pagos.messaging;

import java.math.BigDecimal;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.service.PagoStateService;

@Component
public class RabbitMQListener {
    private final PagoStateService stateService;

    public RabbitMQListener(PagoStateService stateService) { this.stateService = stateService; }

    @RabbitListener(queues = RabbitMQConfig.APROBADA)
    public void recibirCotizacionAprobada(String mensaje) {
        String[] valores = mensaje.split(":");
        if (valores.length != 2) throw new IllegalArgumentException("Formato de mensaje inválido: " + mensaje);
        stateService.aprobar(Long.parseLong(valores[0]), new BigDecimal(valores[1]));
    }

    @RabbitListener(queues = RabbitMQConfig.CANCELADA)
    public void recibirCotizacionCancelada(String mensaje) {
        stateService.cancelarCotizacion(Long.parseLong(mensaje));
    }
}
'@

Write-Source 'ms-pagos\src\main\java\com\lastore\pagos\config\DuplicatePaymentCleanup.java' @'
package com.lastore.pagos.config;

import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;
import com.lastore.pagos.service.PagoStateService;

@Component
public class DuplicatePaymentCleanup implements CommandLineRunner {
    private final PagoStateService stateService;

    public DuplicatePaymentCleanup(PagoStateService stateService) { this.stateService = stateService; }

    @Override public void run(String... args) { stateService.limpiarDuplicadosPendientes(); }
}
'@

Write-Source 'ms-pagos\src\main\java\com\lastore\pagos\controller\PagoController.java' @'
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
import com.lastore.pagos.service.PagoStateService;

@RestController
@RequestMapping("/api/v1/pagos")
public class PagoController {
    private final PagoRepository pagoRepository;
    private final PagoStateService stateService;

    public PagoController(PagoRepository pagoRepository, PagoStateService stateService) {
        this.pagoRepository = pagoRepository;
        this.stateService = stateService;
    }

    @GetMapping public List<Pago> listar() { return pagoRepository.findAll(); }
    @GetMapping("/{id}") public Pago obtener(@PathVariable Long id) {
        return pagoRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Pago no encontrado"));
    }
    @PostMapping public ResponseEntity<Pago> crear(@RequestBody Pago pago) {
        pago.setId(null);
        if (pago.getEstadoPago() == null || pago.getEstadoPago().isBlank()) pago.setEstadoPago("PENDIENTE");
        return ResponseEntity.status(HttpStatus.CREATED).body(pagoRepository.save(pago));
    }
    @PutMapping("/{id}") public Pago actualizar(@PathVariable Long id, @RequestBody Pago datos) {
        Pago pago = obtener(id);
        pago.setTicketId(datos.getTicketId());
        pago.setMontoPago(datos.getMontoPago());
        pago.setEstadoPago(datos.getEstadoPago());
        return pagoRepository.save(pago);
    }
    @DeleteMapping("/{id}") public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        pagoRepository.delete(obtener(id));
        return ResponseEntity.noContent().build();
    }
    @PutMapping("/{id}/procesar") public ResponseEntity<Pago> procesar(@PathVariable Long id) {
        Pago pago = obtener(id);
        pago.setEstadoPago("PAGADO");
        return ResponseEntity.ok(pagoRepository.save(pago));
    }
    @PutMapping("/{id}/anular") public ResponseEntity<Pago> anular(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.anularPago(obtener(id)));
    }
}
'@

Write-Source 'frontend-lastore\src\app\components\pagos\pagos.component.ts' @'
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Pago } from '../../models/models';
import { PagoService } from '../../services/pago.service';

@Component({ selector: 'app-pagos', standalone: true, imports: [CurrencyPipe], templateUrl: './pagos.component.html' })
export class PagosComponent implements OnInit {
  pagos: Pago[] = [];
  cargando = false;
  procesandoId?: number;
  anulandoId?: number;
  mensaje = '';
  error = '';

  constructor(private readonly pagoService: PagoService, private readonly changeDetectorRef: ChangeDetectorRef) {}
  ngOnInit(): void { this.cargarPagos(); }

  cargarPagos(): void {
    this.cargando = true;
    this.pagoService.listar().pipe(finalize(() => {
      this.cargando = false;
      this.changeDetectorRef.markForCheck();
    })).subscribe({ next: pagos => this.pagos = pagos, error: () => this.error = 'No se pudieron cargar los pagos.' });
  }

  procesar(pago: Pago): void {
    if (!pago.id || !confirm(`¿Confirmar el cobro del pago #${pago.id}?`)) return;
    this.procesandoId = pago.id;
    this.pagoService.procesarPago(pago.id).pipe(finalize(() => {
      this.procesandoId = undefined;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: () => { this.mensaje = 'Cobro procesado correctamente.'; this.cargarPagos(); },
      error: () => { this.error = 'No se pudo procesar el cobro.'; this.changeDetectorRef.markForCheck(); }
    });
  }

  anularPago(pago: Pago): void {
    if (!pago.id || !confirm(`¿Anular el pago #${pago.id} y su cotización?`)) return;
    this.anulandoId = pago.id;
    this.error = '';
    this.pagoService.anularPago(pago.id).pipe(finalize(() => {
      this.anulandoId = undefined;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: () => {
        this.mensaje = 'Pago y cotización asociada anulados correctamente';
        this.cargarPagos();
      },
      error: () => {
        this.error = 'No se pudo anular el pago.';
        this.changeDetectorRef.markForCheck();
      }
    });
  }

  contar(estado: string): number { return this.pagos.filter(pago => pago.estadoPago === estado).length; }
}
'@

Write-Source 'frontend-lastore\src\app\components\pagos\pagos.component.html' @'
<div class="d-flex flex-wrap justify-content-between align-items-center gap-3 mb-4"><div><p class="text-primary fw-bold small mb-1">TESORERÍA</p><h1 class="page-title mb-1">Pagos</h1><p class="text-secondary mb-0">Cobros generados automáticamente desde RabbitMQ.</p></div><button class="btn btn-outline-primary" (click)="cargarPagos()"><i class="bi bi-arrow-clockwise me-2"></i>Actualizar</button></div>
@if (mensaje) { <div class="alert alert-success alert-dismissible">{{ mensaje }}<button class="btn-close" (click)="mensaje = ''"></button></div> }
@if (error) { <div class="alert alert-danger alert-dismissible">{{ error }}<button class="btn-close" (click)="error = ''"></button></div> }
<div class="row g-3 mb-4">
  <div class="col-md-3"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pagos registrados</small><div class="fs-2 fw-bold">{{ pagos.length }}</div></div></div></div>
  <div class="col-md-3"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pendientes</small><div class="fs-2 fw-bold text-warning">{{ contar('PENDIENTE') }}</div></div></div></div>
  <div class="col-md-3"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Procesados</small><div class="fs-2 fw-bold text-success">{{ contar('PAGADO') }}</div></div></div></div>
  <div class="col-md-3"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Anulados</small><div class="fs-2 fw-bold text-danger">{{ contar('ANULADO') }}</div></div></div></div>
</div>
<div class="card surface-card overflow-hidden"><div class="table-responsive"><table class="table table-hover mb-0"><thead class="table-light"><tr><th>Pago</th><th>Ticket origen</th><th>Monto</th><th>Estado</th><th class="text-end">Acciones</th></tr></thead><tbody>
@for (pago of pagos; track pago.id) {
  <tr><td class="fw-semibold">#{{ pago.id }}</td><td><span class="badge text-bg-light">Ticket #{{ pago.ticketId }}</span></td><td class="fs-5 fw-bold">{{ pago.montoPago | currency:'PEN':'symbol':'1.2-2' }}</td><td><span class="badge" [class.text-bg-warning]="pago.estadoPago === 'PENDIENTE'" [class.text-bg-success]="pago.estadoPago === 'PAGADO'" [class.text-bg-danger]="pago.estadoPago === 'ANULADO'">{{ pago.estadoPago }}</span></td><td class="text-end text-nowrap">
  @if (pago.estadoPago === 'PENDIENTE') {
    <button class="btn btn-sm btn-primary me-2" [disabled]="procesandoId === pago.id || anulandoId === pago.id" (click)="procesar(pago)"><i class="bi bi-credit-card me-2"></i>{{ procesandoId === pago.id ? 'Procesando...' : 'Procesar cobro' }}</button>
    <button class="btn btn-sm btn-danger" [disabled]="procesandoId === pago.id || anulandoId === pago.id" (click)="anularPago(pago)"><i class="bi bi-x-circle me-2"></i>{{ anulandoId === pago.id ? 'Anulando...' : 'Anular' }}</button>
  } @else { <span class="text-secondary small">Sin acciones pendientes</span> }
  </td></tr>
} @empty { <tr><td colspan="5" class="empty-state">@if (cargando) { Consultando pagos... } @else { No hay cobros registrados. }</td></tr> }
</tbody></table></div></div>
'@

$ticketsHtmlPath = Join-Path $ProjectRoot 'frontend-lastore\src\app\components\tickets\tickets.component.html'
$ticketsHtml = [System.IO.File]::ReadAllText($ticketsHtmlPath)
$ticketsHtml = $ticketsHtml.Replace('[class.text-bg-success]="ticket.estadoCotizacion === ''APROBADA''" [class.text-bg-warning]="ticket.estadoCotizacion !== ''APROBADA'' && ticket.estadoCotizacion !== ''ANULADA''" [class.text-bg-secondary]="ticket.estadoCotizacion === ''ANULADA''"', '[class.text-bg-secondary]="ticket.estadoCotizacion === ''PENDIENTE_ENVIO''" [class.text-bg-warning]="ticket.estadoCotizacion === ''ENVIADA''" [class.text-bg-success]="ticket.estadoCotizacion === ''APROBADA''" [class.text-bg-dark]="ticket.estadoCotizacion === ''RECHAZADA''" [class.text-bg-danger]="ticket.estadoCotizacion === ''ANULADA''"')
$ticketsHtml = $ticketsHtml.Replace('[class.text-bg-secondary]="ticket.estadoCotizacion === ''PENDIENTE_ENVIO'' || ticket.estadoCotizacion === ''RECHAZADA''"', '[class.text-bg-secondary]="ticket.estadoCotizacion === ''PENDIENTE_ENVIO''" [class.text-bg-dark]="ticket.estadoCotizacion === ''RECHAZADA''"')
Write-Source 'frontend-lastore\src\app\components\tickets\tickets.component.html' $ticketsHtml

Write-Source 'ms-reparaciones\src\test\java\com\lastore\reparaciones\service\TicketStateServiceTest.java' @'
package com.lastore.reparaciones.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;

class TicketStateServiceTest {
    private final TicketRepository repository = mock(TicketRepository.class);
    private final RabbitTemplate rabbit = mock(RabbitTemplate.class);
    private final TicketStateService service = new TicketStateService(repository, rabbit);

    @Test void crearAprobadaPublicaCobro() {
        when(repository.save(any(Ticket.class))).thenAnswer(call -> {
            Ticket ticket = call.getArgument(0);
            ticket.setId(12L);
            return ticket;
        });
        Ticket ticket = new Ticket(null, 1L, "Laptop", "X", "Falla", "APROBADA", new BigDecimal("150.50"));
        service.crear(ticket);
        verify(rabbit).convertAndSend(RabbitMQConfig.APROBADA, "12:150.50");
    }

    @Test void editarARechazadaCancelaCobro() {
        Ticket ticket = new Ticket(12L, 1L, "Laptop", "X", "Falla", "APROBADA", new BigDecimal("150.50"));
        when(repository.findById(12L)).thenReturn(Optional.of(ticket));
        when(repository.save(any(Ticket.class))).thenAnswer(call -> call.getArgument(0));
        Ticket datos = new Ticket(12L, 1L, "Laptop", "X", "Falla", "RECHAZADA", new BigDecimal("150.50"));
        service.actualizar(12L, datos);
        verify(rabbit).convertAndSend(RabbitMQConfig.CANCELADA, "12");
    }

    @Test void anularConservaRegistroYPublicaCancelacion() {
        Ticket ticket = new Ticket(12L, 1L, "Laptop", "X", "Falla", "ENVIADA", BigDecimal.TEN);
        when(repository.findById(12L)).thenReturn(Optional.of(ticket));
        when(repository.save(any(Ticket.class))).thenAnswer(call -> call.getArgument(0));
        assertThat(service.anular(12L).getEstadoCotizacion()).isEqualTo("ANULADA");
        verify(repository).save(ticket);
        verify(rabbit).convertAndSend(RabbitMQConfig.CANCELADA, "12");
    }
}
'@

Write-Source 'ms-pagos\src\test\java\com\lastore\pagos\service\PagoStateServiceTest.java' @'
package com.lastore.pagos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import com.lastore.pagos.config.RabbitMQConfig;
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;

class PagoStateServiceTest {
    private final PagoRepository repository = mock(PagoRepository.class);
    private final RabbitTemplate rabbit = mock(RabbitTemplate.class);
    private final PagoStateService service = new PagoStateService(repository, rabbit);

    @Test void aprobacionReutilizaPrimerPendienteYAnulaDuplicado() {
        Pago primero = new Pago(1L, 12L, BigDecimal.TEN, "PENDIENTE");
        Pago duplicado = new Pago(2L, 12L, BigDecimal.TEN, "PENDIENTE");
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(primero, duplicado));
        service.aprobar(12L, new BigDecimal("150.50"));
        assertThat(primero.getMontoPago()).isEqualByComparingTo("150.50");
        assertThat(duplicado.getEstadoPago()).isEqualTo("ANULADO");
        verify(repository, times(2)).save(any(Pago.class));
    }

    @Test void pagoCobradoImpideNuevoPendiente() {
        Pago pagado = new Pago(1L, 12L, BigDecimal.TEN, "PAGADO");
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(pagado));
        service.aprobar(12L, BigDecimal.TEN);
        verify(repository, never()).save(any(Pago.class));
    }

    @Test void cancelacionAnulaSoloPendientes() {
        Pago pendiente = new Pago(1L, 12L, BigDecimal.TEN, "PENDIENTE");
        Pago pagado = new Pago(2L, 12L, BigDecimal.TEN, "PAGADO");
        when(repository.findByTicketIdOrderByIdAsc(12L)).thenReturn(List.of(pendiente, pagado));
        service.cancelarCotizacion(12L);
        assertThat(pendiente.getEstadoPago()).isEqualTo("ANULADO");
        assertThat(pagado.getEstadoPago()).isEqualTo("PAGADO");
    }

    @Test void anulacionDePagoNotificaReparaciones() {
        Pago pago = new Pago(1L, 12L, BigDecimal.TEN, "PENDIENTE");
        when(repository.save(pago)).thenReturn(pago);
        service.anularPago(pago);
        assertThat(pago.getEstadoPago()).isEqualTo("ANULADO");
        verify(rabbit).convertAndSend(RabbitMQConfig.PAGO_ANULADO, "12");
    }
}
'@

$destinationScript = Join-Path $ProjectRoot 'fix-maquina-estados-lastore.ps1'
if ([System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path) -ne [System.IO.Path]::GetFullPath($destinationScript)) {
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination $destinationScript -Force
}

foreach ($service in @('ms-reparaciones', 'ms-pagos')) {
    Write-Host "Compilando $service con pruebas..."
    Invoke-Captured $maven @('clean', 'test', 'install', '-B', '-Dnet.bytebuddy.experimental=true') (Join-Path $ProjectRoot $service)
}
Invoke-Captured 'npm.cmd' @('run', 'build') (Join-Path $ProjectRoot 'frontend-lastore')

$runtimeDirectory = Join-Path $ProjectRoot '.runtime'
if (-not (Test-Path -LiteralPath $runtimeDirectory)) { New-Item -ItemType Directory -Path $runtimeDirectory | Out-Null }
$gitignorePath = Join-Path $ProjectRoot '.gitignore'
$gitignoreText = [System.IO.File]::ReadAllText($gitignorePath)
if (-not $gitignoreText.Contains('.runtime/')) { [System.IO.File]::AppendAllText($gitignorePath, "`n.runtime/`n") }
foreach ($service in @(@{Name='ms-reparaciones';Port=8083}, @{Name='ms-pagos';Port=8084})) {
    $existing = Get-NetTCPConnection -LocalPort $service.Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { Write-Warning "Puerto $($service.Port) ocupado; $($service.Name) queda compilado y listo para reinicio manual."; continue }
    $jar = Join-Path $ProjectRoot "$($service.Name)\target\$($service.Name)-0.0.1-SNAPSHOT.jar"
    $outputLog = Join-Path $runtimeDirectory "$($service.Name).out.log"
    $errorLog = Join-Path $runtimeDirectory "$($service.Name).err.log"
    Start-Process -FilePath 'java.exe' -ArgumentList @('-jar', ('"' + $jar + '"')) -WindowStyle Hidden -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog | Out-Null
}

Invoke-Captured 'git.exe' @('add', '.') $ProjectRoot
$commitMessage = 'fix(state-machine): implement full state machine, logical cancel audit, and prevent duplicate payments'
$staged = & git.exe -C $ProjectRoot diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    $latestMessage = & git.exe -C $ProjectRoot log -1 --format=%s
    if ($latestMessage -eq $commitMessage) {
        Invoke-Captured 'git.exe' @('commit', '--amend', '--no-edit') $ProjectRoot
    } else {
        Invoke-Captured 'git.exe' @('commit', '-m', $commitMessage) $ProjectRoot
    }
}
Write-Host 'Máquina de estados compilada y commit creado.'
