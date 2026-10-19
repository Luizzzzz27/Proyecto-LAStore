package com.lastore.reparaciones.service;

import java.math.BigDecimal;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import com.lastore.reparaciones.config.RabbitMQConfig;
import com.lastore.reparaciones.model.EstadoCotizacion;
import com.lastore.reparaciones.model.Ticket;
import com.lastore.reparaciones.repository.TicketRepository;

@Service
public class TicketStateService {
    private final TicketRepository ticketRepository;
    private final RabbitTemplate rabbitTemplate;

    public TicketStateService(TicketRepository ticketRepository, RabbitTemplate rabbitTemplate) {
        this.ticketRepository = ticketRepository;
        this.rabbitTemplate = rabbitTemplate;
    }

    public Ticket obtener(Long id) {
        return ticketRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Ticket no encontrado"));
    }

    public Ticket crear(Ticket ticket) {
        ticket.setId(null);
        if (ticket.getEstadoCotizacion() == null || ticket.getEstadoCotizacion().isBlank()) {
            ticket.setEstadoCotizacion(EstadoCotizacion.PENDIENTE_ENVIO.name());
        }
        EstadoCotizacion.desde(ticket.getEstadoCotizacion());
        if (ticket.getMontoTotal() == null) ticket.setMontoTotal(BigDecimal.ZERO);
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public Ticket actualizar(Long id, Ticket datos) {
        Ticket ticket = obtener(id);
        EstadoCotizacion anterior = EstadoCotizacion.desde(ticket.getEstadoCotizacion());
        EstadoCotizacion siguiente = EstadoCotizacion.desde(datos.getEstadoCotizacion());
        anterior.validarTransicion(siguiente);
        ticket.setClienteId(datos.getClienteId());
        ticket.setTipoEquipo(datos.getTipoEquipo());
        ticket.setMarcaModelo(datos.getMarcaModelo());
        ticket.setFallaReportada(datos.getFallaReportada());
        ticket.setEstadoCotizacion(siguiente.name());
        ticket.setMontoTotal(datos.getMontoTotal());
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public Ticket aprobar(Long id) {
        Ticket ticket = obtener(id);
        EstadoCotizacion.desde(ticket.getEstadoCotizacion()).validarTransicion(EstadoCotizacion.APROBADA);
        ticket.setEstadoCotizacion(EstadoCotizacion.APROBADA.name());
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public Ticket anular(Long id) {
        Ticket ticket = obtener(id);
        ticket.setEstadoCotizacion(EstadoCotizacion.ANULADA.name());
        Ticket guardado = ticketRepository.save(ticket);
        sincronizarEstadoConPagos(guardado);
        return guardado;
    }

    public void anularDesdePago(Long ticketId) {
        ticketRepository.findById(ticketId).ifPresent(ticket -> {
            ticket.setEstadoCotizacion(EstadoCotizacion.ANULADA.name());
            ticketRepository.save(ticket);
        });
    }

    public void sincronizarEstadoConPagos(Ticket ticket) {
        EstadoCotizacion estado = EstadoCotizacion.desde(ticket.getEstadoCotizacion());
        if (estado == EstadoCotizacion.APROBADA) {
            if (ticket.getMontoTotal() != null && ticket.getMontoTotal().compareTo(BigDecimal.ZERO) > 0) {
                rabbitTemplate.convertAndSend(RabbitMQConfig.APROBADA,
                    ticket.getId() + ":" + ticket.getMontoTotal().toPlainString());
            } else {
                rabbitTemplate.convertAndSend(RabbitMQConfig.CANCELADA, String.valueOf(ticket.getId()));
            }
        } else {
            rabbitTemplate.convertAndSend(RabbitMQConfig.CANCELADA, String.valueOf(ticket.getId()));
        }
    }
}