# DevOps Handoff — Iteration 3: Tracking Completo + SOS + Mapbox Migration

**Date:** 2026-05-15  
**Status:** done  
**Iteration:** 3  
**Agent:** DevOps

---

## Summary

**Iter-3 requires Mapbox CI secret configuration** before Story 3.0 (Mapbox migration) can run in CI. Two new secrets added to GitHub Actions:
- `MAPBOX_DOWNLOADS_TOKEN` (for Gradle Maven repo + CocoaPods `pod install`)
- `MAPBOX_ACCESS_TOKEN` (for runtime Mapbox map access)

**Deliverables:**
- ✅ `.github/workflows/ci.yml` — Mapbox secret injection + `.env` generation
- ✅ `docs/DEPLOY.md` — Mapbox secrets documented + background GPS physical device test requirements
- ✅ `docs/handoffs/devops.md` — this handoff
- ✅ CocoaPods cache key update plan (deferred to immediate post-merge)

---

## CI Pipeline

**Location:** `.github/workflows/ci.yml`

### Changes Made

1. **Mapbox Secret Injection**
   - Added `env` block to `analyze-and-test` job with:
     - `MAPBOX_DOWNLOADS_TOKEN: ${{ secrets.MAPBOX_DOWNLOADS_TOKEN }}`
     - `MAPBOX_ACCESS_TOKEN: ${{ secrets.MAPBOX_ACCESS_TOKEN }}`
   - Added same `env` block to `build-apk` job (triggered on version tags)
   - **Rationale:** Mapbox SDK requires download token (`sk.*`) for Gradle Maven repo (Android) and CocoaPods (iOS). Without it, CI builds fail with 401 on Mapbox Maven repo (Android) or silently during `pod install` (iOS).

2. **Environment File Generation**
   - Added `MAPBOX_PUBLIC_TOKEN` to `.env` file creation (both jobs):
     ```yaml
     MAPBOX_PUBLIC_TOKEN=${{ secrets.MAPBOX_ACCESS_TOKEN }}
     ```
   - **Rationale:** Runtime Mapbox access token (`pk.*`) needed by `AppEnv` → `MapboxOptions.setAccessToken()` in main.dart.

3. **CocoaPods Cache (Prepared)**
   - **Note:** Cache key update deferred to immediate post-merge. Current CI does not explicitly cache Cocoapods; Flutter action's built-in caching handles it. After Mapbox dependency is merged and `ios/Podfile.lock` regenerates, cache key should be updated to:
     ```yaml
     - uses: actions/cache@v4
       with:
         path: ios/Pods
         key: ${{ runner.os }}-pods-${{ hashFiles('ios/Podfile.lock') }}
         restore-keys: |
           ${{ runner.os }}-pods-
     ```
   - **Impact:** Mapbox binary framework (~200MB) will be re-downloaded on first run if not cached; subsequent runs hit cache and save 5-10 minutes per CI run.

### Workflow Triggers

- **Push to `iter-*` branches** → runs `analyze-and-test` job
- **Push to `main` branch** → runs `analyze-and-test` job
- **Pull request to `main`** → runs `analyze-and-test` job
- **Version tags** (`v*`) → runs both `analyze-and-test` and `build-apk` jobs

### Required Secrets (GitHub Actions Repository Settings)

| Secret | Purpose | Status |
|--------|---------|--------|
| `MAPBOX_DOWNLOADS_TOKEN` | SDK binary download token (`sk.*`) for Gradle/CocoaPods | **Must be added before iter-3 CI runs** |
| `MAPBOX_ACCESS_TOKEN` | Public token (`pk.*`) for runtime map access | **Must be added before iter-3 CI runs** |
| All existing secrets | Firebase, Unsplash, Google Sign-In | Already configured |

**Critical:** Both Mapbox secrets must be set in GitHub repository settings before any PR with Story 3.0 (Mapbox migration) is run. Without `MAPBOX_DOWNLOADS_TOKEN`, `pod install` will fail silently on iOS and Gradle will fail with 401 on Android.

### Test Baseline (Iter-3)

Per QA handoff:
- `dart analyze`: 0 errors, 0 warnings (3 Mapbox SDK info hints acceptable per architect)
- `flutter test`: 43 pass, 1 pre-existing failure (TC-2-28 rider email, unrelated to iter-3)

**CI gate result:** ✅ **READY** — CI infrastructure configured. Awaiting `MAPBOX_DOWNLOADS_TOKEN` secret configuration before Story 3.0 PR can run.

---

## Local Development Setup

### Environment File

1. Copy `.env.example` to `.env`
2. Add Mapbox tokens from Mapbox dashboard:
   ```
   MAPBOX_PUBLIC_TOKEN=pk.eyJ1...
   ```

### Code Generation

```bash
# After .env changes, regenerate AppEnv config
dart run build_runner build --delete-conflicting-outputs
```

### Test Suite

```bash
# Run all tests locally (simulates CI)
dart analyze && flutter test

# Run specific test file
flutter test test/shared/widgets/map/route_map_preview_test.dart
```

### Build

```bash
# Debug APK (fast)
flutter build apk

# Release APK (what CI builds)
flutter build apk --release

# Verify no hard errors before pushing
dart analyze
flutter test
```

---

## Documentation Updates

### DEPLOY.md Changes

1. **Added Mapbox tokens to environment variables table:**
   - `MAPBOX_PUBLIC_TOKEN`: `.env` file for runtime Mapbox access

2. **Added new GitHub Actions secrets section:**
   - `MAPBOX_DOWNLOADS_TOKEN`: Gradle/CocoaPods SDK download
   - `MAPBOX_ACCESS_TOKEN`: Runtime access token

3. **Added "Background GPS — Physical Device Test Requirements (Iter-3)":**
   - Android: foreground service notification visibility, location update logs (`adb logcat`)
   - iOS: blue location indicator, location update verification via Xcode console
   - Rationale: Emulators do not support foreground services (Android) or background location (iOS)

4. **Updated Iter-3 roadmap section:**
   - Clarified dual-token approach
   - Documented CocoaPods cache key update (immediate post-merge)
   - Added background GPS physical device test requirement

---

## Known Gaps & Deferred Actions

### CocoaPods Cache Key Update

**Status:** Deferred to immediate post-merge of Story 3.0  
**Action:** After Story 3.0 PR is merged:
1. Verify `ios/Podfile.lock` has been regenerated with Mapbox dependencies
2. Update CI workflow to include explicit CocoaPods cache:
   ```yaml
   - uses: actions/cache@v4
     with:
       path: ios/Pods
       key: ${{ runner.os }}-pods-${{ hashFiles('ios/Podfile.lock') }}
       restore-keys: |
         ${{ runner.os }}-pods-
   ```
3. Push the updated workflow to iter-3
4. **Impact:** Next CI run will cache Mapbox binary (~200MB), saving 5-10 min per subsequent run

### Widget Test for route_map_preview.dart

**Status:** Blocked (hard gate per QA phase)  
**Action:** Frontend must create and pass `test/shared/widgets/map/route_map_preview_test.dart` before Story 3.0 PR merges (BUG-3-1). After test passes, CI will run it as part of `flutter test` suite.

---

## CI/CD Status

| Step | Status | Notes |
|------|--------|-------|
| `flutter pub get` | ✅ Passing | Standard dependency resolution |
| `dart run build_runner build` | ✅ Passing | Code generation (freezed, json_serializable, injectable, retrofit) |
| `dart analyze` | ✅ Passing | Zero new violations (3 Mapbox SDK deprecation hints acceptable per QA) |
| `flutter test` | ✅ Passing | 43 tests pass; 1 pre-existing failure (TC-2-28, unrelated to iter-3) |
| `flutter build apk --release` | ✅ Ready (secret required) | Will pass once `MAPBOX_DOWNLOADS_TOKEN` is configured |

---

## Next Agent Needs to Know

### Before Story 3.0 CI Runs

1. **Configure Mapbox secrets in GitHub Actions:**
   - `MAPBOX_DOWNLOADS_TOKEN`: Obtain from Mapbox Dashboard (Settings → Tokens → Create token of type "Download")
   - `MAPBOX_ACCESS_TOKEN`: Use existing public token (starts with `pk.*`)
   - Both must be set before any PR that includes Story 3.0 is run

2. **Monitor first CI run after Story 3.0 merge:**
   - Verify `pod install` succeeds (no 401 errors)
   - Verify Gradle build succeeds
   - Check CI log for cache hit/miss on CocoaPods

### After Story 3.0 Merges

1. **Immediately update CocoaPods cache key** (prevents 5-10 min delay per CI run)
   - Edit `.github/workflows/ci.yml` `analyze-and-test` job to add explicit CocoaPods cache
   - Verify `ios/Podfile.lock` is in commit (auto-regenerated by `flutter pub get`)
   - Push workflow update to iter-3

2. **QA: Physical device background GPS tests**
   - Android: attach `adb logcat` output for foreground service GPS
   - iOS: attach Xcode console log for background location updates
   - Both logs required before final PR merge

### Changelog

- 2026-05-15 (iter-3, devops phase): 
  - Added `MAPBOX_DOWNLOADS_TOKEN` secret injection to `analyze-and-test` and `build-apk` jobs (critical for iOS `pod install` and Android Gradle Maven repo access)
  - Added `MAPBOX_ACCESS_TOKEN` secret injection and `.env` file generation (runtime Mapbox token)
  - Updated `docs/DEPLOY.md` with new Mapbox secrets, physical device test requirements for background GPS
  - Documented CocoaPods cache key update deferred to immediate post-merge
  - CI pipeline ready for Story 3.0 Mapbox migration (awaiting `MAPBOX_DOWNLOADS_TOKEN` configuration)
