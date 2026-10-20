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
import com.lastore.pagos.dto.CobroRequest;
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
        return ResponseEntity.status(HttpStatus.CREATED).body(stateService.crear(pago));
    }
    @PutMapping("/{id}") public Pago actualizar(@PathVariable Long id, @RequestBody Pago datos) {
        return stateService.actualizar(id, datos);
    }
    @DeleteMapping("/{id}") public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        stateService.anular(id);
        return ResponseEntity.noContent().build();
    }
    @PutMapping("/{id}/procesar") public ResponseEntity<Pago> procesar(@PathVariable Long id,
            @RequestBody(required = false) CobroRequest solicitud) {
        return ResponseEntity.ok(stateService.procesar(id, solicitud));
    }
    @PutMapping("/{id}/anular") public ResponseEntity<Pago> anular(@PathVariable Long id) {
        return ResponseEntity.ok(stateService.anular(id));
    }
}
