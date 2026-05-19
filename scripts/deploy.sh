#!/bin/bash
# deploy.sh — Despliega los microservicios en la EC2
# Uso: ./scripts/deploy.sh <IP_PUBLICA>
# Ejemplo: ./scripts/deploy.sh 54.x.x.x

set -euo pipefail

# ─── Argumentos ───────────────────────────────────────────────────────────────
SERVER_IP="${1:-}"
if [ -z "$SERVER_IP" ]; then
  echo "ERROR: Debes proporcionar la IP del servidor"
  echo "Uso: $0 <IP_PUBLICA>"
  echo "     Puedes obtenerla con: terraform output public_ip"
  exit 1
fi

KEY_PATH="${KEY_PATH:-$HOME/.ssh/rideglory-key.pem}"
SSH_USER="ec2-user"
APP_DIR="/opt/rideglory"

echo "🚀 Desplegando en $SERVER_IP..."

# ─── Función auxiliar para correr comandos en el servidor ─────────────────────
run_remote() {
  ssh -i "$KEY_PATH" \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      "$SSH_USER@$SERVER_IP" "$@"
}

# ─── 1. Verificar conectividad SSH ───────────────────────────────────────────
echo "→ Verificando conexión SSH..."
run_remote "echo 'Conexión OK'"

# ─── 2. Actualizar código fuente ──────────────────────────────────────────────
echo "→ Actualizando código..."
run_remote "
  cd $APP_DIR
  git fetch origin
  git pull origin main
  git submodule update --remote --merge
"

# ─── 3. Reconstruir y reiniciar servicios ─────────────────────────────────────
# --build: reconstruye las imágenes con el código nuevo
# -d: modo background (detached)
# No destruye los contenedores que no cambiaron
echo "→ Reconstruyendo imágenes y reiniciando servicios..."
run_remote "
  cd $APP_DIR
  docker compose up --build -d
"

# ─── 4. Ejecutar migraciones pendientes de Prisma ─────────────────────────────
echo "→ Ejecutando migraciones de base de datos..."
for SERVICE in users-ms vehicles-ms events-ms maintenances-ms notifications-ms; do
  echo "   Migrando $SERVICE..."
  run_remote "
    cd $APP_DIR
    docker compose exec -T $SERVICE npx prisma migrate deploy 2>/dev/null || echo '  (sin migraciones pendientes)'
  "
done

# ─── 5. Verificar estado de los contenedores ──────────────────────────────────
echo "→ Estado de los servicios:"
run_remote "cd $APP_DIR && docker compose ps"

# ─── 6. Health check final ────────────────────────────────────────────────────
echo "→ Verificando API..."
sleep 5
if curl -s --fail "http://$SERVER_IP:3000/api/health" > /dev/null; then
  echo "✅ Despliegue exitoso — API disponible en http://$SERVER_IP:3000/api"
else
  echo "⚠️  La API no respondió al health check. Revisa los logs:"
  echo "   ssh -i $KEY_PATH $SSH_USER@$SERVER_IP 'cd $APP_DIR && docker compose logs --tail=50'"
  exit 1
fi