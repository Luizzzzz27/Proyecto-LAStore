package com.lastore.reparaciones.controller;

import java.math.BigDecimal;
import java.util.List;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
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
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;

@RestController
@RequestMapping("/api/v1/tickets")
public class TicketController {
    private static final String ESTADO_APROBADA = "APROBADA";
    private static final String ESTADO_ANULADA = "ANULADA";
    private final TicketRepository ticketRepository;
    private final RabbitTemplate rabbitTemplate;

    public TicketController(TicketRepository ticketRepository, RabbitTemplate rabbitTemplate) {
        this.ticketRepository = ticketRepository;
        this.rabbitTemplate = rabbitTemplate;
    }

    @GetMapping
    public List<Ticket> listar() { return ticketRepository.findAll(); }

    @GetMapping("/{id}")
    public Ticket obtener(@PathVariable Long id) {
        return ticketRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Ticket no encontrado"));
    }

    @PostMapping
    public ResponseEntity<Ticket> crear(@RequestBody Ticket ticket) {
        ticket.setId(null);
        if (ticket.getEstadoCotizacion() == null || ticket.getEstadoCotizacion().isBlank()) {
            ticket.setEstadoCotizacion("PENDIENTE_ENVIO");
        }
        if (ticket.getMontoTotal() == null) ticket.setMontoTotal(BigDecimal.ZERO);
        return ResponseEntity.status(HttpStatus.CREATED).body(ticketRepository.save(ticket));
    }

    @PutMapping("/{id}")
    public Ticket actualizar(@PathVariable Long id, @RequestBody Ticket datos) {
        Ticket ticket = obtener(id);
        boolean debePublicarAprobacion = !ESTADO_APROBADA.equals(ticket.getEstadoCotizacion())
            && ESTADO_APROBADA.equals(datos.getEstadoCotizacion());

        ticket.setClienteId(datos.getClienteId());
        ticket.setTipoEquipo(datos.getTipoEquipo());
        ticket.setMarcaModelo(datos.getMarcaModelo());
        ticket.setFallaReportada(datos.getFallaReportada());
        ticket.setEstadoCotizacion(datos.getEstadoCotizacion());
        ticket.setMontoTotal(datos.getMontoTotal());

        Ticket guardado = ticketRepository.save(ticket);
        if (debePublicarAprobacion) publicarCotizacionAprobada(guardado);
        return guardado;
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        Ticket ticket = obtener(id);
        ticketRepository.delete(ticket);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{id}/aprobar-cotizacion")
    public ResponseEntity<Ticket> aprobarCotizacion(@PathVariable Long id) {
        Ticket ticket = obtener(id);
        ticket.setEstadoCotizacion(ESTADO_APROBADA);
        Ticket guardado = ticketRepository.save(ticket);
        publicarCotizacionAprobada(guardado);
        return ResponseEntity.ok(guardado);
    }

    @PutMapping("/{id}/anular")
    public ResponseEntity<Ticket> anular(@PathVariable Long id) {
        Ticket ticket = obtener(id);
        ticket.setEstadoCotizacion(ESTADO_ANULADA);
        return ResponseEntity.ok(ticketRepository.save(ticket));
    }

    private void publicarCotizacionAprobada(Ticket ticket) {
        if (ticket.getMontoTotal() != null && ticket.getMontoTotal().compareTo(BigDecimal.ZERO) > 0) {
            String mensaje = ticket.getId() + ":" + ticket.getMontoTotal().toPlainString();
            rabbitTemplate.convertAndSend(RabbitMQConfig.COLA_COTIZACION_APROBADA, mensaje);
        }
    }
}