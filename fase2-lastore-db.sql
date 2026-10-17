USE db_lastore_clientes;
CREATE TABLE IF NOT EXISTS cliente (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    dni_ruc VARCHAR(15) NOT NULL UNIQUE,
    nombres VARCHAR(100) NOT NULL,
    telefono VARCHAR(20),
    correo VARCHAR(100)
);

USE db_lastore_reparaciones;
CREATE TABLE IF NOT EXISTS ticket (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cliente_id BIGINT NOT NULL,
    tipo_equipo VARCHAR(50) NOT NULL,
    marca_modelo VARCHAR(100) NOT NULL,
    falla_reportada VARCHAR(255) NOT NULL,
    estado_cotizacion VARCHAR(50) NOT NULL DEFAULT 'PENDIENTE_ENVIO',
    monto_total DECIMAL(10,2) NOT NULL DEFAULT 0.00
);

USE db_lastore_pagos;
CREATE TABLE IF NOT EXISTS pago (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    ticket_id BIGINT NOT NULL,
    monto_pago DECIMAL(10,2) NOT NULL,
    estado_pago VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE'
);