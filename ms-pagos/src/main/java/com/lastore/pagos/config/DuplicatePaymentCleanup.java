package com.lastore.pagos.config;

import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;
import com.lastore.pagos.service.PagoStateService;

@Component
public class DuplicatePaymentCleanup implements CommandLineRunner {
    private final PagoStateService stateService;

    public DuplicatePaymentCleanup(PagoStateService stateService) { this.stateService = stateService; }

    @Override public void run(String... args) { stateService.limpiarDuplicadosPendientes(); }
}