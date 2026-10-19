package com.lastore.pagos.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.lastore.pagos.model.Pago;

public interface PagoRepository extends JpaRepository<Pago, Long> {
    Optional<Pago> findByTicketIdAndEstadoPago(Long ticketId, String estadoPago);
    List<Pago> findByTicketIdOrderByIdAsc(Long ticketId);
}