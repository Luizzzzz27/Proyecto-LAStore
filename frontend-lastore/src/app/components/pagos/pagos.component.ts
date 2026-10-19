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