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