import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../services/auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './login.component.html',
  styleUrl: './login.component.css'
})
export class LoginComponent {
  username = '';
  password = '';
  mensajeError = '';
  cargando = false;

  constructor(private readonly authService: AuthService, private readonly router: Router) {}

  ingresar(): void {
    if (!this.username.trim() || !this.password) {
      this.mensajeError = 'Ingrese su usuario y contraseña.';
      return;
    }
    this.cargando = true;
    this.mensajeError = '';
    this.authService.login(this.username.trim(), this.password).pipe(
      finalize(() => this.cargando = false)
    ).subscribe({
      next: () => this.router.navigate(['/dashboard']),
      error: error => this.mensajeError = error?.error?.mensaje ?? 'No se pudo iniciar sesión. Verifique sus credenciales.'
    });
  }
}