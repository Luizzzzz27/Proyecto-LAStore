import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { finalize } from 'rxjs';
import { Cliente, Pago, Ticket } from '../../models/models';
import { PagoService } from '../../services/pago.service';
import { TicketService } from '../../services/ticket.service';
import { ClienteService } from '../../services/cliente.service';

@Component({ selector: 'app-pagos', standalone: true, imports: [CurrencyPipe, FormsModule], templateUrl: './pagos.component.html' })
export class PagosComponent implements OnInit {
  pagos: Pago[] = [];
  tickets = new Map<number, Ticket>();
  clientes = new Map<number, Cliente>();
  terminoBusqueda = '';
  estadoFiltro = '';
  fechaDesde = '';
  fechaHasta = '';
  cargando = false;
  procesandoId?: number;
  anulandoId?: number;
  mensaje = '';
  error = '';

  constructor(private readonly pagoService: PagoService, private readonly changeDetectorRef: ChangeDetectorRef,
    private readonly ticketService: TicketService, private readonly clienteService: ClienteService) {}
  ngOnInit(): void {
    this.cargarPagos();
    this.ticketService.listar().subscribe({ next: tickets => { this.tickets = new Map(tickets.filter(t => t.id != null).map(t => [t.id!, t])); this.changeDetectorRef.markForCheck(); }, error: () => { this.error = 'No se pudieron cargar los tickets para la búsqueda.'; this.changeDetectorRef.markForCheck(); } });
    this.clienteService.listar().subscribe({ next: clientes => { this.clientes = new Map(clientes.filter(c => c.id != null).map(c => [c.id!, c])); this.changeDetectorRef.markForCheck(); }, error: () => { this.error = 'No se pudieron cargar los clientes para la búsqueda.'; this.changeDetectorRef.markForCheck(); } });
  }

  get pagosFiltrados(): Pago[] {
    const texto = this.terminoBusqueda.trim().toLocaleLowerCase('es-PE');
    return this.pagos.filter(pago => {
      const ticket = this.tickets.get(pago.ticketId);
      const cliente = ticket ? this.clientes.get(ticket.clienteId) : undefined;
      const valores = [pago.id, `#${pago.id}`, pago.ticketId, `#${pago.ticketId}`,
        cliente?.nombres, cliente?.dniRuc, pago.metodoPago];
      const fecha = pago.fechaRegistro?.slice(0, 10);
      return (!texto || valores.some(valor => String(valor ?? '').toLocaleLowerCase('es-PE').includes(texto)))
        && (!this.estadoFiltro || pago.estadoPago === this.estadoFiltro)
        && ((!this.fechaDesde && !this.fechaHasta) || (!!fecha && (!this.fechaDesde || fecha >= this.fechaDesde) && (!this.fechaHasta || fecha <= this.fechaHasta)));
    });
  }
  limpiarFiltros(): void { this.terminoBusqueda = ''; this.estadoFiltro = ''; this.fechaDesde = ''; this.fechaHasta = ''; }

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
  private fechaArchivo(): string {
    const hoy = new Date();
    const local = new Date(hoy.getTime() - hoy.getTimezoneOffset() * 60_000);
    return local.toISOString().slice(0, 10);
  }

  async exportarPDF(): Promise<void> {
    const filas = this.pagosFiltrados;
    if (!filas.length) return;
    const [{ jsPDF }, { autoTable }] = await Promise.all([import('jspdf'), import('jspdf-autotable')]);
    const doc = new jsPDF();
    const ancho = doc.internal.pageSize.getWidth();

    doc.setFont('helvetica', 'bold');
    doc.setFontSize(17);
    doc.text('Reporte de Pagos - LA Store', ancho / 2, 18, {
      align: 'center'
    });

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.text(
      `Generado: ${new Date().toLocaleString('es-PE')}`,
      ancho / 2,
      26,
      { align: 'center' }
    );

    const total = filas.reduce((suma, pago) => suma + Number(pago.montoPago || 0), 0);
    doc.text(`Periodo: ${this.fechaDesde || 'Todos'} al ${this.fechaHasta || 'Todos'} | Total registros: ${filas.length} | Monto total: S/ ${total.toFixed(2)}`, ancho / 2, 32, { align: 'center' });
    autoTable(doc, {
      startY: 39,
      head: [['Pago', 'Ticket origen', 'Monto', 'Estado']],
      body: filas.map(pago => [
        `#${pago.id ?? ''}`,
        `Ticket #${pago.ticketId}`,
        `S/ ${Number(pago.montoPago).toFixed(2)}`,
        pago.estadoPago
      ]),
      theme: 'striped',
      headStyles: { fillColor: [33, 37, 41] },
      styles: { fontSize: 10, cellPadding: 4 }
    });

    doc.save(`Reporte_LA_Store_Pagos_${this.fechaArchivo()}.pdf`);
  }

  async exportarExcel(): Promise<void> {
    if (!this.pagosFiltrados.length) return;
    const XLSX = await import('xlsx');
    const filas = this.pagosFiltrados.map(pago => ({
      Pago: pago.id ?? '',
      'Ticket origen': pago.ticketId,
      Monto: Number(pago.montoPago),
      Estado: pago.estadoPago
    }));

    const hoja = XLSX.utils.json_to_sheet(filas, {
      header: ['Pago', 'Ticket origen', 'Monto', 'Estado']
    });
    hoja['!cols'] = [
      { wch: 12 }, { wch: 18 }, { wch: 15 }, { wch: 18 }
    ];

    const libro = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(libro, hoja, 'Pagos');
    XLSX.writeFile(libro, `Reporte_LA_Store_${this.fechaArchivo()}.xlsx`);
  }
}
