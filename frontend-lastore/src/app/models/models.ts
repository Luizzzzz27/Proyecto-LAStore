export interface UsuarioSesion {
  id: number;
  username: string;
  nombreCompleto: string;
  rol: string;
  mensaje: string;
  token: string;
}

export interface Cliente {
  id?: number;
  dniRuc: string;
  nombres: string;
  telefono: string;
  correo: string;
}

export interface Ticket {
  id?: number;
  clienteId: number;
  tipoEquipo: string;
  marcaModelo: string;
  fallaReportada: string;
  estadoCotizacion: string;
  montoTotal: number;
  fechaRegistro?: string | null;
}

export interface Pago {
  id?: number;
  ticketId: number;
  montoPago: number;
  monto?: number;
  montoPagado?: number | null;
  saldoPendiente?: number | null;
  referenciaPago?: string | null;
  estadoPago: string;
  fechaRegistro?: string | null;
  metodoPago?: string | null;
}

export type MetodoPago = 'EFECTIVO' | 'YAPE_PLIN' | 'TRANSFERENCIA' | 'TARJETA';

export interface CobroRequest {
  montoAbono: number;
  metodoPago: MetodoPago;
  referenciaPago?: string;
}
