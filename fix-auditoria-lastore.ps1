[CmdletBinding()]
param([string]$ProjectRoot = 'C:\Users\Luis\Desktop\6to ciclo\DAW 2\Proyecto-LAStore')

$ErrorActionPreference = 'Stop'

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Captured {
    param([string]$Command, [string]$WorkingDirectory)
    Push-Location -LiteralPath $WorkingDirectory
    try {
        cmd /d /s /c "$Command 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "Falló el comando: $Command (código $LASTEXITCODE)" }
    } finally { Pop-Location }
}

$mavenCommand = Get-ChildItem -Path "$env:USERPROFILE\.m2\wrapper\dists" -Filter mvn.cmd -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $mavenCommand) { $mavenCommand = (Get-Command mvn.cmd -ErrorAction SilentlyContinue).Source }
if (-not $mavenCommand) { throw 'No se encontró Maven.' }

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
        String oldEstado = ticket.getEstadoCotizacion();

        ticket.setClienteId(datos.getClienteId());
        ticket.setTipoEquipo(datos.getTipoEquipo());
        ticket.setMarcaModelo(datos.getMarcaModelo());
        ticket.setFallaReportada(datos.getFallaReportada());
        ticket.setEstadoCotizacion(datos.getEstadoCotizacion());
        ticket.setMontoTotal(datos.getMontoTotal());

        Ticket guardado = ticketRepository.save(ticket);
        if (!ESTADO_APROBADA.equals(oldEstado) && ESTADO_APROBADA.equals(guardado.getEstadoCotizacion())) {
            rabbitTemplate.convertAndSend(
                "q.lastore.cotizacion.aprobada",
                guardado.getId() + ":" + guardado.getMontoTotal()
            );
        }
        return guardado;
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Ticket> eliminarLogicamente(@PathVariable Long id) {
        Ticket ticket = obtener(id);
        ticket.setEstadoCotizacion(ESTADO_ANULADA);
        return ResponseEntity.ok(ticketRepository.save(ticket));
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

    public PagoController(PagoRepository pagoRepository) { this.pagoRepository = pagoRepository; }

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
        Pago guardado = pagoRepository.save(pago);
        return ResponseEntity.ok(guardado);
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'frontend-lastore\src\app\components\pagos\pagos.component.ts') @'
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Pago } from '../../models/models';
import { PagoService } from '../../services/pago.service';
import { TicketService } from '../../services/ticket.service';

@Component({
  selector: 'app-pagos', standalone: true, imports: [CurrencyPipe], templateUrl: './pagos.component.html'
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

  ngOnInit(): void { this.cargarPagos(); }

  cargarPagos(): void {
    this.cargando = true;
    this.pagoService.listar().pipe(finalize(() => {
      this.cargando = false;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: pagos => this.pagos = pagos,
      error: () => this.error = 'No se pudieron cargar los pagos.'
    });
  }

  procesar(pago: Pago): void {
    if (!pago.id || !confirm(`¿Confirmar el cobro del pago #${pago.id}?`)) return;
    this.procesandoId = pago.id;
    this.pagoService.procesarPago(pago.id).pipe(finalize(() => {
      this.procesandoId = undefined;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: () => { this.mensaje = 'Cobro procesado correctamente.'; this.cargarPagos(); },
      error: () => this.error = 'No se pudo procesar el cobro.'
    });
  }

  anularPago(pago: Pago): void {
    if (!pago.id || !confirm(`¿Anular el pago #${pago.id} y el ticket #${pago.ticketId}?`)) return;
    this.anulandoId = pago.id;
    this.error = '';

    this.pagoService.anularPago(pago.id).subscribe({
      next: () => {
        this.ticketService.anularTicket(pago.ticketId).subscribe({
          next: () => {
            this.mensaje = 'Pago y ticket anulados correctamente.';
            this.anulandoId = undefined;
            this.cargarPagos();
          },
          error: () => {
            this.error = 'El pago fue anulado, pero no se pudo anular el ticket origen.';
            this.anulandoId = undefined;
            this.cargarPagos();
          }
        });
      },
      error: () => {
        this.error = 'No se pudo anular el pago.';
        this.anulandoId = undefined;
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
<div class="row g-3 mb-4"><div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pagos registrados</small><div class="fs-2 fw-bold">{{ pagos.length }}</div></div></div></div><div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pendientes</small><div class="fs-2 fw-bold text-warning">{{ pagos.filter(p => p.estadoPago === 'PENDIENTE').length }}</div></div></div></div><div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Procesados</small><div class="fs-2 fw-bold text-success">{{ pagos.filter(p => p.estadoPago === 'PAGADO').length }}</div></div></div></div></div>
<div class="card surface-card overflow-hidden"><div class="table-responsive"><table class="table table-hover mb-0"><thead class="table-light"><tr><th>Pago</th><th>Ticket origen</th><th>Monto</th><th>Estado</th><th class="text-end">Acciones</th></tr></thead><tbody>
@for (pago of pagos; track pago.id) {
  <tr><td class="fw-semibold">#{{ pago.id }}</td><td><span class="badge text-bg-light">Ticket #{{ pago.ticketId }}</span></td><td class="fs-5 fw-bold">{{ pago.montoPago | currency:'PEN':'symbol':'1.2-2' }}</td><td><span class="badge" [class.text-bg-warning]="pago.estadoPago === 'PENDIENTE'" [class.text-bg-success]="pago.estadoPago === 'PAGADO'" [class.text-bg-secondary]="pago.estadoPago === 'ANULADO'">{{ pago.estadoPago }}</span></td><td class="text-end text-nowrap">
  @if (pago.estadoPago === 'PENDIENTE') {
    <button class="btn btn-sm btn-primary me-2" [disabled]="procesandoId === pago.id || anulandoId === pago.id" (click)="procesar(pago)"><i class="bi bi-credit-card me-2"></i>{{ procesandoId === pago.id ? 'Procesando...' : 'Procesar cobro' }}</button>
    <button class="btn btn-sm btn-danger" [disabled]="procesandoId === pago.id || anulandoId === pago.id" (click)="anularPago(pago)"><i class="bi bi-x-circle me-2"></i>{{ anulandoId === pago.id ? 'Anulando...' : 'Anular' }}</button>
  } @else { <span class="text-secondary small">Sin acciones pendientes</span> }
  </td></tr>
} @empty { <tr><td colspan="5" class="empty-state">@if (cargando) { Consultando pagos... } @else { No hay cobros registrados. }</td></tr> }
</tbody></table></div></div>
'@

Write-Utf8File (Join-Path $ProjectRoot 'frontend-lastore\src\app\components\tickets\tickets.component.ts') @'
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Ticket } from '../../models/models';
import { TicketService } from '../../services/ticket.service';

@Component({ selector: 'app-tickets', standalone: true, imports: [FormsModule, CurrencyPipe], templateUrl: './tickets.component.html' })
export class TicketsComponent implements OnInit {
  tickets: Ticket[] = [];
  formulario: Ticket = this.nuevoTicket();
  modalAbierto = false;
  cargando = false;
  guardando = false;
  mensaje = '';
  error = '';

  constructor(private readonly ticketService: TicketService, private readonly changeDetectorRef: ChangeDetectorRef) {}
  ngOnInit(): void { this.cargarTickets(); }

  cargarTickets(): void {
    this.cargando = true;
    this.ticketService.listar().pipe(finalize(() => { this.cargando = false; this.changeDetectorRef.markForCheck(); })).subscribe({ next: tickets => this.tickets = tickets, error: () => this.error = 'No se pudieron cargar los tickets.' });
  }
  abrirCrear(): void { this.formulario = this.nuevoTicket(); this.modalAbierto = true; }
  abrirEditar(ticket: Ticket): void { this.formulario = { ...ticket }; this.modalAbierto = true; }
  guardar(): void {
    this.guardando = true;
    const request = this.formulario.id ? this.ticketService.actualizar(this.formulario.id, this.formulario) : this.ticketService.crear(this.formulario);
    request.pipe(finalize(() => { this.guardando = false; this.changeDetectorRef.markForCheck(); })).subscribe({ next: () => { this.modalAbierto = false; this.mensaje = 'Ticket guardado correctamente.'; this.cargarTickets(); }, error: () => this.error = 'No se pudo guardar el ticket.' });
  }
  aprobar(ticket: Ticket): void {
    if (!ticket.id || ticket.montoTotal <= 0 || !confirm(`¿Aprobar la cotización #${ticket.id} por S/ ${ticket.montoTotal}?`)) return;
    this.ticketService.aprobarCotizacion(ticket.id).subscribe({ next: () => { this.mensaje = 'Cotización aprobada. El cobro fue enviado a RabbitMQ.'; this.cargarTickets(); }, error: () => { this.error = 'No se pudo aprobar la cotización.'; this.changeDetectorRef.markForCheck(); } });
  }
  anularDesdeTabla(ticket: Ticket): void {
    if (!ticket.id || !confirm('¿Desea anular este ticket?')) return;
    this.ticketService.eliminar(ticket.id).subscribe({
      next: () => { this.mensaje = 'Ticket anulado correctamente.'; this.cargarTickets(); },
      error: () => { this.error = 'No se pudo anular el ticket.'; this.changeDetectorRef.markForCheck(); }
    });
  }
  private nuevoTicket(): Ticket { return { clienteId: 0, tipoEquipo: '', marcaModelo: '', fallaReportada: '', estadoCotizacion: 'PENDIENTE_ENVIO', montoTotal: 0 }; }
}
'@

Write-Utf8File (Join-Path $ProjectRoot 'frontend-lastore\src\app\components\tickets\tickets.component.html') @'
<div class="d-flex flex-wrap justify-content-between align-items-center gap-3 mb-4"><div><p class="text-primary fw-bold small mb-1">SERVICIO TÉCNICO</p><h1 class="page-title mb-1">Cotizaciones y tickets</h1><p class="text-secondary mb-0">Registra equipos y activa el flujo de cobro asíncrono.</p></div><button class="btn btn-primary px-4" (click)="abrirCrear()"><i class="bi bi-plus-circle me-2"></i>Registrar equipo</button></div>
@if (mensaje) { <div class="alert alert-success alert-dismissible">{{ mensaje }}<button class="btn-close" (click)="mensaje = ''"></button></div> } @if (error) { <div class="alert alert-danger alert-dismissible">{{ error }}<button class="btn-close" (click)="error = ''"></button></div> }
<div class="card surface-card overflow-hidden"><div class="table-responsive"><table class="table table-hover mb-0"><thead class="table-light"><tr><th>Ticket</th><th>Cliente</th><th>Equipo</th><th>Falla</th><th>Estado</th><th>Monto</th><th class="text-end">Acciones</th></tr></thead><tbody>
@for (ticket of tickets; track ticket.id) { <tr><td class="fw-semibold">#{{ ticket.id }}</td><td>#{{ ticket.clienteId }}</td><td><strong>{{ ticket.tipoEquipo }}</strong><small class="d-block text-secondary">{{ ticket.marcaModelo }}</small></td><td class="text-secondary" style="max-width:220px">{{ ticket.fallaReportada }}</td><td><span class="badge" [class.text-bg-success]="ticket.estadoCotizacion === 'APROBADA'" [class.text-bg-warning]="ticket.estadoCotizacion !== 'APROBADA' && ticket.estadoCotizacion !== 'ANULADA'" [class.text-bg-secondary]="ticket.estadoCotizacion === 'ANULADA'">{{ ticket.estadoCotizacion }}</span></td><td class="fw-bold">{{ ticket.montoTotal | currency:'PEN':'symbol':'1.2-2' }}</td><td class="text-end text-nowrap"><button class="btn btn-sm btn-success me-2" title="Aprobar cotización" [disabled]="ticket.estadoCotizacion === 'APROBADA' || ticket.estadoCotizacion === 'ANULADA' || ticket.montoTotal <= 0" (click)="aprobar(ticket)"><i class="bi bi-check2-circle me-1"></i>Aprobar</button><button class="btn btn-sm btn-outline-primary me-2" [disabled]="ticket.estadoCotizacion === 'ANULADA'" (click)="abrirEditar(ticket)"><i class="bi bi-pencil"></i></button><button class="btn btn-sm btn-outline-danger" title="Anular ticket" [disabled]="ticket.estadoCotizacion === 'ANULADA'" (click)="anularDesdeTabla(ticket)"><i class="bi bi-trash"></i></button></td></tr> } @empty { <tr><td colspan="7" class="empty-state">@if (cargando) { Cargando tickets... } @else { No hay tickets registrados. }</td></tr> }
</tbody></table></div></div>
@if (modalAbierto) { <div class="modal-backdrop-custom"><div class="card modal-card surface-card"><div class="card-body p-4"><div class="d-flex justify-content-between mb-3"><h3 class="fw-bold">{{ formulario.id ? 'Editar ticket' : 'Registrar equipo' }}</h3><button class="btn-close" (click)="modalAbierto=false"></button></div><form (ngSubmit)="guardar()" #form="ngForm"><div class="row g-3">
<div class="col-md-4"><label class="form-label">ID cliente</label><input class="form-control" type="number" min="1" name="clienteId" [(ngModel)]="formulario.clienteId" required></div><div class="col-md-4"><label class="form-label">Tipo de equipo</label><input class="form-control" name="tipoEquipo" [(ngModel)]="formulario.tipoEquipo" required></div><div class="col-md-4"><label class="form-label">Marca / modelo</label><input class="form-control" name="marcaModelo" [(ngModel)]="formulario.marcaModelo" required></div><div class="col-12"><label class="form-label">Falla reportada</label><textarea class="form-control" rows="3" name="fallaReportada" [(ngModel)]="formulario.fallaReportada" required></textarea></div><div class="col-md-6"><label class="form-label">Estado de cotización</label><select class="form-select" name="estadoCotizacion" [(ngModel)]="formulario.estadoCotizacion"><option>PENDIENTE_ENVIO</option><option>ENVIADA</option><option>APROBADA</option><option>RECHAZADA</option><option>ANULADA</option></select></div><div class="col-md-6"><label class="form-label">Monto total</label><input class="form-control" type="number" min="0" step="0.01" name="montoTotal" [(ngModel)]="formulario.montoTotal" required></div>
</div><div class="d-flex justify-content-end gap-2 mt-4"><button type="button" class="btn btn-light" (click)="modalAbierto=false">Cancelar</button><button class="btn btn-primary px-4" [disabled]="form.invalid || guardando">Guardar ticket</button></div></form></div></div></div> }
'@

$destinationScript = Join-Path $ProjectRoot 'fix-auditoria-lastore.ps1'
if ([System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path) -ne [System.IO.Path]::GetFullPath($destinationScript)) {
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination $destinationScript -Force
}

Invoke-Captured ('"' + $mavenCommand + '" clean install -DskipTests') (Join-Path $ProjectRoot 'ms-reparaciones')
Invoke-Captured ('"' + $mavenCommand + '" clean install -DskipTests') (Join-Path $ProjectRoot 'ms-pagos')
Invoke-Captured 'npm run build' (Join-Path $ProjectRoot 'frontend-lastore')
Invoke-Captured 'git add .' $ProjectRoot
$staged = cmd /d /s /c "git -C `"$ProjectRoot`" diff --cached --quiet 2>&1"
if ($LASTEXITCODE -ne 0) {
    Invoke-Captured 'git commit -m "fix(security): implement logical delete, fix rabbitmq event on standard update, and chain cancel operations"' $ProjectRoot
}
Write-Host 'CORRECCIÓN DE AUDITORÍA COMPLETADA' -ForegroundColor Green
