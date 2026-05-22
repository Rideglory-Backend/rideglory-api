> Slim handoff — read this before docs/handoffs/architect.md

# Architect → DevOps — Iteration 3

**Two action windows:** (1) before Story 3.0 CI can run; (2) immediately after Story 3.0 merges.

---

## Before Story 3.0 CI runs — inject secret

### `MAPBOX_DOWNLOADS_TOKEN` CI secret (CRITICAL)

Mapbox requires a secret SDK download token (`sk.*`) to fetch the Mapbox binary framework on Android (Gradle) and iOS (CocoaPods). Without it, Android builds fail with a 401 on the Mapbox Maven repo and iOS builds fail silently during `pod install`.

**Action:** Add `MAPBOX_DOWNLOADS_TOKEN` as a GitHub Actions repository secret before any CI run that includes the Mapbox package.

In GitHub Actions workflow YAML, expose it to the build steps:
```yaml
env:
  MAPBOX_DOWNLOADS_TOKEN: ${{ secrets.MAPBOX_DOWNLOADS_TOKEN }}
```

For Android Gradle, it is also needed in `~/.gradle/gradle.properties` on the CI runner:
```
MAPBOX_DOWNLOADS_TOKEN=sk.eyJ1...
```

For iOS, `pod install` reads it from the environment. Confirm the `Podfile` references it via `ENV['MAPBOX_DOWNLOADS_TOKEN']` or the standard Mapbox Podfile snippet.

---

## Immediately after Story 3.0 merges — update CocoaPods cache key

The Mapbox binary framework is ~200MB. The current CocoaPods cache key in CI covers the old `google_maps_flutter` pods. After 3.0 merges, the cache key is stale and CI will re-download 200MB on every run until the key is updated.

**Action:** Update the `cache-name` / `key` value in the CocoaPods cache step of the GitHub Actions iOS workflow. Base the key on `ios/Podfile.lock` hash:

```yaml
- uses: actions/cache@v4
  with:
    path: ios/Pods
    key: ${{ runner.os }}-pods-${{ hashFiles('ios/Podfile.lock') }}
    restore-keys: |
      ${{ runner.os }}-pods-
```

If the workflow already uses `hashFiles('ios/Podfile.lock')`, the cache will auto-bust on the first run after `pod install` regenerates `Podfile.lock`. Verify by checking the CI log for a cache miss then a successful re-prime.

---

## New environment variables

| Variable | Scope | Description | Secret? |
|----------|-------|-------------|---------|
| `MAPBOX_DOWNLOADS_TOKEN` | CI only | SDK binary download token. Never in `.env`. | Yes — GitHub Actions secret |
| `MAPBOX_PUBLIC_TOKEN` | Flutter `.env` + `AppEnv` | Runtime access token (`pk.*`). Set via `MapboxOptions.setAccessToken()`. | No (public-scoped) — add to `.env.example` |

The rideglory-api already has `MAPBOX_ACCESS_TOKEN` for `places/autocomplete`. Verify it covers the new `/places/geocode` endpoint (same token, same scope — no new backend secret needed).

---

## DEPLOY.md updates

Add a new section **"Background GPS — Physical Device Test Requirements"**:

```markdown
## Background GPS — Physical Device Test Requirements (Iter-3)

### Android
- Physical device required (emulator does not support foreground service GPS correctly)
- Device under test: Samsung or Xiaomi (known aggressive battery restrictions)
- Steps:
  1. Start a mock event tracking session
  2. Send app to background (home button)
  3. Verify persistent non-dismissable notification "Rideglory — Rodada activa" in notification shade
  4. Wait 30 seconds; verify location updates continue appearing in WS server logs
  5. Attach device log (`adb logcat -s BackgroundTrackingService`) as PR artifact

### iOS
- Physical device required (simulator does not honor background location)
- Steps:
  1. Start a mock event tracking session
  2. Send app to background
  3. Verify blue location indicator in system status bar
  4. Wait 30 seconds; verify location updates continue in WS server logs
  5. Attach Xcode console log as PR artifact
```

---

## Checklist

- [ ] `MAPBOX_DOWNLOADS_TOKEN` added to GitHub Actions repository secrets before Story 3.0 CI run
- [ ] CocoaPods cache key updated immediately after Story 3.0 merges (verify Podfile.lock hash-based key)
- [ ] `MAPBOX_PUBLIC_TOKEN` added to `.env.example` with placeholder value
- [ ] `DEPLOY.md` updated with background GPS physical device test steps
- [ ] Confirm `dart analyze` + `flutter test` CI steps are unchanged (no new test commands needed)

> Full detail: docs/handoffs/architect.md
