import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Cliente } from '../models/models';

@Injectable({ providedIn: 'root' })
export class ClienteService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/clientes';
  constructor(private readonly http: HttpClient) {}

  listar(): Observable<Cliente[]> { return this.http.get<Cliente[]>(this.apiUrl); }
  obtener(id: number): Observable<Cliente> { return this.http.get<Cliente>(`${this.apiUrl}/${id}`); }
  crear(cliente: Cliente): Observable<Cliente> { return this.http.post<Cliente>(this.apiUrl, cliente); }
  actualizar(id: number, cliente: Cliente): Observable<Cliente> { return this.http.put<Cliente>(`${this.apiUrl}/${id}`, cliente); }
  eliminar(id: number): Observable<void> { return this.http.delete<void>(`${this.apiUrl}/${id}`); }
}