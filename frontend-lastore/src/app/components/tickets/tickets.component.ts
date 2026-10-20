import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Cliente, Ticket } from '../../models/models';
import { TicketService } from '../../services/ticket.service';
import { ClienteService } from '../../services/cliente.service';

@Component({
  selector: 'app-tickets',
  standalone: true,
  imports: [FormsModule, CurrencyPipe],
  templateUrl: './tickets.component.html',
})
export class TicketsComponent implements OnInit {
  tickets: Ticket[] = [];
  clientes = new Map<number, Cliente>();
  buscarClienteModal = '';
  errorClienteModal = '';
  cargandoClientes = false;
  clientesCargados = false;
  terminoBusqueda = '';
  estadoFiltro = '';
  fechaDesde = '';
  fechaHasta = '';
  formulario: Ticket = this.nuevoTicket();
  modalAbierto = false;
  cargando = false;
  guardando = false;
  mensaje = '';
  error = '';

  constructor(
    private readonly ticketService: TicketService,
    private readonly changeDetectorRef: ChangeDetectorRef,
    private readonly clienteService: ClienteService,
  ) {}
  ngOnInit(): void {
    this.cargarTickets();
    this.cargarClientes();
  }

  cargarClientes(): void {
    this.cargandoClientes = true;
    this.clienteService.listar().pipe(finalize(() => {
      this.cargandoClientes = false;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: clientes => { this.clientesCargados = true; this.clientes = new Map(clientes.filter(c => c.id != null).map(c => [c.id!, c])); this.changeDetectorRef.markForCheck(); },
      error: () => { this.error = 'No se pudieron cargar los clientes para la búsqueda.'; this.changeDetectorRef.markForCheck(); }
    });
  }

  get clienteValido(): boolean { return this.clientes.has(this.formulario.clienteId); }

  get clientesModal(): Cliente[] {
    const normalizar = (valor: string) => valor.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    const texto = normalizar(this.buscarClienteModal.trim());
    return Array.from(this.clientes.values())
      .filter(cliente => !texto || normalizar(cliente.nombres + ' ' + cliente.dniRuc).includes(texto))
      .slice(0, 50);
  }

  buscarCliente(valor: string): void {
    this.buscarClienteModal = valor;
    this.formulario.clienteId = 0;
    this.errorClienteModal = 'Seleccione un cliente de las coincidencias del directorio.';
  }

  seleccionarCliente(cliente: Cliente): void {
    this.formulario.clienteId = cliente.id!;
    this.buscarClienteModal = cliente.nombres;
    this.errorClienteModal = '';
  }

  get ticketsFiltrados(): Ticket[] {
    const texto = this.terminoBusqueda.trim().toLocaleLowerCase('es-PE');
    return this.tickets.filter(ticket => {
      const cliente = this.clientes.get(ticket.clienteId);
      const valores = [ticket.id, `#${ticket.id}`, ticket.clienteId, cliente?.nombres,
        cliente?.dniRuc, ticket.tipoEquipo, ticket.marcaModelo, ticket.fallaReportada];
      return (!texto || valores.some(valor => String(valor ?? '').toLocaleLowerCase('es-PE').includes(texto)))
        && (!this.estadoFiltro || ticket.estadoCotizacion === this.estadoFiltro)
        && this.enRango(ticket.fechaRegistro);
    });
  }

  private enRango(fecha?: string | null): boolean {
    if (!this.fechaDesde && !this.fechaHasta) return true;
    if (!fecha) return false; // Los registros históricos sin fecha solo se excluyen con filtro activo.
    const dia = fecha.slice(0, 10);
    return (!this.fechaDesde || dia >= this.fechaDesde) && (!this.fechaHasta || dia <= this.fechaHasta);
  }

  limpiarFiltros(): void { this.terminoBusqueda = ''; this.estadoFiltro = ''; this.fechaDesde = ''; this.fechaHasta = ''; }
  filtrarHoy(): void { const hoy = this.fechaArchivo(); this.fechaDesde = hoy; this.fechaHasta = hoy; }
  filtrarSemana(): void {
    const hoy = new Date();
    const inicio = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() - (hoy.getDay() + 6) % 7);
    this.fechaDesde = this.formatoDia(inicio); this.fechaHasta = this.fechaArchivo();
  }
  filtrarMes(): void { const hoy = new Date(); this.fechaDesde = this.formatoDia(new Date(hoy.getFullYear(), hoy.getMonth(), 1)); this.fechaHasta = this.fechaArchivo(); }
  private formatoDia(fecha: Date): string { return `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, '0')}-${String(fecha.getDate()).padStart(2, '0')}`; }

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
    this.buscarClienteModal = '';
    this.errorClienteModal = '';
    this.cargarClientes();
    this.modalAbierto = true;
  }
  abrirEditar(ticket: Ticket): void {
    this.formulario = { ...ticket };
    this.buscarClienteModal = this.clientes.get(ticket.clienteId)?.nombres ?? '';
    this.errorClienteModal = this.clienteValido ? '' : 'Asigne un cliente registrado antes de guardar este ticket.';
    this.cargarClientes();
    this.modalAbierto = true;
  }
  guardar(): void {
    if (!this.clienteValido || this.cargandoClientes) {
      this.errorClienteModal = 'Seleccione un cliente válido del directorio de LA Store.';
      return;
    }
    this.errorClienteModal = '';
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
        error: respuesta => { this.errorClienteModal = respuesta.error?.message || 'No se pudo guardar el ticket.'; },
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

  async exportarPDF(): Promise<void> {
    const filas = this.ticketsFiltrados;
    if (!filas.length) return;
    const [{ jsPDF }, { autoTable }] = await Promise.all([import('jspdf'), import('jspdf-autotable')]);
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

    const total = filas.reduce((suma, ticket) => suma + Number(ticket.montoTotal || 0), 0);
    doc.text(`Periodo: ${this.fechaDesde || 'Todos'} al ${this.fechaHasta || 'Todos'} | Total registros: ${filas.length} | Monto total: S/ ${total.toFixed(2)}`, ancho / 2, 32, { align: 'center' });
    autoTable(doc, {
      startY: 39,
      head: [['Ticket', 'Cliente', 'Equipo', 'Falla', 'Estado', 'Monto']],
      body: filas.map((ticket) => [
        `#${ticket.id ?? ''}`,
        this.clientes.get(ticket.clienteId)?.nombres ?? `#${ticket.clienteId}`,
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

  async exportarExcel(): Promise<void> {
    if (!this.ticketsFiltrados.length) return;
    const XLSX = await import('xlsx');
    const filas = this.ticketsFiltrados.map((ticket) => ({
      Ticket: ticket.id ?? '',
      Cliente: this.clientes.get(ticket.clienteId)?.nombres ?? `#${ticket.clienteId}`,
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
