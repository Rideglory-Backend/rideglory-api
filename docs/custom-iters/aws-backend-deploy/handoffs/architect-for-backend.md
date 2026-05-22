# Architect → Backend Handoff (slim)

## Two surgical fixes, then deploy.

### FIX 1 — `notifications-ms/nest-cli.json`

File: `/Users/cami/Developer/Personal/rideglory-api/notifications-ms/nest-cli.json`

Change `"outDir": "dist"` → `"outDir": "dist/src"` (only that one string, inside the `assets` array).

### FIX 2 — `users-ms/package.json`

File: `/Users/cami/Developer/Personal/rideglory-api/users-ms/package.json`

Add to `dependencies` (alphabetical, between `class-validator` and `joi`):

```json
"dotenv": "^17.4.2",
```

### Commands — run in order

```bash
# 1. Regenerate users-ms lockfile (each MS has its own; there is NO monorepo workspace)
cd /Users/cami/Developer/Personal/rideglory-api/users-ms
pnpm install   # do NOT pass --frozen-lockfile

# 2. Verify both local builds compile
cd /Users/cami/Developer/Personal/rideglory-api/notifications-ms
DATABASE_URL=postgresql://x:x@localhost/x pnpm exec prisma generate
pnpm build
test -d dist/src/generated/prisma && echo "notifications OK" || (echo "FAIL"; exit 1)

cd /Users/cami/Developer/Personal/rideglory-api/users-ms
DATABASE_URL=postgresql://x:x@localhost/x pnpm exec prisma generate
pnpm build
test -f dist/src/main.js && echo "users OK" || (echo "FAIL"; exit 1)

# 3. Commit + push to rideglory-api main (allowed for this run)
cd /Users/cami/Developer/Personal/rideglory-api
git add notifications-ms/nest-cli.json users-ms/package.json users-ms/pnpm-lock.yaml
git commit -m "fix(deploy): notifications-ms prisma asset outDir + users-ms dotenv dep

- notifications-ms: align Prisma asset outDir with TS rootDir (dist/src)
- users-ms: add missing dotenv dep so import 'dotenv/config' resolves under pnpm strict mode

Co-Authored-By: Claude Sonnet 4.7 <noreply@anthropic.com>"
git push origin main

# 4. SSH + deploy (SERIAL builds — 1GB RAM, parallel builds will OOM)
ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 << 'EOF'
set -e
cd /opt/rideglory
sudo chown -R ec2-user:ec2-user /opt/rideglory
git config --global --add safe.directory /opt/rideglory
docker compose stop api-gateway notifications-ms users-ms vehicles-ms events-ms maintenances-ms || true
git fetch origin
git pull origin main
git submodule update --remote --merge
docker system prune -f
DOCKER_BUILDKIT=1 docker compose build --no-cache notifications-ms
DOCKER_BUILDKIT=1 docker compose build --no-cache users-ms
docker compose up -d postgres
docker compose up -d users-ms
sleep 75
docker compose ps users-ms
docker compose up -d vehicles-ms events-ms maintenances-ms notifications-ms
sleep 70
docker compose up -d api-gateway
sleep 30
docker compose ps
docker compose logs --tail=30 users-ms
docker compose logs --tail=30 notifications-ms
docker compose logs --tail=20 api-gateway
EOF

# 5. Health check from outside
curl -v http://13.222.116.14:3000/api/health
# Expect: HTTP/1.1 200
```

### Do NOT touch

- `docker-compose.yml`, any Dockerfile, any `healthcheck.js`, any `.env.production`
- Any file in other MS (`api-gateway`, `events-ms`, `maintenances-ms`, `vehicles-ms`)
- Terraform, postgres config, healthcheck timings
- The Flutter repo

### If something OOMs on EC2

Stop postgres for one build, then restart:

```bash
docker compose stop postgres
docker compose build --no-cache <failing-service>
docker compose start postgres
```

Or cap node memory during the build:

```bash
NODE_OPTIONS="--max-old-space-size=400" docker compose build --no-cache <service>
```

### Success criteria

- `docker compose ps` shows 7 rows, all `(healthy)` after Step 4.
- `curl http://13.222.116.14:3000/api/health` → HTTP 200.
- `users-ms` logs contain NO `Cannot find module 'dotenv/config'`.
- `notifications-ms` logs contain NO `Cannot find module '../generated/prisma'`.

### Reference

Full rationale + risk analysis: `docs/custom-iters/aws-backend-deploy/handoffs/architect.md`.
