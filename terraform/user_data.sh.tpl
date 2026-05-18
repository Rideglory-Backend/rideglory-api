#!/bin/bash
# user_data.sh.tpl
# Se ejecuta como root al primer arranque de la instancia.
# Los logs se guardan en /var/log/user-data.log

set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "=== Inicio del script de configuración ==="
echo "Fecha: $(date)"

# ─── Actualizar paquetes del sistema ──────────────────────────────────────────
dnf update -y

# ─── Instalar Docker ──────────────────────────────────────────────────────────
# Amazon Linux 2023 usa dnf como gestor de paquetes.
# Docker está disponible en los repositorios oficiales de Amazon.
dnf install -y docker git

# Iniciar y habilitar Docker para que arranque con el sistema
systemctl start docker
systemctl enable docker

# Agregar el usuario 'ec2-user' al grupo docker para no usar sudo
usermod -aG docker ec2-user

# ─── Instalar Docker Compose v2 ───────────────────────────────────────────────
# Descargamos el binario directamente de GitHub releases.
COMPOSE_VERSION="v2.27.0"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

echo "Docker Compose instalado: $(docker compose version)"

# ─── Crear directorio de la aplicación ───────────────────────────────────────
APP_DIR="/opt/rideglory"
mkdir -p $APP_DIR
cd $APP_DIR

# ─── Clonar repositorios ──────────────────────────────────────────────────────
# Nota: Si los repos son privados, necesitas configurar un deploy key o
# usar un token de acceso personal (PAT) de GitHub.
# Para repos públicos, esto funciona directamente.

GITHUB_USER="${github_user}"

git clone "https://github.com/$GITHUB_USER/rideglory-api.git" .

echo "Repositorio clonado correctamente"

# ─── Crear archivos .env de producción ───────────────────────────────────────
# Aquí defines las variables de entorno de cada microservicio.
# En un setup real, estos valores vendrían de AWS Secrets Manager o
# se pasarían de forma segura. Para el MVP los escribimos directamente.

# .env raíz (PostgreSQL compartido)
cat > $APP_DIR/.env << 'ENVEOF'
POSTGRES_USER=rideglory
POSTGRES_PASSWORD=${postgres_password}
ENVEOF

# .env para api-gateway
cat > $APP_DIR/api-gateway/.env.production << 'ENVEOF'
PORT=3000
USERS_MS_PORT=3001
VEHICLES_MS_PORT=3002
EVENTS_MS_PORT=3003
MAINTENANCES_MS_PORT=3004
NOTIFICATIONS_MS_PORT=3005
# Agrega aquí tus claves de Firebase, Mapbox, etc.
ENVEOF

# .env para users-ms (DATABASE_URL lo inyecta docker-compose desde .env raíz)
cat > $APP_DIR/users-ms/.env.production << 'ENVEOF'
# Variables adicionales específicas de users-ms
ENVEOF

# Repite para vehicles-ms, events-ms, maintenances-ms, notifications-ms
# ...

# ─── Levantar los servicios ───────────────────────────────────────────────────
cd $APP_DIR

# Construir imágenes y levantar en background
docker compose up --build -d

echo "=== Servicios levantados ==="
docker compose ps

echo "=== Script completado exitosamente ==="
echo "API disponible en: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"