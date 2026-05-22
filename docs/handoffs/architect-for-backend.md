> Slim handoff — read this before docs/handoffs/architect.md

# Architect → Backend (NestJS) — Iteration 3

**Iteration goal:** Tracking SOS + organizer ride controls + Mapbox geocode proxy + cron reminders. All in existing microservice boundaries — no new microservice.

## Implementation order (strict)

`T-3-2` → `T-3-4` → `T-3-3` → `T-3-5`. SOS handler (T-3-3) depends on participant lookup from T-3-2.

---

## T-3-2: Tracking start/end HTTP endpoints

**Module:** `api-gateway/src/tracking/tracking-http.controller.ts` (already exists — extend it)

| Method | Path | Guard | Logic |
|--------|------|-------|-------|
| `POST` | `/api/events/:eventId/tracking/start` | Firebase Auth + organizer check | RPC to events-ms → set `state = IN_PROGRESS`; emit `tracking.event.started` to WS room; return `{ id, state:"IN_PROGRESS" }` |
| `POST` | `/api/events/:eventId/tracking/end` | Firebase Auth + organizer check | RPC to events-ms → set `state = FINISHED`; emit `tracking.event.ended` to WS room + FCM push to approved registrants; return `{ id, state:"FINISHED" }` |

Organizer check: compare `event.ownerId` against decoded Firebase UID (same pattern as existing event mutations).

Error responses:
- `403` if caller is not organizer
- `409` if state precondition fails (`start` requires `SCHEDULED`; `end` requires `IN_PROGRESS`)
- `404` if event not found

---

## T-3-4: Route GeoJSON endpoint + schema migration

**Events-ms schema** (`prisma/schema.prisma` — `Event` model):

```prisma
routeGeoJson  Json?
sosTriggeredAt DateTime?
```

Run `prisma migrate reset` on events-ms after adding fields (migration discards data — confirmed safe). Seed with `seed.ts` if present.

**New endpoint in events-ms** (proxied through api-gateway):

```
GET /api/events/:eventId/route
Auth: Bearer
Response 200: { "type": "LineString", "coordinates": [[lng, lat], ...] }
Response 204/200 {}: if routeGeoJson is null
Response 404: event not found
```

The `coordinates` array is **lng-first** (GeoJSON spec). Flutter's Mapbox SDK expects this order.

---

## T-3-3: SOS WebSocket handler

**Module:** `api-gateway/src/tracking/tracking.gateway.ts` — add `@SubscribeMessage('tracking.sos')` handler.

Flow:
1. Receive `{ type: "tracking.sos", data: { eventId, userId } }` from WS client.
2. RPC to events-ms: `markSosTriggered(eventId)` — sets `sosTriggeredAt = now()` only if null; returns `{ triggered: boolean, fullName: string, phone?: string, latitude: number, longitude: number }` (rider location from WS room state).
3. If `triggered === true`:
   - Broadcast to all room members: `{ type: "tracking.sos.alert", data: { userId, fullName, latitude, longitude, phone?: string } }`
   - FCM multicast to all approved registrant tokens (reuse iter-2 token lookup from `NotificationService`).
   - Insert row in `notifications` table (type: `SOS_ALERT`).
4. If `triggered === false` → no-op (already firing, deduplicated).

---

## T-3-5: Cron scheduler entries

**Module:** `api-gateway/src/notifications/notification-scheduler.service.ts` (created in iter-2 — extend it)

Add two `@Cron` methods. Use `@nestjs/schedule` (already installed). All times in `America/Bogota` (UTC-5).

### Maintenance 30-day reminder

```typescript
@Cron('0 9 * * *', { timeZone: 'America/Bogota' })
async sendMaintenanceDateReminders() {
  // Query maintenances-ms: find records where nextMaintenanceDate is 30 days from today
  // AND receiveDateAlert = true AND reminderSentAt IS NULL
  // FCM push to owner: "Tu mantenimiento de {serviceType} para {vehicleName} está programado en 30 días"
  // Mark reminderSentAt = now() to prevent re-fire
}
```

### Event 24h reminder

```typescript
@Cron('*/15 * * * *', { timeZone: 'America/Bogota' })
async sendEventReminders() {
  // Query events-ms: find events where startDate is between (now + 23h55m) and (now + 24h5m)
  // AND state = SCHEDULED AND reminderSentAt IS NULL
  // FCM multicast to all approved registrant tokens for each event
  // "La rodada {eventName} comienza en 24 horas"
  // Mark event.reminderSentAt = now()
}
```

Add `reminderSentAt DateTime?` to events-ms `Event` model (include in same migration as `routeGeoJson`/`sosTriggeredAt`).

---

## Places geocode endpoint

**Module:** `api-gateway/src/places/places.controller.ts` — add new endpoint (autocomplete already exists):

```
GET /api/places/geocode?q=<address>
Auth: Bearer
Response 200: { latitude: number, longitude: number, formattedAddress: string }
Response 404: no result found for address
Response 400: q is empty
Response 502: Mapbox upstream error
```

Proxy to Mapbox Geocoding API v6: `GET https://api.mapbox.com/geocoding/v5/mapbox.places/{encodedAddress}.json?access_token=MAPBOX_ACCESS_TOKEN&limit=1&language=es`

Extract `features[0].center` → `[longitude, latitude]` and `features[0].place_name` → `formattedAddress`.

---

## Environment variables (no new additions expected)

`MAPBOX_ACCESS_TOKEN` should already be set from `places/autocomplete`. Verify it is present in api-gateway `.env`.

---

> Full detail: docs/handoffs/architect.md
