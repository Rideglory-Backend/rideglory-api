# Backend handoff (rideglory-api) — Iteration 3

**Date:** 2026-05-15
**Status:** done

## Endpoints delivered

| Endpoint | Method | Service | Status | Notes |
|----------|--------|---------|--------|-------|
| `/api/events/:eventId/tracking/start` | POST | api-gateway → events-ms | done | Organizer-only guard via ownerId check; state SCHEDULED→IN_PROGRESS; WS broadcast `tracking.event.started` |
| `/api/events/:eventId/tracking/end` | POST | api-gateway → events-ms | done | Organizer-only guard; state IN_PROGRESS→FINISHED; WS broadcast `tracking.event.ended`; FCM multicast to approved registrants |
| `/api/events/:eventId/route` | GET | api-gateway → events-ms | done | Returns routeGeoJson (GeoJSON LineString) or `{}` if null; 404 if event not found |
| `/api/places/geocode?q=` | GET | api-gateway → Mapbox | done | Proxy to Mapbox Geocoding v5; returns `{ latitude, longitude, formattedAddress }`; 400/404/502/503 |
| `tracking.sos` WS message | WS | TrackingGateway | done | markSosTriggered (dedup via sosTriggeredAt); broadcasts `tracking.sos.alert`; FCM multicast to all approved registrants |
| Maintenance 30d cron | @Cron | NotificationSchedulerService | done | Daily 09:00 Bogota; `findMaintenancesDueSoon(30)` in maintenances-ms; FCM push; marks `reminderSentAt` |
| Event 24h cron | @Cron | NotificationSchedulerService | done | Every 15 min; events with startDate in [now+23h55m, now+24h5m]; FCM multicast; marks `reminderSentAt` |

## Schema migrations

| Service | Migration | Fields added |
|---------|-----------|-------------|
| events-ms | `20260515030000_iter3_route_sos_reminder` | `routeGeoJson Json?`, `sosTriggeredAt DateTime?`, `reminderSentAt DateTime?` on `Event` |
| maintenances-ms | `20260515030001_iter3_reminder_sent_at` | `reminderSentAt DateTime?` on `Maintenance` |

## Validation and security

- Firebase ID token verified: confirmed — all HTTP endpoints protected by existing `FirebaseAuthGuard`
- Input validation: UUID via `ParseUUIDPipe` for eventId; `q` query param required with `BadRequestException`
- Sensitive fields excluded from responses: none — only public event/tracking state returned
- Organizer guard: `event.ownerId !== authUserId` → RpcException 403

## Test results

- Unit (events-ms): 19 pass / 19 total (8 filter tests + 11 iter-3 tracking tests)
- Unit (api-gateway): 25 pass / 25 total (19 pre-existing notifications + 6 geocode tests)
- Integration/e2e: none (no live DB in CI; mocked)
- How to run:
  ```bash
  cd /Users/cami/Developer/Personal/rideglory-api/events-ms && npx jest --no-coverage
  cd /Users/cami/Developer/Personal/rideglory-api/api-gateway && npx jest --no-coverage
  ```
- `nest build` passes with zero TypeScript errors on: api-gateway, events-ms, maintenances-ms

## Environment variables (see .env.example in api-gateway)

| Variable | Purpose |
|----------|---------|
| `MAPBOX_ACCESS_TOKEN` | Mapbox public token (pk.*) for geocode proxy at `GET /api/places/geocode` |

All other env vars pre-exist from iter-2. `MAPBOX_ACCESS_TOKEN` was added to:
- `api-gateway/.env.example`
- `api-gateway/src/config/envs.ts` (optional field, no validation failure if absent)

## Known gaps

- **SOS location accuracy**: events-ms does not store live rider positions (in-memory in tracking-ms). The WS client must include `{ latitude, longitude }` in the `tracking.sos` payload. If omitted, coords are null in the broadcast — frontend must handle gracefully.
- **Prisma migrate**: Both new migrations are SQL-only files. Run `npx prisma db push` or apply via `prisma migrate deploy` in staging. `prisma migrate reset` was blocked by Prisma AI safety guard — manual apply required.
- **`reminderSentAt` reset**: No endpoint to reset `reminderSentAt` for testing — must be done directly in DB.

## Next agent needs to know

- **Flutter dev (frontend):**
  - `POST /api/events/:eventId/tracking/start` returns `{ id: string, state: "IN_PROGRESS" }`
  - `POST /api/events/:eventId/tracking/end` returns `{ id: string, state: "FINISHED" }`
  - `GET /api/events/:eventId/route` returns GeoJSON LineString `{ type, coordinates }` or `{}` if none set; coordinates are `[lng, lat]` (GeoJSON spec, lng-first — Mapbox expects this)
  - `GET /api/places/geocode?q=<address>` returns `{ latitude, longitude, formattedAddress }`
  - WS message to trigger SOS: `{ type: "tracking.sos", data: { eventId, userId, latitude, longitude } }`
  - WS message received on SOS alert: `{ type: "tracking.sos.alert", data: { userId, fullName, latitude, longitude, phone? } }`
  - WS message on ride end: `{ type: "tracking.event.ended", data: { eventId } }`
  - WS message on ride start: `{ type: "tracking.event.started", data: { eventId } }`
- **QA:** Start all microservices locally. Apply migrations on events-ms and maintenances-ms. Use Postman with Firebase ID token to test tracking start/end.
- **DevOps:** `MAPBOX_ACCESS_TOKEN` must be added to CI/CD secrets if geocode endpoint is tested in integration.
- **Tech lead:** Organizer check is synchronous (ownerId comparison after findOne) — no race condition. SOS deduplication uses a single DB write with `sosTriggeredAt: null` check — safe for concurrent WS clients.

## Change log

- 2026-05-15: Iteration 3 backend complete. Tracking start/end, SOS WS handler, route GeoJSON endpoint, Mapbox geocode proxy, maintenance 30d cron, event 24h cron. 44 tests pass (events-ms 19 + api-gateway 25).
