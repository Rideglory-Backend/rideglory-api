#!/bin/bash
# user_data.sh.tpl
# Se ejecuta como root al PRIMER arranque de la instancia EC2.
# Terraform inyecta: ${github_user}, ${github_token}, ${postgres_password}, ${project_name}.
# Logs disponibles en: sudo cat /var/log/user-data.log

set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "=== Inicio del script de configuración ==="
echo "Fecha: $(date)"

# ─── Actualizar paquetes del sistema ──────────────────────────────────────────
dnf update -y

# ─── Instalar Docker y Git ────────────────────────────────────────────────────
# Amazon Linux 2023 usa dnf. Docker está disponible en sus repos oficiales.
dnf install -y docker git

# Iniciar Docker y habilitarlo para que arranque automáticamente con el sistema
systemctl start docker
systemctl enable docker

# Agregar ec2-user al grupo docker para no necesitar sudo
usermod -aG docker ec2-user

# ─── Instalar Docker Compose v2 ───────────────────────────────────────────────
COMPOSE_VERSION="v2.27.0"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"

# ─── Crear directorio de la aplicación ───────────────────────────────────────
APP_DIR="/opt/${project_name}"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# ─── Clonar repositorio con submodules ───────────────────────────────────────
# --recurse-submodules clona api-gateway, vehicles-ms, events-ms, users-ms,
# maintenances-ms, rideglory-common-lib y rideglory-contracts en un solo paso.
git clone \
  --recurse-submodules \
  "https://github.com/Rideglory-Backend/rideglory-api.git" .
echo "Repositorio y submodulos clonados"

# ─── Crear script de init de bases de datos ──────────────────────────────────
mkdir -p "$APP_DIR/scripts"
cat > "$APP_DIR/scripts/init-db.sql" << 'SQLEOF'
CREATE DATABASE rideglory_users;
CREATE DATABASE rideglory_vehicles;
CREATE DATABASE rideglory_events;
CREATE DATABASE rideglory_maintenances;
CREATE DATABASE rideglory_notifications;
SQLEOF

# ─── Crear archivos de variables de entorno ───────────────────────────────────
# .env raíz — variables compartidas por docker-compose.yml
cat > "$APP_DIR/.env" << ENVEOF
POSTGRES_USER=rideglory
POSTGRES_PASSWORD=${postgres_password}
ENVEOF

# api-gateway
cat > "$APP_DIR/api-gateway/.env.production" << ENVEOF
PORT=3000
USERS_MS_PORT=3001
VEHICLES_MS_PORT=3002
EVENTS_MS_PORT=3003
MAINTENANCES_MS_PORT=3004
NOTIFICATIONS_MS_PORT=3005
FIREBASE_PROJECT_ID=${firebase_project_id}
FIREBASE_SERVICE_ACCOUNT_JSON=${firebase_service_account_json}
GOOGLE_PLACES_API_KEY=${google_places_api_key}
MAPBOX_ACCESS_TOKEN=${mapbox_access_token}
ENVEOF

# users-ms
cat > "$APP_DIR/users-ms/.env.production" << ENVEOF
PORT=3001
ENVEOF

# vehicles-ms
cat > "$APP_DIR/vehicles-ms/.env.production" << ENVEOF
PORT=3002
ENVEOF

# events-ms
cat > "$APP_DIR/events-ms/.env.production" << ENVEOF
PORT=3003
ENVEOF

# maintenances-ms
cat > "$APP_DIR/maintenances-ms/.env.production" << ENVEOF
PORT=3004
ENVEOF

# notifications-ms
cat > "$APP_DIR/notifications-ms/.env.production" << ENVEOF
PORT=3005
FIREBASE_PROJECT_ID=${firebase_project_id}
FIREBASE_SERVICE_ACCOUNT_JSON=${firebase_service_account_json}
ENVEOF

echo "Archivos .env creados"

# ─── Levantar los servicios ───────────────────────────────────────────────────
cd "$APP_DIR"

# Construir todas las imágenes y levantar en background
docker compose up --build -d

echo "Esperando a que los servicios estén healthy (máx 5 min)..."
WAIT=0
until [ "$(docker compose ps --format json | grep -c '"Health":"healthy"')" -ge 7 ] || [ "$WAIT" -ge 300 ]; do
  sleep 10
  WAIT=$((WAIT + 10))
done

echo "=== Estado de los servicios ==="
docker compose ps

echo "=== Script completado exitosamente ==="
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "API disponible en: http://$PUBLIC_IP:3000/api"
