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