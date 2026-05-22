# Architect → QA Handoff (slim)

## What to verify after Backend agent reports "deploy complete"

### 1. Container health

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 "cd /opt/rideglory && docker compose ps"
```

All 7 rows must show `(healthy)`:
- `rideglory-postgres`
- `rideglory-users-ms`
- `rideglory-vehicles-ms`
- `rideglory-events-ms`
- `rideglory-maintenances-ms`
- `rideglory-notifications-ms`
- `rideglory-api-gateway`

None in `Restarting` or `Exited`.

### 2. External health endpoint (PRIMARY success criterion)

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://13.222.116.14:3000/api/health
```

Expect: `200`.

### 3. Log inspection — must show NO module-not-found errors

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 \
  "cd /opt/rideglory && docker compose logs users-ms --tail=80 | grep -i 'cannot find module' || echo CLEAN"
# expect CLEAN

ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 \
  "cd /opt/rideglory && docker compose logs notifications-ms --tail=80 | grep -i 'cannot find module' || echo CLEAN"
# expect CLEAN
```

### 4. Sanity checks inside containers

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 \
  "cd /opt/rideglory && docker compose exec -T users-ms node -e \"require('dotenv/config'); console.log('ok')\""
# expect: ok

ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 \
  "cd /opt/rideglory && docker compose exec -T notifications-ms node -e \"require('./dist/src/generated/prisma'); console.log('ok')\""
# expect: ok
```

### 5. Regression checks on previously-healthy services

```bash
ssh -i ~/.ssh/rideglory-key.pem ec2-user@13.222.116.14 \
  "cd /opt/rideglory && docker compose logs vehicles-ms events-ms maintenances-ms --tail=40 | grep -iE 'error|fatal' || echo CLEAN"
# Expect: only routine startup logs, no fatal/error spam
```

### Fail conditions — block approval

- Any container stuck in `Restarting` after the deploy window (10 min).
- `curl /api/health` returns non-2xx.
- Either MS shows `Cannot find module ...` in logs.
- `postgres` shows restart events during the deploy window.

### Pass criteria — approve

- All 4 inspection commands above match expected outputs.
- Steady-state observed (no churn) for 5 minutes after final health check.

### Reference

Full diagnosis: `docs/custom-iters/aws-backend-deploy/handoffs/architect.md`.
