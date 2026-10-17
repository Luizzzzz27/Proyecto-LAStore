package com.lastore.clientes.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.clientes.model.Cliente;

public interface ClienteRepository extends JpaRepository<Cliente, Long> { }