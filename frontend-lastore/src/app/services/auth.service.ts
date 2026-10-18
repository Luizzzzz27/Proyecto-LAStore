import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';
import { UsuarioSesion } from '../models/models';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly apiUrl = 'http://localhost:8080/api/v1/auth';
  private readonly storageKey = 'lastore_usuario';

  constructor(private readonly http: HttpClient) {}

  login(username: string, password: string): Observable<UsuarioSesion> {
    return this.http.post<UsuarioSesion>(`${this.apiUrl}/login`, { username, password }).pipe(
      tap(usuario => localStorage.setItem(this.storageKey, JSON.stringify(usuario)))
    );
  }

  obtenerUsuario(): UsuarioSesion | null {
    const value = localStorage.getItem(this.storageKey);
    if (!value) return null;
    try { return JSON.parse(value) as UsuarioSesion; } catch { return null; }
  }

  estaAutenticado(): boolean { return this.obtenerUsuario() !== null; }
  cerrarSesion(): void { localStorage.removeItem(this.storageKey); }
}