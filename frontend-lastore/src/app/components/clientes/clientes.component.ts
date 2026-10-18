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