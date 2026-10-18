import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Pago } from '../models/models';

@Injectable({ providedIn: 'root' })
export class PagoService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/pagos';
  constructor(private readonly http: HttpClient) {}

  listar(): Observable<Pago[]> { return this.http.get<Pago[]>(this.apiUrl); }
  procesarPago(id: number): Observable<Pago> { return this.http.put<Pago>(`${this.apiUrl}/${id}/procesar`, {}); }
  anularPago(id: number): Observable<Pago> { return this.http.put<Pago>(`${this.apiUrl}/${id}/anular`, {}); }
}