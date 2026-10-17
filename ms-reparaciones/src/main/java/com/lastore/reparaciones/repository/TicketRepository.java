package com.lastore.reparaciones.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.reparaciones.model.Ticket;

public interface TicketRepository extends JpaRepository<Ticket, Long> { }