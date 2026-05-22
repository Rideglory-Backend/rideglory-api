# PRD Normalized — AWS Backend Deploy

## §1 Background

The Rideglory backend is a NestJS monorepo at `/Users/cami/Developer/Personal/rideglory-api` composed of an API Gateway and five microservices (users, vehicles, events, maintenances, notifications). The infrastructure (EC2 t3.micro at `13.222.116.14`, Postgres, Docker Compose) is already provisioned and registered in `terraform/terraform.tfstate`. The services were deployed previously but the API is currently down due to two build-time errors introduced at some point:

1. **notifications-ms**: `nest-cli.json` copies Prisma client assets to `dist/generated/prisma/` but the compiled JS imports them from `dist/src/generated/prisma/` — a path mismatch that causes `Cannot find module '../generated/prisma'` at runtime.
2. **users-ms**: `main.ts` uses `import 'dotenv/config'` but `dotenv` is not listed as a direct dependency in `users-ms/package.json`. pnpm strict mode does not expose transitive dependencies, so the build fails with `Cannot find module 'dotenv/config'`.

Because `users-ms` is unhealthy, all downstream microservices (vehicles, events, maintenances) and the api-gateway fail to start due to `depends_on: service_healthy` conditions in `docker-compose.yml`.

## §2 Goal

Fix two root-cause build errors in the backend monorepo, redeploy to the existing EC2 instance, and restore `http://13.222.116.14:3000/api/health` to HTTP 200.

## §3 Improvement Type and Severity

- **Type**: Bug fix / production incident remediation
- **Severity**: High — the production API is completely down; the Flutter app cannot authenticate or perform any network operations

## §4 Affected Areas

| File | Current broken state |
|------|---------------------|
| `/Users/cami/Developer/Personal/rideglory-api/notifications-ms/nest-cli.json` | `assets[0].outDir` is `"dist"` — should be `"dist/src"` |
| `/Users/cami/Developer/Personal/rideglory-api/users-ms/package.json` | `dotenv` missing from `dependencies` |
| `pnpm-lock.yaml` (repo root) | Will need update after adding `dotenv` to users-ms |
| EC2 instance `13.222.116.14` | Containers `users-ms` and `notifications-ms` in Restarting state; other MS and api-gateway not started |

## §5 Out of Scope

- Creating new EC2 infrastructure or running `terraform apply`
- Changes to any other microservice except `users-ms` and `notifications-ms`
- Changes to `docker-compose.yml` or Dockerfiles
- Flutter app changes
- Modifying healthcheck logic, memory limits, or Postgres configuration

## §6 Acceptance Criteria

1. `notifications-ms/nest-cli.json` has `"outDir": "dist/src"` for the Prisma assets entry.
2. `users-ms/package.json` lists `dotenv` (^17.x or compatible) in `dependencies`.
3. `pnpm-lock.yaml` is updated to reflect the new dependency.
4. Both microservices compile locally without errors (`nest build` exits 0).
5. The fixes are committed and pushed to `main` on `rideglory-api`.
6. On EC2: `docker compose pull && docker compose up --build -d` completes successfully.
7. All six containers (`postgres`, `users-ms`, `vehicles-ms`, `events-ms`, `maintenances-ms`, `notifications-ms`, `api-gateway`) reach `healthy` status.
8. `curl http://13.222.116.14:3000/api/health` returns HTTP 200.

## §7 Regression Guardrails

- Verify `notifications-ms` Prisma client is importable: `node -e "require('./dist/src/generated/prisma')"` inside the container or after local build.
- Verify `users-ms` starts without module-not-found errors by checking container logs immediately after deploy.
- Confirm `postgres` container remains healthy throughout (no accidental restart).
- Confirm all other MS (vehicles, events, maintenances) that were passing before remain unaffected.

## §8 Success Metrics

- **Primary**: `GET http://13.222.116.14:3000/api/health` → HTTP 200 within 5 minutes of deploy completion.
- **Secondary**: Zero containers in `Restarting` state 10 minutes after deploy.
- **Tertiary**: All six service containers show `(healthy)` in `docker compose ps`.

## §9 Open Questions

- The dotenv version in the PRD says `^17.4.2` — verify this is compatible with Node version on EC2 and consistent with dotenv version used by other microservices (e.g., `vehicles-ms/package.json`). If other MS pin an older version, align to that instead.
jkljk