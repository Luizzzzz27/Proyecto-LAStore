import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { finalize } from 'rxjs';
import { Pago } from '../../models/models';
import { PagoService } from '../../services/pago.service';
import { jsPDF } from 'jspdf';
import { autoTable } from 'jspdf-autotable';
import * as XLSX from 'xlsx';

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
  private fechaArchivo(): string {
    const hoy = new Date();
    const local = new Date(hoy.getTime() - hoy.getTimezoneOffset() * 60_000);
    return local.toISOString().slice(0, 10);
  }

  exportarPDF(): void {
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

    autoTable(doc, {
      startY: 34,
      head: [['Pago', 'Ticket origen', 'Monto', 'Estado']],
      body: this.pagos.map(pago => [
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

  exportarExcel(): void {
    const filas = this.pagos.map(pago => ({
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
