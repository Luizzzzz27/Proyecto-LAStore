package com.lastore.clientes.repository;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase.Replace;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import com.lastore.clientes.model.Cliente;

@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.NONE)
class ClienteRepositoryTest {
    @Autowired
    private ClienteRepository clienteRepository;

    @Test
    void testInsertarCliente() {
        Cliente cliente = new Cliente(null, "70000001", "Cliente Insertado", "900000001", "insertado@lastore.pe");
        Cliente guardado = clienteRepository.saveAndFlush(cliente);

        assertThat(guardado.getId()).isNotNull();
    }

    @Test
    void testActualizarCliente() {
        Cliente cliente = new Cliente(null, "70000002", "Cliente Actualizado", "900000002", "actualizado@lastore.pe");
        Cliente guardado = clienteRepository.saveAndFlush(cliente);
        guardado.setTelefono("999888777");
        clienteRepository.saveAndFlush(guardado);

        Cliente actualizado = clienteRepository.findById(guardado.getId()).orElseThrow();
        assertThat(actualizado.getTelefono()).isEqualTo("999888777");
    }

    @Test
    void testListarClientes() {
        clienteRepository.saveAndFlush(new Cliente(null, "70000003", "Cliente Lista Uno", "900000003", "lista1@lastore.pe"));
        clienteRepository.saveAndFlush(new Cliente(null, "70000004", "Cliente Lista Dos", "900000004", "lista2@lastore.pe"));

        List<Cliente> clientes = clienteRepository.findAll();
        assertThat(clientes).hasSizeGreaterThanOrEqualTo(2);
    }

    @Test
    void testEliminarCliente() {
        Cliente cliente = new Cliente(null, "70000005", "Cliente Eliminado", "900000005", "eliminado@lastore.pe");
        Cliente guardado = clienteRepository.saveAndFlush(cliente);
        clienteRepository.deleteById(guardado.getId());
        clienteRepository.flush();

        assertThat(clienteRepository.findById(guardado.getId())).isEmpty();
    }
}