package com.lastore.pagos.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import com.lastore.pagos.model.Pago;

public interface PagoRepository extends JpaRepository<Pago, Long> {
    Optional<Pago> findByTicketIdAndEstadoPago(Long ticketId, String estadoPago);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    List<Pago> findByTicketIdOrderByIdAsc(Long ticketId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from Pago p where p.id = :id")
    Optional<Pago> findForUpdateById(@Param("id") Long id);
}
