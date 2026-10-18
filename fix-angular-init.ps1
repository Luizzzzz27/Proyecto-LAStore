[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Users\Luis\Desktop\6to ciclo\DAW 2\Proyecto-LAStore'
)

$ErrorActionPreference = 'Stop'

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

$frontendRoot = Join-Path $ProjectRoot 'frontend-lastore'
if (-not (Test-Path -LiteralPath (Join-Path $frontendRoot 'angular.json'))) {
    throw "No se encontró el proyecto Angular en $frontendRoot"
}

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\clientes\clientes.component.ts') @'
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { finalize } from 'rxjs';
import { Cliente } from '../../models/models';
import { ClienteService } from '../../services/cliente.service';

@Component({
  selector: 'app-clientes',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './clientes.component.html'
})
export class ClientesComponent implements OnInit {
  clientes: Cliente[] = [];
  formulario: Cliente = this.nuevoCliente();
  modalAbierto = false;
  cargando = false;
  guardando = false;
  mensaje = '';
  error = '';

  constructor(
    private readonly clienteService: ClienteService,
    private readonly changeDetectorRef: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.cargarClientes();
  }

  cargarClientes(): void {
    this.cargando = true;
    this.error = '';
    this.clienteService.listar().pipe(
      finalize(() => {
        this.cargando = false;
        this.changeDetectorRef.markForCheck();
      })
    ).subscribe({
      next: clientes => this.clientes = clientes,
      error: () => this.error = 'No se pudo cargar la lista de clientes.'
    });
  }

  abrirCrear(): void {
    this.formulario = this.nuevoCliente();
    this.modalAbierto = true;
  }

  abrirEditar(cliente: Cliente): void {
    this.formulario = { ...cliente };
    this.modalAbierto = true;
  }

  guardar(): void {
    this.guardando = true;
    const operacion = this.formulario.id
      ? this.clienteService.actualizar(this.formulario.id, this.formulario)
      : this.clienteService.crear(this.formulario);
    operacion.pipe(finalize(() => {
      this.guardando = false;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: () => {
        this.modalAbierto = false;
        this.mensaje = 'Cliente guardado correctamente.';
        this.cargarClientes();
      },
      error: () => this.error = 'No se pudo guardar el cliente. Verifique el DNI/RUC.'
    });
  }

  eliminar(cliente: Cliente): void {
    if (!cliente.id || !confirm(`¿Eliminar a ${cliente.nombres}?`)) return;
    this.clienteService.eliminar(cliente.id).subscribe({
      next: () => {
        this.mensaje = 'Cliente eliminado.';
        this.cargarClientes();
      },
      error: () => {
        this.error = 'No se pudo eliminar el cliente.';
        this.changeDetectorRef.markForCheck();
      }
    });
  }

  private nuevoCliente(): Cliente {
    return { dniRuc: '', nombres: '', telefono: '', correo: '' };
  }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\tickets\tickets.component.ts') @'
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Ticket } from '../../models/models';
import { TicketService } from '../../services/ticket.service';

@Component({
  selector: 'app-tickets',
  standalone: true,
  imports: [FormsModule, CurrencyPipe],
  templateUrl: './tickets.component.html'
})
export class TicketsComponent implements OnInit {
  tickets: Ticket[] = [];
  formulario: Ticket = this.nuevoTicket();
  modalAbierto = false;
  cargando = false;
  guardando = false;
  mensaje = '';
  error = '';

  constructor(
    private readonly ticketService: TicketService,
    private readonly changeDetectorRef: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.cargarTickets();
  }

  cargarTickets(): void {
    this.cargando = true;
    this.error = '';
    this.ticketService.listar().pipe(
      finalize(() => {
        this.cargando = false;
        this.changeDetectorRef.markForCheck();
      })
    ).subscribe({
      next: tickets => this.tickets = tickets,
      error: () => this.error = 'No se pudieron cargar los tickets.'
    });
  }

  abrirCrear(): void {
    this.formulario = this.nuevoTicket();
    this.modalAbierto = true;
  }

  abrirEditar(ticket: Ticket): void {
    this.formulario = { ...ticket };
    this.modalAbierto = true;
  }

  guardar(): void {
    this.guardando = true;
    const request = this.formulario.id
      ? this.ticketService.actualizar(this.formulario.id, this.formulario)
      : this.ticketService.crear(this.formulario);
    request.pipe(finalize(() => {
      this.guardando = false;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: () => {
        this.modalAbierto = false;
        this.mensaje = 'Ticket guardado correctamente.';
        this.cargarTickets();
      },
      error: () => this.error = 'No se pudo guardar el ticket.'
    });
  }

  aprobar(ticket: Ticket): void {
    if (!ticket.id || ticket.montoTotal <= 0 || !confirm(`¿Aprobar la cotización #${ticket.id} por S/ ${ticket.montoTotal}?`)) return;
    this.ticketService.aprobarCotizacion(ticket.id).subscribe({
      next: () => {
        this.mensaje = 'Cotización aprobada. El cobro fue enviado a RabbitMQ.';
        this.cargarTickets();
      },
      error: () => {
        this.error = 'No se pudo aprobar la cotización.';
        this.changeDetectorRef.markForCheck();
      }
    });
  }

  eliminar(ticket: Ticket): void {
    if (!ticket.id || !confirm(`¿Eliminar el ticket #${ticket.id}?`)) return;
    this.ticketService.eliminar(ticket.id).subscribe({
      next: () => this.cargarTickets(),
      error: () => {
        this.error = 'No se pudo eliminar el ticket.';
        this.changeDetectorRef.markForCheck();
      }
    });
  }

  private nuevoTicket(): Ticket {
    return {
      clienteId: 0,
      tipoEquipo: '',
      marcaModelo: '',
      fallaReportada: '',
      estadoCotizacion: 'PENDIENTE_ENVIO',
      montoTotal: 0
    };
  }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\pagos\pagos.component.ts') @'
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Pago } from '../../models/models';
import { PagoService } from '../../services/pago.service';

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
  mensaje = '';
  error = '';

  constructor(
    private readonly pagoService: PagoService,
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
}
'@

# Actualiza las referencias de los botones existentes a los nombres explícitos.
$pagosHtmlPath = Join-Path $frontendRoot 'src\app\components\pagos\pagos.component.html'
$pagosHtml = [System.IO.File]::ReadAllText($pagosHtmlPath).Replace('(click)="cargar()"', '(click)="cargarPagos()"')
Write-Utf8File $pagosHtmlPath $pagosHtml

$thisScript = $MyInvocation.MyCommand.Path
$destinationScript = Join-Path $ProjectRoot 'fix-angular-init.ps1'
if ($thisScript -and ([System.IO.Path]::GetFullPath($thisScript) -ne [System.IO.Path]::GetFullPath($destinationScript))) {
    Copy-Item -LiteralPath $thisScript -Destination $destinationScript -Force
}

Write-Host "`n=== Validando corrección Angular ===" -ForegroundColor Cyan
Invoke-Captured 'npm run build' $frontendRoot

Invoke-Captured 'git add .' $ProjectRoot
$stagedOutput = cmd /d /s /c "git -C `"$ProjectRoot`" diff --cached --quiet 2>&1"
if ($LASTEXITCODE -ne 0) {
    Invoke-Captured 'git commit -m "fix(frontend): add ngOnInit to load data automatically on view change"' $ProjectRoot
}

Write-Host "`nCORRECCIÓN COMPLETADA: OnInit y actualización de vista configurados." -ForegroundColor Green
