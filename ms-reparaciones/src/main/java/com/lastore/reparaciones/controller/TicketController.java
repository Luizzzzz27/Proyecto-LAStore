package com.lastore.reparaciones.controller;

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
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;
import com.lastore.reparaciones.service.TicketStateService;

@RestController
@RequestMapping("/api/v1/tickets")
public class TicketController {
    private final TicketRepository ticketRepository;
    private final TicketStateService stateService;

    public TicketController(TicketRepository ticketRepository, TicketStateService stateService) {
        this.ticketRepository = ticketRepository;
        this.stateService = stateService;
    }

    @GetMapping public List<Ticket> listar() { return ticketRepository.findAll(); }
    @GetMapping("/{id}") public Ticket obtener(@PathVariable Long id) { return stateService.obtener(id); }
    @PostMapping public ResponseEntity<Ticket> crear(@RequestBody Ticket ticket) {
        return ResponseEntity.status(HttpStatus.CREATED).body(stateService.crear(ticket));
    }
    @PutMapping("/{id}") public Ticket actualizar(@PathVariable Long id, @RequestBody Ticket datos) {
        return stateService.actualizar(id, datos);
    }
    @PutMapping("/{id}/aprobar-cotizacion") public ResponseEntity<Ticket> aprobar(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.aprobar(id));
    }
    @PutMapping("/{id}/anular") public ResponseEntity<Ticket> anular(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.anular(id));
    }
    @DeleteMapping("/{id}") public ResponseEntity<Ticket> eliminarLogicamente(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.anular(id));
    }
}