# Architect Handoff — aws-backend-deploy

## 1. Verification of the two known fixes

### Fix 1 — `notifications-ms` Prisma asset outDir

**Current file** `/Users/cami/Developer/Personal/rideglory-api/notifications-ms/nest-cli.json`:

```json
{
  "compilerOptions": {
    "deleteOutDir": true,
    "assets": [
      { "include": "generated/prisma/**/*", "outDir": "dist" }
    ]
  }
}
```

**Why it breaks at runtime:**

- `prisma/schema.prisma` declares `output = "../src/generated/prisma"` → Prisma client is generated to `src/generated/prisma/`.
- `prisma.config.ts` sits at the project root, not inside `src/`. TypeScript therefore infers `rootDir = "."` and emits compiled JS preserving the `src/` prefix → `dist/src/notifications/notifications.service.js`.
- That compiled file imports `'../generated/prisma'`, which Node resolves to **`dist/src/generated/prisma/`**.
- But Nest's asset copier obeys `outDir: "dist"` → copies the generator output to **`dist/generated/prisma/`** (no `src/` prefix).
- Mismatch → `Cannot find module '../generated/prisma'` on container start.

**Fix:** change `"outDir": "dist"` → `"outDir": "dist/src"`. Verified: every other MS that uses a custom Prisma output (`events-ms`, `maintenances-ms`, `users-ms`, `vehicles-ms`) already uses `"dist/src"`. `notifications-ms` is the only outlier.

### Fix 2 — `users-ms` missing `dotenv` dependency

**Current file** `/Users/cami/Developer/Personal/rideglory-api/users-ms/package.json` `dependencies`:
- has `@nestjs/*`, `@prisma/*`, `joi`, `pg`, `prisma`, `reflect-metadata`, `rxjs`, `class-transformer`, `class-validator`, `@rideglory/*` local file deps.
- **does NOT have `dotenv`.**

**Verified:**
- `src/main.ts` line 1: `import 'dotenv/config';` (would fail at module resolution).
- `prisma.config.ts` line 1: `import "dotenv/config";` (would fail when running `prisma migrate deploy` in the runtime CMD).
- All other 5 MS (`api-gateway`, `events-ms`, `maintenances-ms`, `notifications-ms`, `vehicles-ms`) pin `"dotenv": "^17.4.2"` in `dependencies` and each has its own `pnpm-lock.yaml` reflecting that.
- `users-ms/pnpm-lock.yaml` currently has only 3 occurrences of `dotenv` (transitive references). `vehicles-ms/pnpm-lock.yaml` has 6 (direct + transitive).

**Fix:** add `"dotenv": "^17.4.2"` to `users-ms/package.json` dependencies (alphabetical order suggests inserting between `class-validator` and `joi`), then run `pnpm install` **inside `users-ms/`** (each MS has its own lockfile — there is no monorepo workspace file).

## 2. Additional similar issues check — NONE FOUND

Audited every microservice for the same two patterns:

| MS | Prisma custom output? | `nest-cli.json` outDir | `dotenv` in deps? | `import 'dotenv/config'` in main.ts? | Verdict |
|---|---|---|---|---|---|
| `api-gateway` | no (no Prisma) | n/a | yes ^17.4.2 | yes | OK |
| `events-ms` | yes `../src/generated/prisma` | `dist/src` | yes ^17.4.2 | yes | OK |
| `maintenances-ms` | yes `../src/generated/prisma` | `dist/src` | yes ^17.4.2 | yes | OK |
| `notifications-ms` | yes `../src/generated/prisma` | **`dist` BROKEN** | yes ^17.4.2 | yes | FIX 1 |
| `users-ms` | yes `../src/generated/prisma` | `dist/src` | **MISSING BROKEN** | yes | FIX 2 |
| `vehicles-ms` | yes `../src/generated/prisma` | `dist/src` | yes ^17.4.2 | yes | OK |

No other surprises. Two surgical edits, nothing else.

## 3. Change map

| File | Action | Change | Risk |
|---|---|---|---|
| `rideglory-api/notifications-ms/nest-cli.json` | modify | `"outDir": "dist"` → `"outDir": "dist/src"` (Prisma assets entry) | low — aligns with the other 4 MS |
| `rideglory-api/users-ms/package.json` | modify | Add `"dotenv": "^17.4.2"` to `dependencies` | low — same version as other 5 MS |
| `rideglory-api/users-ms/pnpm-lock.yaml` | regenerate | Result of `pnpm install` inside `users-ms/` | low — additive; no API surface change |

No Dockerfile, docker-compose, terraform, healthcheck, or schema changes required.

## 4. Implementation order (Backend agent)

### Step A — Apply file edits locally

1. Edit `/Users/cami/Developer/Personal/rideglory-api/notifications-ms/nest-cli.json` → change `"outDir": "dist"` to `"outDir": "dist/src"`.
2. Edit `/Users/cami/Developer/Personal/rideglory-api/users-ms/package.json` → add `"dotenv": "^17.4.2",` inside `dependencies` (suggested position: between `"class-validator"` and `"joi"` to keep alphabetical ordering).

### Step B — Update lockfile

```bash
cd /Users/cami/Developer/Personal/rideglory-api/users-ms
pnpm install
```

This regenerates `users-ms/pnpm-lock.yaml` with the dotenv entry. Do NOT pass `--frozen-lockfile`.

### Step C — Verify local builds

```bash
# notifications-ms
cd /Users/cami/Developer/Personal/rideglory-api/notifications-ms
DATABASE_URL=postgresql://x:x@localhost/x pnpm exec prisma generate
pnpm build
test -d dist/src/generated/prisma && echo "OK: prisma assets at dist/src/generated/prisma" || echo "FAIL"

# users-ms
cd /Users/cami/Developer/Personal/rideglory-api/users-ms
DATABASE_URL=postgresql://x:x@localhost/x pnpm exec prisma generate
pnpm build
test -f dist/src/main.js && echo "OK: users-ms build produced dist/src/main.js" || echo "FAIL"
```

Both must exit 0.

### Step D — Commit and push to `rideglory-api` main

```bash
cd /Users/cami/Developer/Personal/rideglory-api
git status
git add notifications-ms/nest-cli.json users-ms/package.json users-ms/pnpm-lock.yaml
git commit -m "fix(deploy): notifications-ms prisma asset outDir + users-ms dotenv dep

- notifications-ms: align Prisma asset outDir with TS rootDir (dist/src)
- users-ms: add missing dotenv dep so import 'dotenv/config' resolves under pnpm strict mode

Co-Authored-By: Claude Sonnet 4.7 <noreply@anthropic.com>"
git push origin main
```

Backend agent IS authorised to commit and push to `rideglory-api` — this is the deployment mechanism for this run, NOT a workflow violation. (HARD RULE #1 applies to the Flutter repo only.)

### Step E — Deploy to EC2 (memory-safe rebuild)

See section 5 below for the exact sequence.

### Step F — Verify

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 "cd /opt/rideglory && docker compose ps"
curl -v http://13.222.116.14:3000/api/health
```

Expect HTTP 200 and all 7 containers `(healthy)`.

## 5. EC2 deployment strategy (1GB RAM, OOM-safe)

The EC2 is a t3.micro (1GB RAM). Per `docker-compose.yml`:
- postgres: 200m
- api-gateway: 128m
- each MS (5): 80m → 400m
- **total runtime steady-state: ~728m** — fits, but rebuilding multiple Node images simultaneously will OOM.

`node:22-alpine` builder stages each load ~150-300MB during `pnpm install` + `nest build`. Running parallel builds will exhaust RAM. Build **serially**, one service at a time.

### Recommended sequence on EC2

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14
cd /opt/rideglory

# 1. Stop the two broken services so they stop chewing CPU in restart loops.
#    Leave postgres up.
docker compose stop api-gateway notifications-ms users-ms vehicles-ms events-ms maintenances-ms || true

# 2. Pull latest code
sudo chown -R ec2-user:ec2-user /opt/rideglory
git config --global --add safe.directory /opt/rideglory
git fetch origin
git pull origin main
git submodule update --remote --merge

# 3. Free build cache + dangling images BEFORE rebuilding (reclaim disk + RAM headroom)
docker system prune -f

# 4. Rebuild ONLY the two changed services, SERIALLY, with no parallel jobs.
#    --pull keeps the base node:22-alpine fresh; remove if disk is tight.
DOCKER_BUILDKIT=1 docker compose build --no-cache notifications-ms
DOCKER_BUILDKIT=1 docker compose build --no-cache users-ms

# 5. Bring the stack up in dependency order. compose handles depends_on,
#    but starting users-ms first lets healthcheck pass before downstream MS start.
docker compose up -d postgres
docker compose up -d users-ms
# wait ~70s for users-ms start_period (60s) + first healthcheck
sleep 75
docker compose ps users-ms
# then the rest
docker compose up -d vehicles-ms events-ms maintenances-ms notifications-ms
sleep 70
docker compose up -d api-gateway
sleep 30

# 6. Verify
docker compose ps
docker compose logs --tail=40 users-ms
docker compose logs --tail=40 notifications-ms
docker compose logs --tail=20 api-gateway
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/api/health
```

### Why NOT `docker compose up --build -d` in one shot

That command builds **all 6 service images in parallel** by default. On 1GB RAM with `node:22-alpine` + `pnpm install` + `prisma generate` + `nest build` × 6, the kernel will OOM-kill the docker daemon or random builds will fail mid-way. The sequential `build` calls above keep peak RSS under ~400MB.

### Fallback if `prisma generate` step OOMs during build

```bash
# Build with explicit memory cap for node during the build stage
NODE_OPTIONS="--max-old-space-size=400" docker compose build --no-cache notifications-ms
```

If a single build still OOMs, stop postgres temporarily during that one build, then restart it:

```bash
docker compose stop postgres
docker compose build --no-cache <ms>
docker compose start postgres
```

## 6. Verification checklist (for QA)

After Step F:

- [ ] `docker compose ps` → 7 rows, all `(healthy)`.
- [ ] `docker compose logs users-ms --tail=50` → no `Cannot find module 'dotenv/config'`.
- [ ] `docker compose logs notifications-ms --tail=50` → no `Cannot find module '../generated/prisma'`.
- [ ] `docker compose logs postgres --tail=20` → no restart events during deploy window.
- [ ] `curl -s -o /dev/null -w "%{http_code}" http://13.222.116.14:3000/api/health` → `200`.
- [ ] `docker compose exec -T users-ms node -e "require('dotenv/config'); console.log('ok')"` → `ok`.
- [ ] `docker compose exec -T notifications-ms node -e "require('./dist/src/generated/prisma'); console.log('ok')"` → `ok`.

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| `pnpm install` in `users-ms` pulls in a newer `dotenv` than other MS | Pin to `^17.4.2` (same caret range). Lockfile will resolve to a concrete version; acceptable. |
| EC2 OOM during parallel rebuild | Use the serial `docker compose build` sequence in §5. |
| `git pull` conflicts on EC2 | EC2 should have clean tree (deployment-only); if not, `git reset --hard origin/main` is acceptable (it's a deployment target, not a working tree). Document this only if conflict actually occurs — do not pre-emptively reset. |
| Postgres restarts and loses connections during deploy | Keep postgres running throughout (`docker compose stop` excludes it in §5). |
| `prisma migrate deploy` fails because schema is already current | The runtime `CMD` uses `prisma migrate deploy` which is idempotent — already-applied migrations are a no-op. |
| Healthcheck `start_period: 60s` for MS / `20s` for gateway → may look "unhealthy" briefly | Wait the full periods between `up -d` calls (sleeps in §5). |

## 8. What the Backend agent must NOT touch

- `docker-compose.yml`
- Any Dockerfile
- Any `healthcheck.js`
- Postgres config or memory limits
- Any `.env.production` file
- Terraform (`/Users/cami/Developer/Personal/rideglory-api/terraform/`)
- Any file in any **other** MS
- The Flutter repo (`/Users/cami/Developer/Personal/Rideglory/`)
- `docs/PRD.md`, `workflow/state.json`, or any iteration tracking file in the Flutter repo
