import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Ticket } from '../../models/models';
import { TicketService } from '../../services/ticket.service';
import { jsPDF } from 'jspdf';
import { autoTable } from 'jspdf-autotable';
import * as XLSX from 'xlsx';

@Component({
  selector: 'app-tickets',
  standalone: true,
  imports: [FormsModule, CurrencyPipe],
  templateUrl: './tickets.component.html',
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
    private readonly changeDetectorRef: ChangeDetectorRef,
  ) {}
  ngOnInit(): void {
    this.cargarTickets();
  }

  cargarTickets(): void {
    this.cargando = true;
    this.ticketService
      .listar()
      .pipe(
        finalize(() => {
          this.cargando = false;
          this.changeDetectorRef.markForCheck();
        }),
      )
      .subscribe({
        next: (tickets) => (this.tickets = tickets),
        error: () => (this.error = 'No se pudieron cargar los tickets.'),
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
    request
      .pipe(
        finalize(() => {
          this.guardando = false;
          this.changeDetectorRef.markForCheck();
        }),
      )
      .subscribe({
        next: () => {
          this.modalAbierto = false;
          this.mensaje = 'Ticket guardado correctamente.';
          this.cargarTickets();
        },
        error: () => (this.error = 'No se pudo guardar el ticket.'),
      });
  }
  aprobar(ticket: Ticket): void {
    if (
      !ticket.id ||
      ticket.montoTotal <= 0 ||
      !confirm(`¿Aprobar la cotización #${ticket.id} por S/ ${ticket.montoTotal}?`)
    )
      return;
    this.ticketService.aprobarCotizacion(ticket.id).subscribe({
      next: () => {
        this.mensaje = 'Cotización aprobada. El cobro fue enviado a RabbitMQ.';
        this.cargarTickets();
      },
      error: () => {
        this.error = 'No se pudo aprobar la cotización.';
        this.changeDetectorRef.markForCheck();
      },
    });
  }
  anularDesdeTabla(ticket: Ticket): void {
    if (!ticket.id || !confirm('¿Desea anular este ticket?')) return;
    this.ticketService.eliminar(ticket.id).subscribe({
      next: () => {
        this.mensaje = 'Ticket anulado correctamente.';
        this.cargarTickets();
      },
      error: () => {
        this.error = 'No se pudo anular el ticket.';
        this.changeDetectorRef.markForCheck();
      },
    });
  }
  private nuevoTicket(): Ticket {
    return {
      clienteId: 0,
      tipoEquipo: '',
      marcaModelo: '',
      fallaReportada: '',
      estadoCotizacion: 'PENDIENTE_ENVIO',
      montoTotal: 0,
    };
  }
  private fechaArchivo(): string {
    const hoy = new Date();
    const local = new Date(hoy.getTime() - hoy.getTimezoneOffset() * 60_000);
    return local.toISOString().slice(0, 10);
  }

  exportarPDF(): void {
    const doc = new jsPDF({ orientation: 'landscape' });
    const ancho = doc.internal.pageSize.getWidth();

    doc.setFont('helvetica', 'bold');
    doc.setFontSize(17);
    doc.text('Reporte de Cotizaciones - LA Store', ancho / 2, 18, {
      align: 'center',
    });

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.text(`Generado: ${new Date().toLocaleString('es-PE')}`, ancho / 2, 26, { align: 'center' });

    autoTable(doc, {
      startY: 34,
      head: [['Ticket', 'Cliente', 'Equipo', 'Falla', 'Estado', 'Monto']],
      body: this.tickets.map((ticket) => [
        `#${ticket.id ?? ''}`,
        `#${ticket.clienteId}`,
        `${ticket.tipoEquipo} - ${ticket.marcaModelo}`,
        ticket.fallaReportada,
        ticket.estadoCotizacion,
        `S/ ${Number(ticket.montoTotal).toFixed(2)}`,
      ]),
      theme: 'striped',
      headStyles: { fillColor: [33, 37, 41] },
      styles: { fontSize: 9, cellPadding: 3 },
      columnStyles: { 3: { cellWidth: 75 } },
    });

    doc.save(`Reporte_LA_Store_Cotizaciones_${this.fechaArchivo()}.pdf`);
  }

  exportarExcel(): void {
    const filas = this.tickets.map((ticket) => ({
      Ticket: ticket.id ?? '',
      Cliente: ticket.clienteId,
      Equipo: `${ticket.tipoEquipo} - ${ticket.marcaModelo}`,
      Falla: ticket.fallaReportada,
      Estado: ticket.estadoCotizacion,
      Monto: Number(ticket.montoTotal),
    }));

    const hoja = XLSX.utils.json_to_sheet(filas, {
      header: ['Ticket', 'Cliente', 'Equipo', 'Falla', 'Estado', 'Monto'],
    });
    hoja['!cols'] = [{ wch: 12 }, { wch: 12 }, { wch: 35 }, { wch: 55 }, { wch: 22 }, { wch: 15 }];

    const libro = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(libro, hoja, 'Cotizaciones');
    XLSX.writeFile(libro, `Reporte_LA_Store_${this.fechaArchivo()}.xlsx`);
  }
}
