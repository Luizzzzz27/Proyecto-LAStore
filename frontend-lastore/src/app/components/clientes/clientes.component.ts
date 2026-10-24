import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
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
  terminoBusqueda = '';
  formulario: Cliente = this.nuevoCliente();
  modalAbierto = false;
  cargando = false;
  guardando = false;
  mensaje = '';
  error = '';

  constructor(
    private readonly clienteService: ClienteService,
    private readonly changeDetectorRef: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.cargarClientes();
  }

  get clientesFiltrados(): Cliente[] {
    const termino = this.normalizar(this.terminoBusqueda.trim());
    if (!termino) return this.clientes;
    return this.clientes.filter(cliente =>
      [cliente.dniRuc, cliente.nombres, cliente.correo, cliente.telefono]
        .some(valor => this.normalizar(valor ?? '').includes(termino))
    );
  }

  limpiarFiltros(): void {
    this.terminoBusqueda = '';
  }

  private normalizar(valor: string): string {
    return valor.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es-PE');
  }

  cargarClientes(): void {
    this.cargando = true;
    this.error = '';
    this.clienteService.listar().pipe(
      finalize(() => {
        this.cargando = false;
        this.changeDetectorRef.markForCheck();
      })
    ).subscribe({
      next: clientes => this.clientes = clientes,
      error: () => this.error = 'No se pudo cargar la lista de clientes.'
    });
  }

  abrirCrear(): void {
    this.formulario = this.nuevoCliente();
    this.modalAbierto = true;
  }

  abrirEditar(cliente: Cliente): void {
    this.formulario = { ...cliente };
    this.modalAbierto = true;
  }

  guardar(): void {
    this.guardando = true;
    const operacion = this.formulario.id
      ? this.clienteService.actualizar(this.formulario.id, this.formulario)
      : this.clienteService.crear(this.formulario);
    operacion.pipe(finalize(() => {
      this.guardando = false;
      this.changeDetectorRef.markForCheck();
    })).subscribe({
      next: () => {
        this.modalAbierto = false;
        this.mensaje = 'Cliente guardado correctamente.';
        this.cargarClientes();
      },
      error: () => this.error = 'No se pudo guardar el cliente. Verifique el DNI/RUC.'
    });
  }

  eliminar(cliente: Cliente): void {
    if (!cliente.id || !confirm(`¿Eliminar a ${cliente.nombres}?`)) return;
    this.clienteService.eliminar(cliente.id).subscribe({
      next: () => {
        this.mensaje = 'Cliente eliminado.';
        this.cargarClientes();
      },
      error: () => {
        this.error = 'No se pudo eliminar el cliente.';
        this.changeDetectorRef.markForCheck();
      }
    });
  }

  private nuevoCliente(): Cliente {
    return { dniRuc: '', nombres: '', telefono: '', correo: '' };
  }

  private fechaArchivo(): string {
    const hoy = new Date();
    const local = new Date(hoy.getTime() - hoy.getTimezoneOffset() * 60_000);
    return local.toISOString().slice(0, 10);
  }

  async exportarPDF(): Promise<void> {
    const clientes = this.clientesFiltrados;
    if (!clientes.length) return;
    const [{ jsPDF }, { autoTable }] = await Promise.all([import('jspdf'), import('jspdf-autotable')]);
    const documento = new jsPDF({ orientation: 'landscape' });
    const ancho = documento.internal.pageSize.getWidth();

    documento.setFont('helvetica', 'bold');
    documento.setFontSize(17);
    documento.text('Directorio de Clientes - LA Store', ancho / 2, 18, { align: 'center' });
    documento.setFont('helvetica', 'normal');
    documento.setFontSize(10);
    documento.text(`Generado: ${new Date().toLocaleString('es-PE')} | Total registros: ${clientes.length}`, ancho / 2, 26, { align: 'center' });

    autoTable(documento, {
      startY: 34,
      head: [['ID', 'DNI / RUC', 'Cliente / Razón social', 'Teléfono', 'Correo electrónico']],
      body: clientes.map(cliente => [
        `#${cliente.id ?? ''}`,
        cliente.dniRuc,
        cliente.nombres,
        cliente.telefono || '—',
        cliente.correo || '—'
      ]),
      theme: 'striped',
      headStyles: { fillColor: [33, 37, 41] },
      styles: { fontSize: 9, cellPadding: 3 }
    });
    documento.save(`Directorio_Clientes_LA_Store_${this.fechaArchivo()}.pdf`);
  }

  async exportarExcel(): Promise<void> {
    const clientes = this.clientesFiltrados;
    if (!clientes.length) return;
    const XLSX = await import('xlsx');
    const filas = clientes.map(cliente => ({
      ID: cliente.id ?? '',
      'DNI / RUC': cliente.dniRuc,
      'Cliente / Razón social': cliente.nombres,
      Teléfono: cliente.telefono || '',
      'Correo electrónico': cliente.correo || ''
    }));
    const hoja = XLSX.utils.json_to_sheet(filas);
    hoja['!cols'] = [{ wch: 10 }, { wch: 18 }, { wch: 40 }, { wch: 18 }, { wch: 35 }];
    const libro = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(libro, hoja, 'Clientes');
    XLSX.writeFile(libro, `Directorio_Clientes_LA_Store_${this.fechaArchivo()}.xlsx`);
  }
}
