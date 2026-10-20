package com.lastore.pagos.controller;

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
import com.lastore.pagos.model.Pago;
import com.lastore.pagos.repository.PagoRepository;
import com.lastore.pagos.service.PagoStateService;

@RestController
@RequestMapping("/api/v1/pagos")
public class PagoController {
    private final PagoRepository pagoRepository;
    private final PagoStateService stateService;

    public PagoController(PagoRepository pagoRepository, PagoStateService stateService) {
        this.pagoRepository = pagoRepository;
        this.stateService = stateService;
    }

    @GetMapping public List<Pago> listar() { return pagoRepository.findAll(); }
    @GetMapping("/{id}") public Pago obtener(@PathVariable Long id) {
        return pagoRepository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Pago no encontrado"));
    }
    @PostMapping public ResponseEntity<Pago> crear(@RequestBody Pago pago) {
        pago.setId(null);
        if (pago.getEstadoPago() == null || pago.getEstadoPago().isBlank()) pago.setEstadoPago("PENDIENTE");
        return ResponseEntity.status(HttpStatus.CREATED).body(pagoRepository.save(pago));
    }
    @PutMapping("/{id}") public Pago actualizar(@PathVariable Long id, @RequestBody Pago datos) {
        Pago pago = obtener(id);
        pago.setTicketId(datos.getTicketId());
        pago.setMontoPago(datos.getMontoPago());
        pago.setEstadoPago(datos.getEstadoPago());
        pago.setMetodoPago(datos.getMetodoPago());
        return pagoRepository.save(pago);
    }
    @DeleteMapping("/{id}") public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        pagoRepository.delete(obtener(id));
        return ResponseEntity.noContent().build();
    }
    @PutMapping("/{id}/procesar") public ResponseEntity<Pago> procesar(@PathVariable Long id) {
        Pago pago = obtener(id);
        pago.setEstadoPago("PAGADO");
        return ResponseEntity.ok(pagoRepository.save(pago));
    }
    @PutMapping("/{id}/anular") public ResponseEntity<Pago> anular(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.anularPago(obtener(id)));
    }
}
