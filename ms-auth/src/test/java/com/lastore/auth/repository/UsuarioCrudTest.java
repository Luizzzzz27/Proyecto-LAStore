package com.lastore.auth.repository;

import static org.assertj.core.api.Assertions.assertThat;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import com.lastore.auth.model.Usuario;

@DataJpaTest
class UsuarioCrudTest {
    @Autowired
    private UsuarioRepository usuarioRepository;
    private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

    @Test
    void insertarUsuarioConPasswordCifrada() {
        Usuario guardado = usuarioRepository.saveAndFlush(nuevoUsuario("nuevo", "clave123"));
        assertThat(guardado.getId()).isNotNull();
        assertThat(guardado.getPassword()).isNotEqualTo("clave123");
        assertThat(passwordEncoder.matches("clave123", guardado.getPassword())).isTrue();
    }

    @Test
    void actualizarUsuarioExistente() {
        Usuario guardado = usuarioRepository.saveAndFlush(nuevoUsuario("actualizar", "original"));
        guardado.setNombreCompleto("Nombre actualizado");
        guardado.setRol("ADMIN");
        Usuario actualizado = usuarioRepository.saveAndFlush(guardado);
        assertThat(usuarioRepository.findById(actualizado.getId())).get()
            .extracting(Usuario::getNombreCompleto, Usuario::getRol)
            .containsExactly("Nombre actualizado", "ADMIN");
    }

    @Test
    void eliminarUsuario() {
        Usuario guardado = usuarioRepository.saveAndFlush(nuevoUsuario("eliminar", "clave"));
        usuarioRepository.deleteById(guardado.getId());
        usuarioRepository.flush();
        assertThat(usuarioRepository.findById(guardado.getId())).isEmpty();
    }

    @Test
    void listarUsuariosYValidarHashBcrypt() {
        usuarioRepository.saveAndFlush(nuevoUsuario("lista1", "secreto1"));
        usuarioRepository.saveAndFlush(nuevoUsuario("lista2", "secreto2"));
        List<Usuario> usuarios = usuarioRepository.findAll();
        assertThat(usuarios).hasSize(2);
        assertThat(passwordEncoder.matches("secreto1", usuarioRepository.findByUsername("lista1").orElseThrow().getPassword())).isTrue();
        assertThat(passwordEncoder.matches("secreto2", usuarioRepository.findByUsername("lista2").orElseThrow().getPassword())).isTrue();
    }

    private Usuario nuevoUsuario(String username, String rawPassword) {
        return new Usuario(null, username, passwordEncoder.encode(rawPassword), "Usuario de prueba", "TECNICO", true);
    }
}