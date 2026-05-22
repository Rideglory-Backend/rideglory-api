# PO Handoff — aws-backend-deploy

## Goal

Fix two root-cause build errors in the `rideglory-api` monorepo and redeploy to EC2 so the production API responds at `http://13.222.116.14:3000/api/health`.

## Interpretation

This is a pure backend bug-fix deployment. No new features, no database migrations, no Flutter changes. The infrastructure (EC2, Postgres, networking) is healthy and in place. Two files need surgical edits; then the fixes are pushed to `main` and rebuilt on the EC2 instance via SSH.

The dotenv version to use is `^17.4.2` — confirmed consistent with all other five microservices in the monorepo.

## Affected Areas — Current State

| File | Problem |
|------|---------|
| `rideglory-api/notifications-ms/nest-cli.json` | `assets[0].outDir` is `"dist"` → Prisma assets land in `dist/generated/prisma/` but compiled JS resolves `../generated/prisma` relative to `dist/src/` → `Cannot find module '../generated/prisma'` at runtime |
| `rideglory-api/users-ms/package.json` | `dotenv` absent from `dependencies` → pnpm strict mode does not hoist transitive dep → `Cannot find module 'dotenv/config'` during build |
| `rideglory-api/pnpm-lock.yaml` | Must be regenerated after adding `dotenv` to `users-ms` |
| EC2 `13.222.116.14` | `users-ms` and `notifications-ms` in `Restarting`; `vehicles-ms`, `events-ms`, `maintenances-ms`, `api-gateway` not started |

## Acceptance Criteria

1. `notifications-ms/nest-cli.json` → `"outDir": "dist/src"` for Prisma assets.
2. `users-ms/package.json` → `"dotenv": "^17.4.2"` added to `dependencies`.
3. `pnpm-lock.yaml` updated (`pnpm install` run at monorepo root).
4. Both MS compile locally: `nest build` exits 0 in each.
5. Fixes committed and pushed to `main` on `rideglory-api`.
6. SSH into EC2 → `git pull` → `docker compose up --build -d` succeeds.
7. All containers reach `(healthy)` in `docker compose ps`.
8. `curl http://13.222.116.14:3000/api/health` → HTTP 200.

## Regression Guardrails

- After local build of `notifications-ms`, confirm `dist/src/generated/prisma/` exists.
- After deploy, check `docker compose logs users-ms --tail=50` — must show no `Cannot find module` errors.
- `docker compose logs notifications-ms --tail=50` — must show no Prisma import errors.
- `docker compose ps` — `postgres` must remain `healthy` throughout.
- Vehicles, events, and maintenances MS logs must show no new errors.

## Suggested Phase Plan

```json
{
  "needsDesign": false,
  "needsBackend": true,
  "needsFrontend": false,
  "needsDb": false
}
```

Phases in order:
1. **backend** — apply the two file fixes, run `pnpm install` at repo root, verify local builds, push to `main`, SSH-deploy to EC2, health-check.

No other phases required.

## Notes for Orchestrator

- The backend repo is at `/Users/cami/Developer/Personal/rideglory-api` (separate git repo from the Flutter app).
- SSH key: `~/.ssh/rideglory-key.pem`, EC2 user: `ec2-user`, host: `13.222.116.14`.
- The EC2 already has the repo cloned; the backend agent should `git pull` on the instance after pushing to `main`.
- Do NOT run `terraform apply`. Do NOT create new containers or modify `docker-compose.yml`.
- The backend agent IS expected to commit and push to `rideglory-api` — that is the deployment mechanism, not a workflow violation.
- After `docker compose up --build -d`, wait up to 5 minutes for `users-ms` `start_period: 60s` and `api-gateway start_period: 20s` healthchecks to pass before declaring success.
