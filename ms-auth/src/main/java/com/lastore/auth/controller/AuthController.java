package com.lastore.auth.controller;

import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.lastore.auth.dto.ErrorResponse;
import com.lastore.auth.dto.LoginRequest;
import com.lastore.auth.dto.LoginResponse;
import com.lastore.auth.model.Usuario;
import com.lastore.auth.repository.UsuarioRepository;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final UsuarioRepository usuarioRepository;
    private final BCryptPasswordEncoder passwordEncoder;

    public AuthController(UsuarioRepository usuarioRepository, BCryptPasswordEncoder passwordEncoder) {
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody LoginRequest request) {
        if (request == null || isBlank(request.getUsername()) || isBlank(request.getPassword())) {
            return ResponseEntity.badRequest().body(new ErrorResponse("Username y password son obligatorios"));
        }
        return usuarioRepository.findByUsername(request.getUsername().trim())
            .filter(Usuario::isActivo)
            .filter(user -> passwordEncoder.matches(request.getPassword(), user.getPassword()))
            .<ResponseEntity<?>>map(user -> ResponseEntity.ok(new LoginResponse(user.getId(), user.getUsername(),
                user.getNombreCompleto(), user.getRol(), "Autenticación exitosa en LA Store", UUID.randomUUID().toString())))
            .orElseGet(() -> ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("Credenciales inválidas o usuario inactivo")));
    }

    @GetMapping("/usuarios")
    public List<Usuario> listar() { return usuarioRepository.findAll(); }

    @GetMapping("/usuarios/{id}")
    public ResponseEntity<?> obtener(@PathVariable Long id) {
        return usuarioRepository.findById(id).<ResponseEntity<?>>map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse("Usuario no encontrado")));
    }

    @PostMapping("/usuarios")
    public ResponseEntity<?> crear(@RequestBody Usuario usuario) {
        if (usuario == null || isBlank(usuario.getUsername()) || isBlank(usuario.getPassword())
                || isBlank(usuario.getNombreCompleto()) || isBlank(usuario.getRol())) {
            return ResponseEntity.badRequest().body(new ErrorResponse("Username, password, nombreCompleto y rol son obligatorios"));
        }
        if (usuarioRepository.findByUsername(usuario.getUsername().trim()).isPresent()) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorResponse("El username ya existe"));
        }
        usuario.setId(null);
        usuario.setUsername(usuario.getUsername().trim());
        usuario.setPassword(passwordEncoder.encode(usuario.getPassword()));
        return ResponseEntity.status(HttpStatus.CREATED).body(usuarioRepository.save(usuario));
    }

    @PutMapping("/usuarios/{id}")
    public ResponseEntity<?> actualizar(@PathVariable Long id, @RequestBody Usuario datos) {
        return usuarioRepository.findById(id).<ResponseEntity<?>>map(usuario -> {
            if (!isBlank(datos.getUsername())) usuario.setUsername(datos.getUsername().trim());
            if (!isBlank(datos.getNombreCompleto())) usuario.setNombreCompleto(datos.getNombreCompleto());
            if (!isBlank(datos.getRol())) usuario.setRol(datos.getRol());
            usuario.setActivo(datos.isActivo());
            if (!isBlank(datos.getPassword())) usuario.setPassword(passwordEncoder.encode(datos.getPassword()));
            return ResponseEntity.ok(usuarioRepository.save(usuario));
        }).orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse("Usuario no encontrado")));
    }

    @DeleteMapping("/usuarios/{id}")
    public ResponseEntity<?> eliminar(@PathVariable Long id) {
        if (!usuarioRepository.existsById(id)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse("Usuario no encontrado"));
        }
        usuarioRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private boolean isBlank(String value) { return value == null || value.isBlank(); }
}