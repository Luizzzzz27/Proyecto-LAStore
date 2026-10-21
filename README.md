# 💻 LA Store Service-Commerce

Plataforma distribuida basada en **Microservicios** y **Mensajería Asíncrona** para la gestión integral de servicio técnico, cotizaciones y tesorería. 
Proyecto final desarrollado para el curso de **Experiencias Formativas en Situaciones Reales de Trabajo V (EFSRT V)** - Cibertec 2026.

## 🚀 Stack Tecnológico
* **Backend:** Java 17, Spring Boot 3, Spring Cloud (Netflix Eureka, API Gateway), Spring Data JPA
* **Frontend:** Angular 18, Bootstrap 5, jsPDF, SheetJS (xlsx)
* **Mensajería & Infraestructura:** RabbitMQ (AMQP) sobre Docker
* **Base de Datos:** MySQL 8.0 (Producción), H2 Database (Testing)
* **DevOps & Calidad:** GitHub Actions (CI Pipeline), JUnit 5

## ⚙️ Arquitectura del Sistema
El ecosistema está compuesto por 6 microservicios independientes:
1. `ms-eureka-server` (Puerto 8761): Servidor de registro y descubrimiento.
2. `ms-api-gateway` (Puerto 8080): Punto único de entrada (Enrutamiento dinámico y CORS).
3. `ms-auth` (Puerto 8081): Autenticación de usuarios (JWT y BCrypt).
4. `ms-clientes` (Puerto 8082): Directorio comercial y validación por DNI/RUC.
5. `ms-reparaciones` (Puerto 8083): Máquina de estados de tickets técnicos. *(Productor de Eventos)*
6. `ms-pagos` (Puerto 8084): Gestión de adelantos, saldos y medios de pago. *(Consumidor de Eventos)*

## ✨ Características Destacadas
* **Event-Driven Architecture:** Desacoplamiento total entre Taller y Caja utilizando un `Direct Exchange` y 3 colas durables en RabbitMQ.
* **Control Financiero:** Soporte matemático para pagos parciales (adelantos) y conciliación de múltiples medios de pago (Yape/Plin, Efectivo, Tarjeta).
* **Auditoría Intacta:** Implementación de *Eliminación Lógica* para garantizar la trazabilidad de operaciones anuladas, cumpliendo normativas de protección de datos.
* **Reportes Gerenciales:** Exportación instantánea de vistas filtradas a **PDF** y **Excel** procesadas desde el lado del cliente (Angular).
* **Integración Continua:** Pipeline en GitHub Actions que ejecuta pruebas unitarias automatizadas validando las reglas de negocio ante cada commit.

## 👨‍💻 Autor
* **Luis Angel Gonzales Arguedas**

