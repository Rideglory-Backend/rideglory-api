-- Este script crea todas las bases de datos al primer arranque de PostgreSQL.
-- Docker ejecuta automáticamente los scripts en /docker-entrypoint-initdb.d/
-- SOLO en el primer arranque (cuando el volumen está vacío).

CREATE DATABASE rideglory_users;
CREATE DATABASE rideglory_vehicles;
CREATE DATABASE rideglory_events;
CREATE DATABASE rideglory_maintenances;
CREATE DATABASE rideglory_notifications;
