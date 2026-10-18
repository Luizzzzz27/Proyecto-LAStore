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
    throw "No se encontró el repositorio LA Store en $ProjectRoot"
}

$frontendRoot = Join-Path $ProjectRoot 'frontend-lastore'
if (-not (Test-Path -LiteralPath (Join-Path $frontendRoot 'angular.json'))) {
    Invoke-Captured 'ng new frontend-lastore --routing=true --style=css --skip-git --defaults' $ProjectRoot
}

Write-Utf8File (Join-Path $frontendRoot 'src\index.html') @'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>LA Store Service-Commerce</title>
  <base href="/">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Gestión empresarial de servicios técnicos y repuestos LA Store">
  <link rel="icon" type="image/x-icon" href="favicon.ico">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">
</head>
<body>
  <app-root></app-root>
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
'@

Write-Utf8File (Join-Path $frontendRoot 'src\styles.css') @'
:root {
  --la-navy: #111827;
  --la-blue: #2563eb;
  --la-cyan: #06b6d4;
  --la-surface: #f4f7fb;
  --la-muted: #64748b;
}

html, body { min-height: 100%; }
body {
  margin: 0;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
  background: var(--la-surface);
  color: #172033;
}

.page-title { font-weight: 750; letter-spacing: -0.03em; }
.surface-card { border: 0; border-radius: 1rem; box-shadow: 0 12px 32px rgba(15, 23, 42, .08); }
.btn { border-radius: .65rem; }
.form-control, .form-select { border-radius: .65rem; min-height: 44px; }
.table > :not(caption) > * > * { padding: .9rem .75rem; vertical-align: middle; }
.modal-backdrop-custom {
  position: fixed; inset: 0; z-index: 1050; display: grid; place-items: center;
  padding: 1rem; background: rgba(15, 23, 42, .62); backdrop-filter: blur(3px);
}
.modal-card { width: min(680px, 100%); max-height: 92vh; overflow-y: auto; }
.empty-state { padding: 3rem 1rem; color: var(--la-muted); text-align: center; }
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\app.ts') @'
import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet],
  template: '<router-outlet />'
})
export class App {}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\app.config.ts') @'
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(),
    provideRouter(routes)
  ]
};
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\models\models.ts') @'
export interface UsuarioSesion {
  id: number;
  username: string;
  nombreCompleto: string;
  rol: string;
  mensaje: string;
  token: string;
}

export interface Cliente {
  id?: number;
  dniRuc: string;
  nombres: string;
  telefono: string;
  correo: string;
}

export interface Ticket {
  id?: number;
  clienteId: number;
  tipoEquipo: string;
  marcaModelo: string;
  fallaReportada: string;
  estadoCotizacion: string;
  montoTotal: number;
}

export interface Pago {
  id?: number;
  ticketId: number;
  montoPago: number;
  estadoPago: string;
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\services\auth.service.ts') @'
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';
import { UsuarioSesion } from '../models/models';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/auth';
  private readonly storageKey = 'lastore_usuario';

  constructor(private readonly http: HttpClient) {}

  login(username: string, password: string): Observable<UsuarioSesion> {
    return this.http.post<UsuarioSesion>(`${this.apiUrl}/login`, { username, password }).pipe(
      tap(usuario => localStorage.setItem(this.storageKey, JSON.stringify(usuario)))
    );
  }

  obtenerUsuario(): UsuarioSesion | null {
    const value = localStorage.getItem(this.storageKey);
    if (!value) return null;
    try { return JSON.parse(value) as UsuarioSesion; } catch { return null; }
  }

  estaAutenticado(): boolean { return this.obtenerUsuario() !== null; }
  cerrarSesion(): void { localStorage.removeItem(this.storageKey); }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\services\cliente.service.ts') @'
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Cliente } from '../models/models';

@Injectable({ providedIn: 'root' })
export class ClienteService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/clientes';
  constructor(private readonly http: HttpClient) {}

  listar(): Observable<Cliente[]> { return this.http.get<Cliente[]>(this.apiUrl); }
  obtener(id: number): Observable<Cliente> { return this.http.get<Cliente>(`${this.apiUrl}/${id}`); }
  crear(cliente: Cliente): Observable<Cliente> { return this.http.post<Cliente>(this.apiUrl, cliente); }
  actualizar(id: number, cliente: Cliente): Observable<Cliente> { return this.http.put<Cliente>(`${this.apiUrl}/${id}`, cliente); }
  eliminar(id: number): Observable<void> { return this.http.delete<void>(`${this.apiUrl}/${id}`); }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\services\ticket.service.ts') @'
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
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\services\pago.service.ts') @'
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
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\guards\auth.guard.ts') @'
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

export const authGuard: CanActivateFn = () => {
  const authService = inject(AuthService);
  const router = inject(Router);
  return authService.estaAutenticado() ? true : router.createUrlTree(['/login']);
};
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\login\login.component.ts') @'
import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../services/auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './login.component.html',
  styleUrl: './login.component.css'
})
export class LoginComponent {
  username = '';
  password = '';
  mensajeError = '';
  cargando = false;

  constructor(private readonly authService: AuthService, private readonly router: Router) {}

  ingresar(): void {
    if (!this.username.trim() || !this.password) {
      this.mensajeError = 'Ingrese su usuario y contraseña.';
      return;
    }
    this.cargando = true;
    this.mensajeError = '';
    this.authService.login(this.username.trim(), this.password).pipe(
      finalize(() => this.cargando = false)
    ).subscribe({
      next: () => this.router.navigate(['/dashboard']),
      error: error => this.mensajeError = error?.error?.mensaje ?? 'No se pudo iniciar sesión. Verifique sus credenciales.'
    });
  }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\login\login.component.html') @'
<main class="login-shell">
  <section class="login-card shadow-lg">
    <div class="brand-panel">
      <div class="brand-badge"><i class="bi bi-cpu-fill"></i></div>
      <p class="eyebrow">SERVICE-COMMERCE</p>
      <h1>LA Store</h1>
      <p>Gestión integral de reparaciones, cotizaciones y cobros técnicos.</p>
      <div class="feature"><i class="bi bi-shield-check"></i><span>Acceso empresarial seguro</span></div>
      <div class="feature"><i class="bi bi-lightning-charge"></i><span>Operación en tiempo real</span></div>
    </div>
    <div class="form-panel">
      <div class="mb-4">
        <p class="text-primary fw-semibold mb-1">Bienvenido</p>
        <h2 class="fw-bold">Iniciar sesión</h2>
        <p class="text-secondary">Ingrese sus credenciales de LA Store.</p>
      </div>
      @if (mensajeError) { <div class="alert alert-danger py-2">{{ mensajeError }}</div> }
      <form (ngSubmit)="ingresar()" #loginForm="ngForm">
        <label class="form-label fw-semibold" for="username">Usuario</label>
        <div class="input-group mb-3">
          <span class="input-group-text"><i class="bi bi-person"></i></span>
          <input id="username" name="username" class="form-control" [(ngModel)]="username" autocomplete="username" required>
        </div>
        <label class="form-label fw-semibold" for="password">Contraseña</label>
        <div class="input-group mb-4">
          <span class="input-group-text"><i class="bi bi-lock"></i></span>
          <input id="password" name="password" type="password" class="form-control" [(ngModel)]="password" autocomplete="current-password" required>
        </div>
        <button class="btn btn-primary w-100 py-2 fw-semibold" [disabled]="cargando || loginForm.invalid">
          @if (cargando) { <span class="spinner-border spinner-border-sm me-2"></span> }
          Ingresar al sistema
        </button>
      </form>
      <p class="small text-secondary text-center mt-4 mb-0">Soporte técnico · Repuestos · Confianza</p>
    </div>
  </section>
</main>
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\login\login.component.css') @'
.login-shell { min-height: 100vh; display: grid; place-items: center; padding: 2rem; background: radial-gradient(circle at 15% 10%, #dbeafe, transparent 35%), linear-gradient(135deg, #eef4ff, #f8fafc); }
.login-card { display: grid; grid-template-columns: 1fr 1fr; width: min(940px, 100%); overflow: hidden; border-radius: 1.5rem; background: white; }
.brand-panel { padding: 4rem 3.5rem; color: white; background: linear-gradient(145deg, #111827, #1d4ed8); }
.brand-panel h1 { font-size: 3.2rem; font-weight: 800; letter-spacing: -.05em; }
.brand-panel > p:not(.eyebrow) { color: #dbeafe; font-size: 1.08rem; margin-bottom: 2.5rem; }
.brand-badge { display: grid; place-items: center; width: 64px; height: 64px; margin-bottom: 2rem; border-radius: 1rem; font-size: 2rem; background: rgba(255,255,255,.14); }
.eyebrow { margin-bottom: .4rem; color: #67e8f9; font-size: .76rem; font-weight: 800; letter-spacing: .18em; }
.feature { display: flex; gap: .8rem; align-items: center; margin-top: 1rem; color: #e0f2fe; }
.form-panel { padding: 4rem 3.5rem; align-self: center; }
.input-group-text { border-radius: .65rem 0 0 .65rem; background: #f8fafc; }
@media (max-width: 760px) { .login-card { grid-template-columns: 1fr; } .brand-panel { display: none; } .form-panel { padding: 2.5rem 1.5rem; } }
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\dashboard\dashboard.component.ts') @'
import { Component, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthService } from '../../services/auth.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './dashboard.component.html',
  styleUrl: './dashboard.component.css'
})
export class DashboardComponent {
  private readonly authService = inject(AuthService);
  private readonly router = inject(Router);
  readonly usuario = this.authService.obtenerUsuario();
  menuAbierto = false;

  cerrarSesion(): void {
    this.authService.cerrarSesion();
    this.router.navigate(['/login']);
  }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\dashboard\dashboard.component.html') @'
<div class="app-shell">
  <aside class="sidebar" [class.open]="menuAbierto">
    <a class="brand" routerLink="/dashboard">
      <span class="brand-icon"><i class="bi bi-cpu-fill"></i></span>
      <span><strong>LA Store</strong><small>Service-Commerce</small></span>
    </a>
    <nav class="nav flex-column gap-2">
      <a class="nav-link" routerLink="/dashboard/clientes" routerLinkActive="active"><i class="bi bi-people"></i> Clientes</a>
      <a class="nav-link" routerLink="/dashboard/tickets" routerLinkActive="active"><i class="bi bi-tools"></i> Cotizaciones</a>
      <a class="nav-link" routerLink="/dashboard/pagos" routerLinkActive="active"><i class="bi bi-credit-card"></i> Pagos</a>
    </nav>
    <div class="sidebar-footer">
      <div class="user-avatar">{{ usuario?.nombreCompleto?.charAt(0) || 'L' }}</div>
      <div class="user-copy"><strong>{{ usuario?.nombreCompleto || 'Usuario LA Store' }}</strong><small>{{ usuario?.rol || 'COLABORADOR' }}</small></div>
      <button class="btn btn-link text-white" title="Cerrar sesión" (click)="cerrarSesion()"><i class="bi bi-box-arrow-right"></i></button>
    </div>
  </aside>
  <section class="workspace">
    <header class="topbar">
      <button class="btn btn-light d-lg-none" (click)="menuAbierto = !menuAbierto"><i class="bi bi-list"></i></button>
      <div><span class="status-dot"></span> Servicios conectados mediante API Gateway</div>
      <span class="badge text-bg-light">Puerto 8080</span>
    </header>
    <main class="content"><router-outlet /></main>
  </section>
</div>
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\dashboard\dashboard.component.css') @'
.app-shell { min-height: 100vh; display: grid; grid-template-columns: 270px 1fr; }
.sidebar { position: sticky; top: 0; height: 100vh; display: flex; flex-direction: column; padding: 1.4rem; color: white; background: #111827; z-index: 1030; }
.brand { display: flex; gap: .9rem; align-items: center; padding: .45rem; margin-bottom: 2.3rem; color: white; text-decoration: none; }
.brand-icon { display: grid; place-items: center; width: 44px; height: 44px; border-radius: .8rem; background: linear-gradient(145deg, #2563eb, #06b6d4); }
.brand strong, .brand small { display: block; }.brand strong { font-size: 1.2rem; }.brand small { color: #94a3b8; font-size: .72rem; }
.nav-link { display: flex; gap: .85rem; align-items: center; padding: .8rem 1rem; border-radius: .75rem; color: #cbd5e1; }
.nav-link:hover, .nav-link.active { color: white; background: #2563eb; }
.sidebar-footer { display: grid; grid-template-columns: 38px 1fr auto; gap: .7rem; align-items: center; margin-top: auto; padding-top: 1.2rem; border-top: 1px solid #334155; }
.user-avatar { display: grid; place-items: center; width: 38px; height: 38px; border-radius: 50%; font-weight: 700; background: #2563eb; }
.user-copy { min-width: 0; }.user-copy strong, .user-copy small { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }.user-copy strong { font-size: .78rem; }.user-copy small { color: #94a3b8; font-size: .65rem; }
.workspace { min-width: 0; }.topbar { height: 64px; display: flex; gap: 1rem; align-items: center; justify-content: space-between; padding: 0 2rem; border-bottom: 1px solid #e2e8f0; color: #64748b; background: white; font-size: .85rem; }
.status-dot { display: inline-block; width: 8px; height: 8px; margin-right: .45rem; border-radius: 50%; background: #22c55e; box-shadow: 0 0 0 4px #dcfce7; }.content { padding: 2rem; }
@media (max-width: 991px) { .app-shell { grid-template-columns: 1fr; } .sidebar { position: fixed; width: 270px; transform: translateX(-100%); transition: transform .2s; }.sidebar.open { transform: translateX(0); }.content { padding: 1rem; }.topbar { padding: 0 1rem; } }
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\clientes\clientes.component.ts') @'
import { Component, OnInit } from '@angular/core';
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

  constructor(private readonly clienteService: ClienteService) {}
  ngOnInit(): void { this.cargar(); }

  cargar(): void {
    this.cargando = true;
    this.clienteService.listar().pipe(finalize(() => this.cargando = false)).subscribe({
      next: clientes => this.clientes = clientes,
      error: () => this.error = 'No se pudo cargar la lista de clientes.'
    });
  }

  abrirCrear(): void { this.formulario = this.nuevoCliente(); this.modalAbierto = true; }
  abrirEditar(cliente: Cliente): void { this.formulario = { ...cliente }; this.modalAbierto = true; }

  guardar(): void {
    this.guardando = true;
    const operacion = this.formulario.id
      ? this.clienteService.actualizar(this.formulario.id, this.formulario)
      : this.clienteService.crear(this.formulario);
    operacion.pipe(finalize(() => this.guardando = false)).subscribe({
      next: () => { this.modalAbierto = false; this.mensaje = 'Cliente guardado correctamente.'; this.cargar(); },
      error: () => this.error = 'No se pudo guardar el cliente. Verifique el DNI/RUC.'
    });
  }

  eliminar(cliente: Cliente): void {
    if (!cliente.id || !confirm(`¿Eliminar a ${cliente.nombres}?`)) return;
    this.clienteService.eliminar(cliente.id).subscribe({
      next: () => { this.mensaje = 'Cliente eliminado.'; this.cargar(); },
      error: () => this.error = 'No se pudo eliminar el cliente.'
    });
  }

  private nuevoCliente(): Cliente { return { dniRuc: '', nombres: '', telefono: '', correo: '' }; }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\clientes\clientes.component.html') @'
<div class="d-flex flex-wrap justify-content-between align-items-center gap-3 mb-4">
  <div><p class="text-primary fw-bold small mb-1">DIRECTORIO COMERCIAL</p><h1 class="page-title mb-1">Clientes</h1><p class="text-secondary mb-0">Administra personas y empresas atendidas por LA Store.</p></div>
  <button class="btn btn-primary px-4" (click)="abrirCrear()"><i class="bi bi-person-plus me-2"></i>Nuevo cliente</button>
</div>
@if (mensaje) { <div class="alert alert-success alert-dismissible">{{ mensaje }}<button class="btn-close" (click)="mensaje = ''"></button></div> }
@if (error) { <div class="alert alert-danger alert-dismissible">{{ error }}<button class="btn-close" (click)="error = ''"></button></div> }
<div class="card surface-card overflow-hidden">
  <div class="table-responsive">
    <table class="table table-hover mb-0">
      <thead class="table-light"><tr><th>ID</th><th>DNI / RUC</th><th>Cliente</th><th>Teléfono</th><th>Correo</th><th class="text-end">Acciones</th></tr></thead>
      <tbody>
        @for (cliente of clientes; track cliente.id) {
          <tr><td class="text-secondary">#{{ cliente.id }}</td><td><span class="badge text-bg-light">{{ cliente.dniRuc }}</span></td><td class="fw-semibold">{{ cliente.nombres }}</td><td>{{ cliente.telefono || '—' }}</td><td>{{ cliente.correo || '—' }}</td><td class="text-end"><button class="btn btn-sm btn-outline-primary me-2" (click)="abrirEditar(cliente)"><i class="bi bi-pencil"></i></button><button class="btn btn-sm btn-outline-danger" (click)="eliminar(cliente)"><i class="bi bi-trash"></i></button></td></tr>
        } @empty { <tr><td colspan="6" class="empty-state">@if (cargando) { Cargando clientes... } @else { Aún no hay clientes registrados. }</td></tr> }
      </tbody>
    </table>
  </div>
</div>
@if (modalAbierto) {
  <div class="modal-backdrop-custom">
    <div class="card modal-card surface-card"><div class="card-body p-4">
      <div class="d-flex justify-content-between mb-3"><h3 class="fw-bold">{{ formulario.id ? 'Editar cliente' : 'Nuevo cliente' }}</h3><button class="btn-close" (click)="modalAbierto = false"></button></div>
      <form (ngSubmit)="guardar()" #form="ngForm"><div class="row g-3">
        <div class="col-md-5"><label class="form-label">DNI / RUC</label><input class="form-control" name="dniRuc" [(ngModel)]="formulario.dniRuc" maxlength="15" required></div>
        <div class="col-md-7"><label class="form-label">Nombres o razón social</label><input class="form-control" name="nombres" [(ngModel)]="formulario.nombres" required></div>
        <div class="col-md-6"><label class="form-label">Teléfono</label><input class="form-control" name="telefono" [(ngModel)]="formulario.telefono"></div>
        <div class="col-md-6"><label class="form-label">Correo</label><input class="form-control" type="email" name="correo" [(ngModel)]="formulario.correo"></div>
      </div><div class="d-flex justify-content-end gap-2 mt-4"><button type="button" class="btn btn-light" (click)="modalAbierto = false">Cancelar</button><button class="btn btn-primary px-4" [disabled]="form.invalid || guardando">Guardar cliente</button></div></form>
    </div></div>
  </div>
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\tickets\tickets.component.ts') @'
import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Ticket } from '../../models/models';
import { TicketService } from '../../services/ticket.service';

@Component({
  selector: 'app-tickets', standalone: true, imports: [FormsModule, CurrencyPipe], templateUrl: './tickets.component.html'
})
export class TicketsComponent implements OnInit {
  tickets: Ticket[] = [];
  formulario: Ticket = this.nuevoTicket();
  modalAbierto = false;
  cargando = false;
  guardando = false;
  mensaje = '';
  error = '';

  constructor(private readonly ticketService: TicketService) {}
  ngOnInit(): void { this.cargar(); }
  cargar(): void { this.cargando = true; this.ticketService.listar().pipe(finalize(() => this.cargando = false)).subscribe({ next: data => this.tickets = data, error: () => this.error = 'No se pudieron cargar los tickets.' }); }
  abrirCrear(): void { this.formulario = this.nuevoTicket(); this.modalAbierto = true; }
  abrirEditar(ticket: Ticket): void { this.formulario = { ...ticket }; this.modalAbierto = true; }
  guardar(): void {
    this.guardando = true;
    const request = this.formulario.id ? this.ticketService.actualizar(this.formulario.id, this.formulario) : this.ticketService.crear(this.formulario);
    request.pipe(finalize(() => this.guardando = false)).subscribe({ next: () => { this.modalAbierto = false; this.mensaje = 'Ticket guardado correctamente.'; this.cargar(); }, error: () => this.error = 'No se pudo guardar el ticket.' });
  }
  aprobar(ticket: Ticket): void {
    if (!ticket.id || ticket.montoTotal <= 0 || !confirm(`¿Aprobar la cotización #${ticket.id} por S/ ${ticket.montoTotal}?`)) return;
    this.ticketService.aprobarCotizacion(ticket.id).subscribe({ next: () => { this.mensaje = 'Cotización aprobada. El cobro fue enviado a RabbitMQ.'; this.cargar(); }, error: () => this.error = 'No se pudo aprobar la cotización.' });
  }
  eliminar(ticket: Ticket): void { if (!ticket.id || !confirm(`¿Eliminar el ticket #${ticket.id}?`)) return; this.ticketService.eliminar(ticket.id).subscribe({ next: () => this.cargar(), error: () => this.error = 'No se pudo eliminar el ticket.' }); }
  private nuevoTicket(): Ticket { return { clienteId: 0, tipoEquipo: '', marcaModelo: '', fallaReportada: '', estadoCotizacion: 'PENDIENTE_ENVIO', montoTotal: 0 }; }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\tickets\tickets.component.html') @'
<div class="d-flex flex-wrap justify-content-between align-items-center gap-3 mb-4"><div><p class="text-primary fw-bold small mb-1">SERVICIO TÉCNICO</p><h1 class="page-title mb-1">Cotizaciones y tickets</h1><p class="text-secondary mb-0">Registra equipos y activa el flujo de cobro asíncrono.</p></div><button class="btn btn-primary px-4" (click)="abrirCrear()"><i class="bi bi-plus-circle me-2"></i>Registrar equipo</button></div>
@if (mensaje) { <div class="alert alert-success alert-dismissible">{{ mensaje }}<button class="btn-close" (click)="mensaje = ''"></button></div> }
@if (error) { <div class="alert alert-danger alert-dismissible">{{ error }}<button class="btn-close" (click)="error = ''"></button></div> }
<div class="card surface-card overflow-hidden"><div class="table-responsive"><table class="table table-hover mb-0"><thead class="table-light"><tr><th>Ticket</th><th>Cliente</th><th>Equipo</th><th>Falla</th><th>Estado</th><th>Monto</th><th class="text-end">Acciones</th></tr></thead><tbody>
@for (ticket of tickets; track ticket.id) { <tr><td class="fw-semibold">#{{ ticket.id }}</td><td>#{{ ticket.clienteId }}</td><td><strong>{{ ticket.tipoEquipo }}</strong><small class="d-block text-secondary">{{ ticket.marcaModelo }}</small></td><td class="text-secondary" style="max-width:220px">{{ ticket.fallaReportada }}</td><td><span class="badge" [class.text-bg-success]="ticket.estadoCotizacion === 'APROBADA'" [class.text-bg-warning]="ticket.estadoCotizacion !== 'APROBADA'">{{ ticket.estadoCotizacion }}</span></td><td class="fw-bold">{{ ticket.montoTotal | currency:'PEN':'symbol':'1.2-2' }}</td><td class="text-end text-nowrap"><button class="btn btn-sm btn-success me-2" title="Aprobar cotización" [disabled]="ticket.estadoCotizacion === 'APROBADA' || ticket.montoTotal <= 0" (click)="aprobar(ticket)"><i class="bi bi-check2-circle me-1"></i>Aprobar</button><button class="btn btn-sm btn-outline-primary me-2" (click)="abrirEditar(ticket)"><i class="bi bi-pencil"></i></button><button class="btn btn-sm btn-outline-danger" (click)="eliminar(ticket)"><i class="bi bi-trash"></i></button></td></tr> } @empty { <tr><td colspan="7" class="empty-state">@if (cargando) { Cargando tickets... } @else { No hay tickets registrados. }</td></tr> }
</tbody></table></div></div>
@if (modalAbierto) { <div class="modal-backdrop-custom"><div class="card modal-card surface-card"><div class="card-body p-4"><div class="d-flex justify-content-between mb-3"><h3 class="fw-bold">{{ formulario.id ? 'Editar ticket' : 'Registrar equipo' }}</h3><button class="btn-close" (click)="modalAbierto=false"></button></div><form (ngSubmit)="guardar()" #form="ngForm"><div class="row g-3">
<div class="col-md-4"><label class="form-label">ID cliente</label><input class="form-control" type="number" min="1" name="clienteId" [(ngModel)]="formulario.clienteId" required></div><div class="col-md-4"><label class="form-label">Tipo de equipo</label><input class="form-control" name="tipoEquipo" [(ngModel)]="formulario.tipoEquipo" required></div><div class="col-md-4"><label class="form-label">Marca / modelo</label><input class="form-control" name="marcaModelo" [(ngModel)]="formulario.marcaModelo" required></div><div class="col-12"><label class="form-label">Falla reportada</label><textarea class="form-control" rows="3" name="fallaReportada" [(ngModel)]="formulario.fallaReportada" required></textarea></div><div class="col-md-6"><label class="form-label">Estado de cotización</label><select class="form-select" name="estadoCotizacion" [(ngModel)]="formulario.estadoCotizacion"><option>PENDIENTE_ENVIO</option><option>ENVIADA</option><option>APROBADA</option><option>RECHAZADA</option></select></div><div class="col-md-6"><label class="form-label">Monto total</label><input class="form-control" type="number" min="0" step="0.01" name="montoTotal" [(ngModel)]="formulario.montoTotal" required></div>
</div><div class="d-flex justify-content-end gap-2 mt-4"><button type="button" class="btn btn-light" (click)="modalAbierto=false">Cancelar</button><button class="btn btn-primary px-4" [disabled]="form.invalid || guardando">Guardar ticket</button></div></form></div></div></div> }
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\pagos\pagos.component.ts') @'
import { Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Pago } from '../../models/models';
import { PagoService } from '../../services/pago.service';

@Component({ selector: 'app-pagos', standalone: true, imports: [CurrencyPipe], templateUrl: './pagos.component.html' })
export class PagosComponent implements OnInit {
  pagos: Pago[] = [];
  cargando = false;
  procesandoId?: number;
  mensaje = '';
  error = '';
  constructor(private readonly pagoService: PagoService) {}
  ngOnInit(): void { this.cargar(); }
  cargar(): void { this.cargando = true; this.pagoService.listar().pipe(finalize(() => this.cargando = false)).subscribe({ next: pagos => this.pagos = pagos, error: () => this.error = 'No se pudieron cargar los pagos.' }); }
  procesar(pago: Pago): void {
    if (!pago.id || !confirm(`¿Confirmar el cobro del pago #${pago.id}?`)) return;
    this.procesandoId = pago.id;
    this.pagoService.procesarPago(pago.id).pipe(finalize(() => this.procesandoId = undefined)).subscribe({ next: () => { this.mensaje = 'Cobro procesado correctamente.'; this.cargar(); }, error: () => this.error = 'No se pudo procesar el cobro.' });
  }
}
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\components\pagos\pagos.component.html') @'
<div class="d-flex flex-wrap justify-content-between align-items-center gap-3 mb-4"><div><p class="text-primary fw-bold small mb-1">TESORERÍA</p><h1 class="page-title mb-1">Pagos</h1><p class="text-secondary mb-0">Cobros generados automáticamente desde RabbitMQ.</p></div><button class="btn btn-outline-primary" (click)="cargar()"><i class="bi bi-arrow-clockwise me-2"></i>Actualizar</button></div>
@if (mensaje) { <div class="alert alert-success alert-dismissible">{{ mensaje }}<button class="btn-close" (click)="mensaje = ''"></button></div> } @if (error) { <div class="alert alert-danger alert-dismissible">{{ error }}<button class="btn-close" (click)="error = ''"></button></div> }
<div class="row g-3 mb-4"><div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pagos registrados</small><div class="fs-2 fw-bold">{{ pagos.length }}</div></div></div></div><div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Pendientes</small><div class="fs-2 fw-bold text-warning">{{ pagos.filter(p => p.estadoPago === 'PENDIENTE').length }}</div></div></div></div><div class="col-md-4"><div class="card surface-card"><div class="card-body"><small class="text-secondary">Procesados</small><div class="fs-2 fw-bold text-success">{{ pagos.filter(p => p.estadoPago === 'PAGADO').length }}</div></div></div></div></div>
<div class="card surface-card overflow-hidden"><div class="table-responsive"><table class="table table-hover mb-0"><thead class="table-light"><tr><th>Pago</th><th>Ticket origen</th><th>Monto</th><th>Estado</th><th class="text-end">Acción</th></tr></thead><tbody>@for (pago of pagos; track pago.id) { <tr><td class="fw-semibold">#{{ pago.id }}</td><td><span class="badge text-bg-light">Ticket #{{ pago.ticketId }}</span></td><td class="fs-5 fw-bold">{{ pago.montoPago | currency:'PEN':'symbol':'1.2-2' }}</td><td><span class="badge" [class.text-bg-warning]="pago.estadoPago === 'PENDIENTE'" [class.text-bg-success]="pago.estadoPago === 'PAGADO'">{{ pago.estadoPago }}</span></td><td class="text-end"><button class="btn btn-sm btn-primary" [disabled]="pago.estadoPago === 'PAGADO' || procesandoId === pago.id" (click)="procesar(pago)"><i class="bi bi-credit-card me-2"></i>{{ procesandoId === pago.id ? 'Procesando...' : 'Procesar cobro' }}</button></td></tr> } @empty { <tr><td colspan="5" class="empty-state">@if (cargando) { Consultando pagos... } @else { No hay cobros pendientes. Apruebe una cotización para iniciar el flujo. }</td></tr> }</tbody></table></div></div>
'@

Write-Utf8File (Join-Path $frontendRoot 'src\app\app.routes.ts') @'
import { Routes } from '@angular/router';
import { authGuard } from './guards/auth.guard';
import { LoginComponent } from './components/login/login.component';
import { DashboardComponent } from './components/dashboard/dashboard.component';
import { ClientesComponent } from './components/clientes/clientes.component';
import { TicketsComponent } from './components/tickets/tickets.component';
import { PagosComponent } from './components/pagos/pagos.component';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  {
    path: 'dashboard',
    component: DashboardComponent,
    canActivate: [authGuard],
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'clientes' },
      { path: 'clientes', component: ClientesComponent },
      { path: 'tickets', component: TicketsComponent },
      { path: 'pagos', component: PagosComponent }
    ]
  },
  { path: '', pathMatch: 'full', redirectTo: 'login' },
  { path: '**', redirectTo: 'login' }
];
'@

# Angular CLI 22 genera pruebas de la plantilla base; se reemplazan para reflejar el nuevo componente raíz.
Write-Utf8File (Join-Path $frontendRoot 'src\app\app.spec.ts') @'
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { App } from './app';

describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({ imports: [App], providers: [provideRouter([])] }).compileComponents();
  });

  it('should create the app', () => {
    const fixture = TestBed.createComponent(App);
    expect(fixture.componentInstance).toBeTruthy();
  });
});
'@

$thisScript = $MyInvocation.MyCommand.Path
$destinationScript = Join-Path $ProjectRoot 'fase4-frontend.ps1'
if ($thisScript -and ([System.IO.Path]::GetFullPath($thisScript) -ne [System.IO.Path]::GetFullPath($destinationScript))) {
    Copy-Item -LiteralPath $thisScript -Destination $destinationScript -Force
}

Write-Host "`n=== Validando frontend Angular ===" -ForegroundColor Cyan
Invoke-Captured 'npm run build' $frontendRoot

Invoke-Captured 'git add .' $ProjectRoot
$stagedOutput = cmd /d /s /c "git -C `"$ProjectRoot`" diff --cached --quiet 2>&1"
if ($LASTEXITCODE -ne 0) {
    Invoke-Captured 'git commit -m "feat(fase4): add angular frontend with REST consumption for clients, tickets and payments"' $ProjectRoot
}

Write-Host "`nFASE 4 COMPLETADA: frontend compilado y commit creado." -ForegroundColor Green
Write-Host "Para iniciar: cd `"$frontendRoot`"; ng serve"
