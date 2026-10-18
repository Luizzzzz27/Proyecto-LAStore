[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Users\Luis\Desktop\6to ciclo\DAW 2\Proyecto-LAStore'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
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
    throw "No se encontró el repositorio LA Store en $ProjectRoot"
}

$mavenCommand = Get-ChildItem -Path "$env:USERPROFILE\.m2\wrapper\dists" -Filter mvn.cmd -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $mavenCommand) { $mavenCommand = (Get-Command mvn.cmd -ErrorAction SilentlyContinue).Source }
if (-not $mavenCommand) { throw 'No se encontró Maven.' }

Write-Utf8File (Join-Path $ProjectRoot 'ms-pagos\src\main\java\com\lastore\pagos\repository\PagoRepository.java') @'
package com.lastore.pagos.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.pagos.model.Pago;

public interface PagoRepository extends JpaRepository<Pago, Long> {
    Optional<Pago> findByTicketIdAndEstadoPago(Long ticketId, String estadoPago);
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
    private static final String ESTADO_PENDIENTE = "PENDIENTE";
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

        if (pagoRepository.findByTicketIdAndEstadoPago(ticketId, ESTADO_PENDIENTE).isPresent()) {
            LOGGER.info("Ya existe un pago pendiente para el ticketId={}; no se creará un duplicado", ticketId);
            return;
        }

        Pago pago = pagoRepository.save(new Pago(null, ticketId, montoTotal, ESTADO_PENDIENTE));
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

    @PutMapping("/{id}/anular")
    public ResponseEntity<Pago> anular(@PathVariable Long id) {
        Pago pago = obtener(id);
        pago.setEstadoPago("ANULADO");
        return ResponseEntity.ok(pagoRepository.save(pago));
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
    private static final String ESTADO_APROBADA = "APROBADA";
    private static final String ESTADO_ANULADA = "ANULADA";
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
        boolean debePublicarAprobacion = !ESTADO_APROBADA.equals(ticket.getEstadoCotizacion())
            && ESTADO_APROBADA.equals(datos.getEstadoCotizacion());

        ticket.setClienteId(datos.getClienteId());
        ticket.setTipoEquipo(datos.getTipoEquipo());
        ticket.setMarcaModelo(datos.getMarcaModelo());
        ticket.setFallaReportada(datos.getFallaReportada());
        ticket.setEstadoCotizacion(datos.getEstadoCotizacion());
        ticket.setMontoTotal(datos.getMontoTotal());

        Ticket guardado = ticketRepository.save(ticket);
        if (debePublicarAprobacion) publicarCotizacionAprobada(guardado);
        return guardado;
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
        ticket.setEstadoCotizacion(ESTADO_APROBADA);
        Ticket guardado = ticketRepository.save(ticket);
        publicarCotizacionAprobada(guardado);
        return ResponseEntity.ok(guardado);
    }

    @PutMapping("/{id}/anular")
    public ResponseEntity<Ticket> anular(@PathVariable Long id) {
        Ticket ticket = obtener(id);
        ticket.setEstadoCotizacion(ESTADO_ANULADA);
        return ResponseEntity.ok(ticketRepository.save(ticket));
    }

    private void publicarCotizacionAprobada(Ticket ticket) {
        if (ticket.getMontoTotal() != null && ticket.getMontoTotal().compareTo(BigDecimal.ZERO) > 0) {
            String mensaje = ticket.getId() + ":" + ticket.getMontoTotal().toPlainString();
            rabbitTemplate.convertAndSend(RabbitMQConfig.COLA_COTIZACION_APROBADA, mensaje);
        }
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'frontend-lastore\src\app\services\pago.service.ts') @'
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Pago } from '../models/models';

@Injectable({ providedIn: 'root' })
export class PagoService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/pagos';
  constructor(private readonly http: HttpClient) {}

  listar(): Observable<Pago[]> { return this.http.get<Pago[]>(this.apiUrl); }
  procesarPago(id: number): Observable<Pago> { return this.http.put<Pago>(`${this.apiUrl}/${id}/procesar`, {}); }
  anularPago(id: number): Observable<Pago> { return this.http.put<Pago>(`${this.apiUrl}/${id}/anular`, {}); }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'frontend-lastore\src\app\services\ticket.service.ts') @'
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Ticket } from '../models/models';

@Injectable({ providedIn: 'root' })
export class TicketService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/tickets';
  constructor(private readonly http: HttpClient) {}

  listar(): Observable<Ticket[]> { return this.http.get<Ticket[]>(this.apiUrl); }
  obtener(id: number): Observable<Ticket> { return this.http.get<Ticket>(`${this.apiUrl}/${id}`); }
  crear(ticket: Ticket): Observable<Ticket> { return this.http.post<Ticket>(this.apiUrl, ticket); }
  actualizar(id: number, ticket: Ticket): Observable<Ticket> { return this.http.put<Ticket>(`${this.apiUrl}/${id}`, ticket); }
  eliminar(id: number): Observable<void> { return this.http.delete<void>(`${this.apiUrl}/${id}`); }
  aprobarCotizacion(id: number): Observable<Ticket> { return this.http.put<Ticket>(`${this.apiUrl}/${id}/aprobar-cotizacion`, {}); }
  anularTicket(id: number): Observable<Ticket> { return this.http.put<Ticket>(`${this.apiUrl}/${id}/anular`, {}); }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'frontend-lastore\src\app\components\pagos\pagos.component.ts') @'
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { finalize, switchMap } from 'rxjs';
import { Pago } from '../../models/models';
import { PagoService } from '../../services/pago.service';
import { TicketService } from '../../services/ticket.service';

@Component({
  selector: 'app-pagos',
  standalone: true,
  imports: [CurrencyPipe],
  templateUrl: './pagos.component.html'
})
export class PagosComponent implements OnInit {
  pagos: Pago[] = [];
  cargando = false;
  procesandoId?: number;
  anulandoId?: number;
  mensaje = '';
  error = '';

  constructor(
    private readonly pagoService: PagoService,
    private readonly ticketService: TicketService,
    private readonly changeDetectorRef: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.cargarPagos();
  }

  cargarPagos(): void {
    this.cargando = true;
    this.error = '';
    this.pagoService.listar().pipe(
      finalize(() => {
        this.cargando = false;
        this.changeDetectorRef.markForCheck();
      })
    ).subscribe({
      next: pagos => this.pagos = pagos,
      error: () => this.error = 'No se pudieron cargar los pagos.'
    });
  }

  procesar(pago: Pago): void {
    if (!pago.id || !confirm(`¿Confirmar el cobro del pago #${pago.id}?`)) return;
    this.procesandoId = pago.id;
    this.pagoService.procesarPago(pago.id).pipe(
      finalize(() => {
        this.procesandoId = undefined;
        this.changeDetectorRef.markForCheck();
      })
    ).subscribe({
      next: () => {
        this.mensaje = 'Cobro procesado correctamente.';
        this.cargarPagos();
      },
      error: () => this.error = 'No se pudo procesar el cobro.'
    });
  }

  anular(pago: Pago): void {
    if (!pago.id || !confirm(`¿Anular el pago #${pago.id} y el ticket #${pago.ticketId}?`)) return;
    this.anulandoId = pago.id;
    this.error = '';
    this.pagoService.anularPago(pago.id).pipe(
      switchMap(() => this.ticketService.anularTicket(pago.ticketId)),
      finalize(() => {
        this.anulandoId = undefined;
        this.changeDetectorRef.markForCheck();
      })
    ).subscribe({
      next: () => {
        this.mensaje = 'Pago y servicio anulados correctamente.';
        this.cargarPagos();
      },
      error: () => {
        this.error = 'No se pudo completar la anulación del pago y el servicio.';
        this.cargarPagos();
      }
    });
  }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'frontend-lastore\src\app\components\pagos\pagos.component.html') @'
<div class="d-flex flex-wrap justify-content-between align-items-center gap-3 mb-4"><div><p class="text-primary fw-bold small mb-1">TESORERÍA</p><h1 class="page-title mb-1">Pagos</h1><p class="text-secondary mb-0">Cobros generados automáticamente desde RabbitMQ.</p></div><button class="btn btn-outline-primary" (click)="cargarPagos()"><i class="bi bi-arrow-clockwise me-2"></i>Actualizar</button></div>
@if (mensaje) { <div class="alert alert-success alert-dismissible">{{ mensaje }}<button class="btn-close" (click)="mensaje = ''"></button></div> }
@if (error) { <div class="alert alert-danger alert-dismissible">{{ error }}<button class="btn-close" (click)="error = ''"></button></div> }
<div class="row g-3 mb-4">
  <div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pagos registrados</small><div class="fs-2 fw-bold">{{ pagos.length }}</div></div></div></div>
  <div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pendientes</small><div class="fs-2 fw-bold text-warning">{{ pagos.filter(p => p.estadoPago === 'PENDIENTE').length }}</div></div></div></div>
  <div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Procesados</small><div class="fs-2 fw-bold text-success">{{ pagos.filter(p => p.estadoPago === 'PAGADO').length }}</div></div></div></div>
</div>
<div class="card surface-card overflow-hidden"><div class="table-responsive"><table class="table table-hover mb-0">
  <thead class="table-light"><tr><th>Pago</th><th>Ticket origen</th><th>Monto</th><th>Estado</th><th class="text-end">Acciones</th></tr></thead>
  <tbody>
    @for (pago of pagos; track pago.id) {
      <tr>
        <td class="fw-semibold">#{{ pago.id }}</td>
        <td><span class="badge text-bg-light">Ticket #{{ pago.ticketId }}</span></td>
        <td class="fs-5 fw-bold">{{ pago.montoPago | currency:'PEN':'symbol':'1.2-2' }}</td>
        <td><span class="badge" [class.text-bg-warning]="pago.estadoPago === 'PENDIENTE'" [class.text-bg-success]="pago.estadoPago === 'PAGADO'" [class.text-bg-secondary]="pago.estadoPago === 'ANULADO'">{{ pago.estadoPago }}</span></td>
        <td class="text-end text-nowrap">
          @if (pago.estadoPago === 'PENDIENTE') {
            <button class="btn btn-sm btn-primary me-2" [disabled]="procesandoId === pago.id || anulandoId === pago.id" (click)="procesar(pago)"><i class="bi bi-credit-card me-2"></i>{{ procesandoId === pago.id ? 'Procesando...' : 'Procesar cobro' }}</button>
            <button class="btn btn-sm btn-danger" [disabled]="procesandoId === pago.id || anulandoId === pago.id" (click)="anular(pago)"><i class="bi bi-x-circle me-2"></i>{{ anulandoId === pago.id ? 'Anulando...' : 'Anular' }}</button>
          } @else {
            <span class="text-secondary small">Sin acciones pendientes</span>
          }
        </td>
      </tr>
    } @empty {
      <tr><td colspan="5" class="empty-state">@if (cargando) { Consultando pagos... } @else { No hay cobros registrados. Apruebe una cotización para iniciar el flujo. }</td></tr>
    }
  </tbody>
</table></div></div>
'@

$thisScript = $MyInvocation.MyCommand.Path
$destinationScript = Join-Path $ProjectRoot 'fix-flujo-negocio.ps1'
if ($thisScript -and ([System.IO.Path]::GetFullPath($thisScript) -ne [System.IO.Path]::GetFullPath($destinationScript))) {
    Copy-Item -LiteralPath $thisScript -Destination $destinationScript -Force
}

Write-Host "`n=== Compilando ms-reparaciones ===" -ForegroundColor Cyan
Invoke-Captured ('"' + $mavenCommand + '" clean install -DskipTests') (Join-Path $ProjectRoot 'ms-reparaciones')
Write-Host "`n=== Compilando ms-pagos ===" -ForegroundColor Cyan
Invoke-Captured ('"' + $mavenCommand + '" clean install -DskipTests') (Join-Path $ProjectRoot 'ms-pagos')
Write-Host "`n=== Compilando frontend Angular ===" -ForegroundColor Cyan
Invoke-Captured 'npm run build' (Join-Path $ProjectRoot 'frontend-lastore')

Invoke-Captured 'git add .' $ProjectRoot
$stagedOutput = cmd /d /s /c "git -C `"$ProjectRoot`" diff --cached --quiet 2>&1"
if ($LASTEXITCODE -ne 0) {
    Invoke-Captured 'git commit -m "fix(business): prevent duplicate payments, sync rabbitmq on standard update, and add cancel feature"' $ProjectRoot
}

Write-Host "`nCORRECCIÓN DE NEGOCIO COMPLETADA" -ForegroundColor Green
