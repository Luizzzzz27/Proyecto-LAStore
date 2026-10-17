package com.lastore.auth.config;

import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;
import com.lastore.auth.model.Usuario;
import com.lastore.auth.repository.UsuarioRepository;

@Component
public class DataInitializer implements CommandLineRunner {
    private final UsuarioRepository usuarioRepository;
    private final BCryptPasswordEncoder passwordEncoder;

    public DataInitializer(UsuarioRepository usuarioRepository, BCryptPasswordEncoder passwordEncoder) {
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(String... args) {
        if (usuarioRepository.count() == 0) {
            usuarioRepository.save(new Usuario(null, "admin", passwordEncoder.encode("admin123"),
                "Luis Gonzales - Administrador LA Store", "ADMIN", true));
            usuarioRepository.save(new Usuario(null, "tecnico", passwordEncoder.encode("tecnico123"),
                "Especialista Soporte Técnico", "TECNICO", true));
        }
    }
}