import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { finalize } from 'rxjs';
import { Cliente, Pago, Ticket, CobroRequest, MetodoPago } from '../../models/models';
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
  pagoSeleccionado: Pago | null = null;
  modalidadCobro: 'TOTAL' | 'PARCIAL' = 'TOTAL';
  montoAbono = 0;
  metodoCobro: MetodoPago | '' = '';
  referenciaCobro = '';
  errorCobro = '';

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

  montoTotal(pago: Pago): number { return Number(pago.monto ?? pago.montoPago ?? 0); }
  abonado(pago: Pago): number { return Number(pago.montoPagado ?? (pago.estadoPago === 'PAGADO' ? this.montoTotal(pago) : 0)); }
  saldo(pago: Pago): number {
    if (pago.estadoPago === 'PAGADO' || pago.estadoPago === 'ANULADO') return 0;
    return Number(pago.saldoPendiente ?? Math.max(0, Math.round((this.montoTotal(pago) - this.abonado(pago)) * 100) / 100));
  }
  nombreCliente(pago: Pago): string {
    const ticket = this.tickets.get(pago.ticketId);
    return ticket ? this.clientes.get(ticket.clienteId)?.nombres ?? `Cliente no registrado (#${ticket.clienteId})` : 'Cliente no disponible';
  }
  resumenEquipo(pago: Pago): string {
    const ticket = this.tickets.get(pago.ticketId);
    return ticket ? `${ticket.tipoEquipo} - ${ticket.marcaModelo}` : '';
  }

  procesar(pago: Pago): void {
    if (!pago.id || !['PENDIENTE', 'PARCIAL'].includes(pago.estadoPago)) return;
    this.pagoSeleccionado = pago;
    this.modalidadCobro = 'TOTAL';
    this.montoAbono = this.saldo(pago);
    this.metodoCobro = '';
    this.referenciaCobro = '';
    this.errorCobro = '';
  }

  elegirModalidad(modalidad: 'TOTAL' | 'PARCIAL'): void {
    this.modalidadCobro = modalidad;
    this.montoAbono = modalidad === 'TOTAL' && this.pagoSeleccionado ? this.saldo(this.pagoSeleccionado) : 0;
  }

  adelantoMitad(): void {
    if (!this.pagoSeleccionado) return;
    this.montoAbono = Math.min(this.saldo(this.pagoSeleccionado), Math.round(this.montoTotal(this.pagoSeleccionado) * 50) / 100);
  }

  get cobroValido(): boolean {
    if (!this.pagoSeleccionado || !this.metodoCobro || !Number.isFinite(this.montoAbono)) return false;
    const centavos = this.montoAbono * 100;
    return centavos > 0 && Math.abs(centavos - Math.round(centavos)) < 0.000001
      && Math.round(centavos) <= Math.round(this.saldo(this.pagoSeleccionado) * 100)
      && this.referenciaCobro.length <= 500;
  }

  cerrarCobro(): void { if (!this.procesandoId) this.pagoSeleccionado = null; }

  registrarCobro(): void {
    if (!this.cobroValido || !this.pagoSeleccionado?.id || this.procesandoId) {
      this.errorCobro = 'Seleccione un método e ingrese un abono mayor a cero, con hasta dos decimales y que no supere el saldo.';
      return;
    }
    const pago = this.pagoSeleccionado;
    const solicitud: CobroRequest = { montoAbono: this.montoAbono, metodoPago: this.metodoCobro as MetodoPago, referenciaPago: this.referenciaCobro.trim() };
    this.procesandoId = pago.id;
    this.errorCobro = '';
    this.pagoService.procesarPago(pago.id!, solicitud).pipe(finalize(() => {
      this.procesandoId = undefined;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: actualizado => {
        this.pagoSeleccionado = null;
        this.mensaje = actualizado.estadoPago === 'PAGADO' ? 'Saldo cancelado. Pago completado correctamente.' : 'Adelanto registrado. El pago mantiene saldo pendiente.';
        this.cargarPagos();
      },
      error: respuesta => { this.errorCobro = respuesta.error?.message || 'No se pudo registrar el abono. Actualice los pagos y revise el saldo.'; }
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
    const doc = new jsPDF({ orientation: 'landscape' });
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

    const total = filas.reduce((suma, pago) => suma + this.montoTotal(pago), 0);
    doc.text(`Periodo: ${this.fechaDesde || 'Todos'} al ${this.fechaHasta || 'Todos'} | Total registros: ${filas.length} | Monto total: S/ ${total.toFixed(2)}`, ancho / 2, 32, { align: 'center' });
    autoTable(doc, {
      startY: 39,
      head: [['Pago', 'Ticket / Cliente', 'Total', 'Abonado', 'Saldo', 'Método', 'Estado']],
      body: filas.map(pago => [
        `#${pago.id ?? ''}`,
        `Ticket #${pago.ticketId} - ${this.nombreCliente(pago)}`,
        `S/ ${this.montoTotal(pago).toFixed(2)}`,
        `S/ ${this.abonado(pago).toFixed(2)}`,
        `S/ ${this.saldo(pago).toFixed(2)}`,
        pago.metodoPago || 'Sin registrar',
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
      Cliente: this.nombreCliente(pago),
      Monto: this.montoTotal(pago),
      Abonado: this.abonado(pago),
      Saldo: this.saldo(pago),
      'Método': pago.metodoPago || 'Sin registrar',
      Referencia: pago.referenciaPago || '',
      Estado: pago.estadoPago
    }));

    const hoja = XLSX.utils.json_to_sheet(filas, {
      header: ['Pago', 'Ticket origen', 'Cliente', 'Monto', 'Abonado', 'Saldo', 'Método', 'Referencia', 'Estado']
    });
    hoja['!cols'] = [
      { wch: 12 }, { wch: 18 }, { wch: 35 }, { wch: 15 }, { wch: 15 }, { wch: 15 }, { wch: 30 }, { wch: 50 }, { wch: 18 }
    ];

    const libro = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(libro, hoja, 'Pagos');
    XLSX.writeFile(libro, `Reporte_LA_Store_${this.fechaArchivo()}.xlsx`);
  }
}
