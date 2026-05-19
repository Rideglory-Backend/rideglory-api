# Paso 6 — Ejecutar el despliegue

> **Prerrequisito:** Los pasos 1–5 deben estar completos: la EC2 está corriendo, los archivos `.env` están en el servidor y el código está clonado en `/opt/rideglory`.

---

## ¿Qué hace este paso?

`scripts/deploy.sh` automatiza el ciclo completo de actualización de los microservicios en la EC2. Internamente ejecuta 6 sub-pasos en orden:

| Sub-paso | Acción |
|----------|--------|
| 1 | Verifica conectividad SSH |
| 2 | Hace `git pull` del código actualizado |
| 3 | Reconstruye las imágenes Docker y reinicia los contenedores (`docker compose up --build -d`) |
| 4 | Corre `prisma migrate deploy` en cada microservicio |
| 5 | Muestra el estado de todos los contenedores |
| 6 | Health check: llama a `GET /api/health` para confirmar que la API responde |

---

## Cómo ejecutarlo

### Primera vez (o después de un `terraform apply`)

Obtén la IP pública del servidor desde el output de Terraform:

```bash
cd terraform/
terraform output public_ip
```

Luego corre el script pasándole esa IP:

```bash
# Desde la raíz del repo rideglory-api
chmod +x scripts/deploy.sh
./scripts/deploy.sh <IP_PUBLICA>
```

Por defecto el script busca tu clave SSH en `~/.ssh/rideglory-key.pem`. Si la tienes en otra ruta, expórtala antes:

```bash
export KEY_PATH=~/.ssh/tu-clave.pem
./scripts/deploy.sh <IP_PUBLICA>
```

### Deploys subsecuentes

Una vez que el servidor ya está configurado, cada vez que quieras desplegar cambios:

```bash
git push origin main          # sube los cambios al repo remoto
./scripts/deploy.sh <IP_PUBLICA>   # el script hace pull y reconstruye
```

---

## Qué esperar en la salida

```
🚀 Desplegando en 54.x.x.x...
→ Verificando conexión SSH...
Conexión OK
→ Actualizando código...
→ Reconstruyendo imágenes y reiniciando servicios...
→ Ejecutando migraciones de base de datos...
   Migrando users-ms...
   Migrando vehicles-ms...
   Migrando events-ms...
   Migrando maintenances-ms...
   Migrando notifications-ms...
→ Estado de los servicios:
NAME             STATUS
api-gateway      running
users-ms         running
vehicles-ms      running
events-ms        running
maintenances-ms  running
notifications-ms running
postgres         running
→ Verificando API...
✅ Despliegue exitoso — API disponible en http://54.x.x.x:3000/api
```

---

## Errores comunes

### `⚠️ La API no respondió al health check`

El contenedor puede tardar unos segundos en estar listo. Conecta al servidor y revisa los logs:

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@<IP_PUBLICA> \
  'cd /opt/rideglory && docker compose logs --tail=50'
```

Causas frecuentes:
- Falta una variable de entorno en algún `.env` (el servicio no arranca).
- Una migración de Prisma falló (verifica los logs del microservicio afectado).
- El puerto 3000 no está abierto en el Security Group (revisa Terraform).

### `Permission denied (publickey)`

La clave SSH no coincide con el Key Pair creado en AWS. Verifica que `KEY_PATH` apunta al archivo `.pem` correcto y que tiene permisos `600`:

```bash
chmod 600 ~/.ssh/rideglory-key.pem
```

### Contenedor en estado `Exited`

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@<IP_PUBLICA> \
  'cd /opt/rideglory && docker compose logs <nombre-del-servicio>'
```

---

## Verificación manual post-deploy

Desde tu máquina local, confirma que el gateway responde:

```bash
curl http://<IP_PUBLICA>:3000/api/health
# Esperado: { "status": "ok" }
```

Si quieres probar un endpoint protegido, obtén un token de Firebase y:

```bash
curl -H "Authorization: Bearer <token>" \
     http://<IP_PUBLICA>:3000/api/home
```
