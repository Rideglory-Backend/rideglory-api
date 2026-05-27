# 07 — Operaciones en producción

Referencia rápida para diagnosticar y operar el servidor EC2 en cualquier momento.

**App dir:** `/opt/rideglory`  
**User:** `ec2-user`

---

## 1. Conectarse al servidor

```bash
# Obtener la IP actual desde Terraform
terraform -chdir=terraform output public_ip

# SSH
ssh -i ~/.ssh/rideglory-key.pem ec2-user@<PUBLIC_IP>
```

---

## 2. Estado general de los contenedores

```bash
cd /opt/rideglory

# Tabla de estado (Running / healthy / unhealthy)
docker compose ps

# Versión compacta
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Solo los que NO están healthy
docker ps --filter "health=unhealthy" --filter "health=starting"
```

Contenedores esperados:

| Nombre | Puerto interno |
|---|---|
| rideglory-postgres | 5432 |
| rideglory-api-gateway | 3000 |
| rideglory-users-ms | 3001 |
| rideglory-vehicles-ms | 3002 |
| rideglory-events-ms | 3003 |
| rideglory-maintenances-ms | 3004 |
| rideglory-notifications-ms | 3005 |

---

## 3. Logs

```bash
cd /opt/rideglory

# Un servicio — últimas 100 líneas y en vivo
docker compose logs -f --tail=100 api-gateway
docker compose logs -f --tail=100 users-ms
docker compose logs -f --tail=100 vehicles-ms
docker compose logs -f --tail=100 events-ms
docker compose logs -f --tail=100 maintenances-ms
docker compose logs -f --tail=100 notifications-ms
docker compose logs -f --tail=100 postgres

# Todos los servicios a la vez
docker compose logs -f --tail=50

# Log del arranque inicial de la instancia (user_data.sh)
sudo cat /var/log/user-data.log

# Últimas líneas del mismo log
sudo tail -100 /var/log/user-data.log
```

---

## 4. Recursos del sistema

```bash
# RAM libre y swap (crítico en t2.micro)
free -h

# Uso de CPU y memoria por proceso en tiempo real
top        # o 'htop' si está instalado

# Uso de CPU + RAM por contenedor en tiempo real
docker stats

# Snapshot rápido de todos los contenedores
docker stats --no-stream

# Disco
df -h
```

---

## 5. Base de datos (PostgreSQL)

```bash
# Shell de Postgres
docker exec -it rideglory-postgres psql -U rideglory -d postgres

# Listar bases de datos
docker exec -it rideglory-postgres psql -U rideglory -c "\l"

# Conectarse a una BD específica
docker exec -it rideglory-postgres psql -U rideglory -d rideglory_users
docker exec -it rideglory-postgres psql -U rideglory -d rideglory_events

# Queries SQL lentas (≥ 1000 ms — el umbral configurado en docker-compose)
docker compose logs postgres | grep "duration:"

# Ver conexiones activas
docker exec -it rideglory-postgres psql -U rideglory -c \
  "SELECT pid, usename, datname, state, query_start, left(query,80) FROM pg_stat_activity WHERE state != 'idle';"
```

---

## 6. Reiniciar servicios

```bash
cd /opt/rideglory

# Reiniciar un servicio sin bajarlo todo
docker compose restart api-gateway
docker compose restart users-ms

# Bajar y volver a levantar todo
docker compose down && docker compose up -d

# Forzar recreación de un contenedor (sin rebuild)
docker compose up -d --force-recreate api-gateway
```

---

## 7. Actualizar el código en producción

```bash
cd /opt/rideglory

# Traer últimos cambios
git pull --recurse-submodules

# Rebuild + redeploy de un servicio específico
docker compose build --no-cache api-gateway
docker compose up -d --force-recreate api-gateway

# Rebuild de todos y redeploy (más lento — monitorear RAM)
docker compose build --no-cache
docker compose up -d
```

---

## 8. Limpiar espacio en disco

```bash
# Ver cuánto ocupa Docker
docker system df

# Eliminar imágenes y capas sin usar (NO borra volúmenes)
docker system prune -f

# También eliminar imágenes no usadas por ningún contenedor
docker image prune -a -f

# Limpiar caché de build
docker builder prune -f
```

---

## 9. Healthchecks manuales

```bash
# API Gateway (desde la EC2)
curl -s http://localhost:3000/api | head -c 200

# Desde tu máquina local (reemplaza con la IP pública)
curl -s http://<PUBLIC_IP>:3000/api

# Inspeccionar el healthcheck de un contenedor
docker inspect --format='{{json .State.Health}}' rideglory-api-gateway | python3 -m json.tool
```

---

## 10. Swap

```bash
# Ver estado del swap (debe mostrar /swapfile 2G)
swapon --show

# Uso actual
free -h

# Si el swap no está montado (raro, ocurre tras un reboot sin fstab)
sudo swapon /swapfile
```
