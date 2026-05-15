# Backend handoff (rideglory-api) — Ad-hoc: notifications-ms + tracking analysis

**Date:** 2026-05-15
**Status:** done

---

## What was done

### 1. notifications-ms — Full NestJS TCP microservice

The `notifications-ms/` directory already had scaffolding (Prisma schema, package.json, config). The full NestJS microservice has been implemented:

| File | Purpose |
|------|---------|
| `src/main.ts` | TCP microservice bootstrap — port from `envs.port`, `RpcAllExceptionsFilter`, `ValidationPipe` |
| `src/app.module.ts` | Root module importing `NotificationsModule` |
| `src/notifications/notifications.module.ts` | Feature module |
| `src/notifications/notifications.service.ts` | Prisma + FCM logic — extends PrismaClient, initializes Firebase Admin |
| `src/notifications/notifications.controller.ts` | TCP `@MessagePattern` handlers |

**Message patterns exposed:**

| Pattern | Payload | Returns |
|---------|---------|---------|
| `notification.create` | `{ userId, type, data }` | Created Notification row |
| `notification.list` | `{ userId, cursor?, limit? }` | `{ data[], nextCursor }` |
| `notification.markRead` | `{ notificationId, userId }` | void — throws 403/404 via RpcException |
| `notification.markAllRead` | `{ userId }` | void |
| `notification.sendFcm` | `{ fcmToken, title, body, data }` | void — FCM failures are non-fatal (logged only) |

**Notification types** (enum in `notifications.service.ts`):
`NEW_REGISTRATION`, `REGISTRATION_APPROVED`, `REGISTRATION_REJECTED`, `SOAT_30D`, `SOAT_7D`, `SOAT_DAY_OF`, `MAINTENANCE_DATE_REMINDER`, `EVENT_REMINDER`, `SOS_ALERT`, `TRACKING_ENDED`

**DB:** Notification table (same schema as before) — notifications-ms now owns it exclusively.

**Port:** `3005` (set in `notifications-ms/.env`).

---

### 2. api-gateway — NotificationsService refactored to RPC proxy

`NotificationsService` no longer extends `PrismaClient` or calls firebase-admin directly. It is now a thin RPC client that delegates to notifications-ms via TCP.

Public method signatures are **unchanged** — scheduler and tracking code required zero changes.

**Files modified:**

| File | Change |
|------|--------|
| `src/config/services.ts` | Added `NOTIFICATIONS_SERVICE = 'NOTIFICATIONS_SERVICE'` |
| `src/config/envs.ts` | Added `NOTIFICATIONS_MS_PORT` + `NOTIFICATIONS_MS_HOST` |
| `src/notifications/notifications.service.ts` | Full rewrite — now a NestJS `@Injectable()` injecting `ClientProxy` |
| `src/notifications/notifications.module.ts` | Registers `ClientsModule` with both `USERS_SERVICE` and `NOTIFICATIONS_SERVICE` |
| `.env` / `.env.example` | Removed `DATABASE_URL` (no longer used by gateway); added `NOTIFICATIONS_MS_PORT=3005`, `NOTIFICATIONS_MS_HOST=localhost` |

**No changes required in:** `notification-scheduler.service.ts`, `tracking.gateway.ts`, `tracking-http.controller.ts` — all call the same `NotificationsService` methods.

---

## Environment variables

### api-gateway
| Variable | Purpose |
|----------|---------|
| `NOTIFICATIONS_MS_PORT` | Port of notifications-ms (default: 3005) |
| `NOTIFICATIONS_MS_HOST` | Host of notifications-ms (default: localhost) |
| ~~`DATABASE_URL`~~ | **Removed** — api-gateway no longer owns the Notification DB |

### notifications-ms
| Variable | Purpose |
|----------|---------|
| `PORT` | TCP port for this microservice (set to 3005) |
| `DATABASE_URL` | PostgreSQL connection string — owns the `Notification` table |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Service account JSON string for FCM dispatch |
| `FIREBASE_PROJECT_ID` | Fallback if service account JSON is not set |

---

## DB notes

- notifications-ms has its own Prisma migration at `notifications-ms/prisma/migrations/20260515050000_init_notifications/`
- api-gateway still has a prisma folder and `@prisma/client` dependency from the previous implementation — these can be removed in a cleanup pass (no code references them anymore)
- In production, use **separate PostgreSQL databases** for each microservice (or at minimum separate schemas) to avoid migration table conflicts

---

## Test results

- api-gateway `notifications.service.spec.ts` — pure logic tests, no service injection — **pass** (unchanged)
- notifications-ms unit tests — not yet written (no test files in `notifications-ms/src/notifications/`)
- Recommend adding: unit test for `NotificationsService.listNotifications` pagination logic and `markRead` authorization in notifications-ms

**How to run existing tests:**
```bash
cd api-gateway && npm test
```

---

## 2. Tracking microservice analysis

### Current state
Tracking lives entirely within `api-gateway`:
- `TrackingGateway` — WS server with in-memory connection state via `TrackingRoomsService`
- `TrackingHttpController` — REST endpoints for start/stop/session/snapshot/route
- `TrackingBroadcaster` — pushes WS messages to in-memory rooms
- `TrackingRoomsService` — in-memory `Map<eventId, Set<WebSocket>>`

Tracking has zero DB of its own: all persistence goes through events-ms via RPC. It only injects `NotificationsService` (now RPC), `FirebaseAuthService`, and the `EVENTS_SERVICE` / `USERS_SERVICE` clients.

### Recommendation: **Keep tracking in api-gateway**

**Reason 1 — In-memory state cannot be split without infrastructure.**
`TrackingRoomsService` holds live WebSocket connections in a plain `Map`. Moving this to a separate process would require sticky sessions (Nginx/ALB) + a pub/sub bus (Redis) for cross-instance broadcasting. Adding that infrastructure for the current user base (~dozens of concurrent riders per event) introduces complexity that delivers no operational benefit.

**Reason 2 — WS connections are tightly coupled to Firebase Auth.**
`TrackingGateway` validates WS tokens using `FirebaseAuthService`, which is already in the gateway. Extracting tracking would mean either duplicating firebase-admin initialization or creating a shared auth service — both are more complexity than the extraction saves.

**Reason 3 — Tracking does not own domain logic.**
Tracking is a thin relay: it reads location from clients → delegates persistence to events-ms → broadcasts to room members. There is no business logic that would benefit from isolation. The domain owner is events-ms.

**Reason 4 — Scale profile doesn't justify it today.**
Tracking traffic is bursty (high during events, zero otherwise). Kubernetes HPA can handle this without a separate service. A separate tracking process would sit idle most of the time, adding operational overhead for no gain.

### When to extract tracking (future trigger)

Extract to a dedicated microservice **if and when**:
- Concurrent WS connections per event exceed ~500 and require horizontal scaling
- At that point, also add: Redis pub/sub for cross-instance broadcasting, sticky sessions in the load balancer, and a dedicated WS process with no REST handlers

---

## Known gaps

- notifications-ms unit tests not written — low risk (business logic is identical to what was previously tested in api-gateway)
- api-gateway still has prisma folder and `@prisma/client` dep — no code uses them — cleanup optional
- notifications-ms `.env` Firebase credentials are placeholder — operator must fill in before running FCM dispatch

## Next agent needs to know

- **Flutter dev (frontend):** No API contract changes. Same endpoints: `GET /api/notifications`, `PATCH /api/notifications/:id/read`, `PATCH /api/notifications/read-all`, `POST /api/notifications/fcm-token`. Response shapes unchanged.
- **QA:** Start notifications-ms (`cd notifications-ms && npm run start:dev`) on port 3005 before starting api-gateway. Run `prisma migrate dev` in notifications-ms to init the DB.
- **DevOps:** New service `notifications-ms` needs its own process/container. Required env vars: `PORT=3005`, `DATABASE_URL`, `FIREBASE_SERVICE_ACCOUNT_JSON`. Add `NOTIFICATIONS_MS_PORT` + `NOTIFICATIONS_MS_HOST` to api-gateway deployment env.
- **Tech lead:** NotificationsService in api-gateway is now a pure RPC proxy — no DB or Firebase Admin in the gateway. firebase-admin import can eventually be removed from api-gateway package.json.

## Change log

- 2026-05-15: notifications-ms implemented (main.ts, app.module.ts, notifications module with controller + service). api-gateway NotificationsService refactored to RPC proxy. Config updated. Tracking analysis delivered.
