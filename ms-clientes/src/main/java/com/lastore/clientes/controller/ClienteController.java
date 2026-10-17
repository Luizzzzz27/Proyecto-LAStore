package com.lastore.clientes.controller;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import com.lastore.clientes.model.Cliente;
import com.lastore.clientes.repository.ClienteRepository;

@RestController
@RequestMapping("/api/v1/clientes")
public class ClienteController {
    private final ClienteRepository clienteRepository;

    public ClienteController(ClienteRepository clienteRepository) {
        this.clienteRepository = clienteRepository;
    }

    @GetMapping
    public List<Cliente> listar() { return clienteRepository.findAll(); }

    @GetMapping("/{id}")
    public Cliente obtener(@PathVariable Long id) {
        return clienteRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Cliente no encontrado"));
    }

    @PostMapping
    public ResponseEntity<Cliente> crear(@RequestBody Cliente cliente) {
        cliente.setId(null);
        return ResponseEntity.status(HttpStatus.CREATED).body(clienteRepository.save(cliente));
    }

    @PutMapping("/{id}")
    public Cliente actualizar(@PathVariable Long id, @RequestBody Cliente datos) {
        Cliente cliente = obtener(id);
        cliente.setDniRuc(datos.getDniRuc());
        cliente.setNombres(datos.getNombres());
        cliente.setTelefono(datos.getTelefono());
        cliente.setCorreo(datos.getCorreo());
        return clienteRepository.save(cliente);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        Cliente cliente = obtener(id);
        clienteRepository.delete(cliente);
        return ResponseEntity.noContent().build();
    }
}