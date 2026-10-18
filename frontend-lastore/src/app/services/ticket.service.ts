import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Ticket } from '../models/models';

@Injectable({ providedIn: 'root' })
export class TicketService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/tickets';
  constructor(private readonly http: HttpClient) {}

  listar(): Observable<Ticket[]> { return this.http.get<Ticket[]>(this.apiUrl); }
  obtener(id: number): Observable<Ticket> { return this.http.get<Ticket>(`${this.apiUrl}/${id}`); }
  crear(ticket: Ticket): Observable<Ticket> { return this.http.post<Ticket>(this.apiUrl, ticket); }
  actualizar(id: number, ticket: Ticket): Observable<Ticket> { return this.http.put<Ticket>(`${this.apiUrl}/${id}`, ticket); }
  eliminar(id: number): Observable<void> { return this.http.delete<void>(`${this.apiUrl}/${id}`); }
  aprobarCotizacion(id: number): Observable<Ticket> { return this.http.put<Ticket>(`${this.apiUrl}/${id}/aprobar-cotizacion`, {}); }
  anularTicket(id: number): Observable<Ticket> { return this.http.put<Ticket>(`${this.apiUrl}/${id}/anular`, {}); }
}