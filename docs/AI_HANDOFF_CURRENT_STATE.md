# SpatialVerify / Census Mobile — AI Handoff Document

**Last updated:** 2026-06-30  
**Purpose:** Give another AI (or engineer) full context on **what is implemented today** — architecture, flows, and constraints — without reading the entire repo.

For target/future architecture (evidence pipeline, Node API), see [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) and [`README.md`](./README.md).

---

## 1. Executive summary

**SpatialVerify** (`spatialverify` Flutter app in `mobile/`) is a geospatial field-survey platform built for **Indian census HLB (House Listing Block) enumeration**. The primary user journey today is:

1. **Sign in** with Firebase Auth (email/password)
2. **Import an official HLO PDF** (officer layout map)
3. **Georeference it** to satellite imagery via control pins + CV-detected boundary
4. **Work on a full-screen satellite mission map** (Google Maps when API key present)
5. **Place buildings, features, and roads** using a map crosshair (not a camera walk)
6. **Fine-tune PDF overlay alignment** after initial fit
7. Transition to **house listing** once mapping coverage is sufficient

**Cloud backend:** Firebase Auth + Firestore + Storage. Mission state is **offline-first** on device (Hive), then syncs when signed in.

**Primary dev target:** USB-connected Android phone via `mobile/run-debug.ps1`. Web is not a production target.

---

## 2. Repository layout

```
d:\census\
├── mobile/          ← Flutter app (main product surface)
├── firebase/        ← Firestore + Storage security rules
├── public/          ← Firebase Hosting APK download page
├── docs/            ← Specs (see docs/README.md for current vs target)
├── scripts/         ← OTA publish, version bump, Firebase token setup
├── tools/           ← Bundled Flutter SDK + Android SDK (Windows dev)
└── .github/workflows/  ← CI + OTA + Firebase deploy
```

| Area | Stack |
|------|--------|
| Mobile | Flutter 3.x, Dart ≥3.5, Riverpod, go_router, Drift (SQLite), Hive |
| Cloud | Firebase Auth, Cloud Firestore, Firebase Storage, Firebase Hosting |
| Maps | `google_maps_flutter` (primary on Android), `flutter_map` + Esri (fallback) |
| CV | On-device `spatial_cv_*` pipeline (boundary detection from PDF raster) |
| OCR | `google_mlkit_text_recognition` for EB block labels on PDF panels |

**Not in repo:** `backend/`, `docker/`, Cloud Functions, PostgreSQL API.

---

## 3. Product phases & routing

### 3.1 App entry

- **`main.dart`**: Initializes secure storage, Drift DB, Riverpod; portrait-only on native.
- **`router.dart`**: Requires Firebase login — unauthenticated users go to `/login`, then `/` (`MissionLandingScreen`).
- **`MissionLandingScreen`**: Resolves GPS once via `appLaunchLocationProvider`, then routes to active HLB or lobby.

### 3.2 HLB phase gate

**`MissionEbRouter`** reads `discoveryStatusProvider` and branches on `DiscoveryStatus.phase`:

| Phase | Screen |
|-------|--------|
| `'mapping'` | `MissionGameMapScreen` — gamified satellite map (primary UX) |
| other | `TodaysMissionScreen` — house listing workflow |

Phase is stored in **`HlbLocalState.phase`** (Hive box `hlb_local_state`).

### 3.3 Key routes (under `/mission/:projectId/eb/:ebId/...`)

| Path | Screen | Purpose |
|------|--------|---------|
| `/` (via landing) | `MissionGameMapScreen` | Map-first mission home |
| `/georef` | `LayoutGeorefWizardScreen` | Import PDF → georef → official boundary |
| `/reorient` | `LayoutGeorefWizardScreen(startInAdjustMode: true)` | Re-adjust existing alignment |
| `/start-point` | `StartPointScreen` | Navigate to NW entry corner |
| `/hub` | `DiscoveryHubScreen` | Mission hub / progress |
| `/listing` | `TodaysMissionScreen` | Building-by-building enumeration |
| `/gaps` | `CoverageGapsScreen` | Coverage gap review |
| `/draft-map` | `DraftHlbMapScreen` | Draft boundary map |
| `/building/:buildingId` | `BuildingWorkflowScreen` | Single building workflow |

Full route table: `mobile/lib/features/home/presentation/router.dart`.

---

## 4. Configuration & environment

### 4.1 Dart compile-time defines (`AppConfig`)

File: `mobile/lib/core/config/app_config.dart`

| Define | Default | Meaning |
|--------|---------|---------|
| `GOOGLE_MAPS_API_KEY` | `''` | Enables Google Maps + Directions |
| `MAPBOX_ACCESS_TOKEN` | `''` | Mapbox (optional; `/map/:projectId` screen) |

**`AppConfig.hasGoogleMaps`** → true when `GOOGLE_MAPS_API_KEY` non-empty.

Without Google Maps: Esri satellite fallback + compass/bearing navigation (no turn-by-turn polyline on Google).

### 4.2 Android dev script

File: `mobile/run-debug.ps1`

- Sets Flutter + ADB paths from `d:\census\tools\`
- Reads `GOOGLE_MAPS_API_KEY` from env or `android/local.properties`
- Passes `--dart-define=GOOGLE_MAPS_API_KEY=...`
- Flags: `-Pub`, `-Clean`, `-Attach`, `-NoBuild`, `-AllDeviceLogs`

### 4.3 Gradle (Windows gotcha)

File: `mobile/android/gradle.properties`

```
kotlin.incremental=false
```

**Must stay false** when Pub cache is on `C:` and project on `D:` — incremental Kotlin breaks builds across drives.

---

## 5. Data architecture (mobile)

### 5.1 Two persistence layers

| Store | Technology | Contents |
|-------|------------|----------|
| **HLB mission state** | Hive (`hlb_local_state` box) | Boundaries, buildings, breadcrumbs, intelligence JSON, phase |
| **General app data** | Drift/SQLite | Users cache, assets, sync queue |
| **Layout images** | Filesystem + Firebase Storage | PDF/PNG bytes per EB |
| **Cloud sync** | Firestore | Per-user `projects/{id}/ebs/{ebId}` via `FirebaseMissionRepository` |

**Source of truth for mission UX:** `HlbLocalState` via `HlbLocalCache` → `MissionLocalFirstService`.

### 5.2 HlbLocalState key fields

File: `mobile/lib/features/mission/data/hlb_local_state.dart`

```dart
ebId, ebCode, projectId
phase              // 'mapping' | later phases
blockStatus        // 'draft' | ...
officialBoundary   // null until georef confirmed → hasOfficialBoundary
layoutGeoref       // legacy georef JSON
missionIntelligence // primary post-import package (imageBounds, boundary, alignment)
buildings, landmarks, breadcrumbs, spatialNodes, roadSegments, ...
```

**`hasOfficialBoundary`** = `officialBoundary != null`. Gates navigation, fine-tune, discovery features.

### 5.3 Mission intelligence package (post-import)

After PDF import, state is written to `missionIntelligence` (and mirrored in `layoutGeoref`):

```json
{
  "layoutImagePath": "<local file path>",
  "alignment": { "imageBounds": { north, south, east, west, rotation } },
  "boundary": {
    "gpsRing": [{ lat, lng }, ...],
    "uvRing": [{ x, y }, ...]
  },
  "regions": [...],
  "confidence": {...}
}
```

**`MissionMapSession`** (`mission_map_session.dart`) hydrates map UI from this:
- `boundaryRing`, `imageBounds`, `layoutImagePath`, `uvRing`, `startPoint`, `draftPins`, `walkPath`

### 5.4 Providers (Riverpod)

File: `mobile/lib/features/mission/presentation/mission_providers.dart`

| Provider | Role |
|----------|------|
| `appLaunchLocationProvider` | One-shot GPS at launch |
| `missionLocalFirstProvider` | Read/write HLB state |
| `localMissionImportProvider` | PDF import + CV + georef commit |
| `discoveryStatusProvider` | Phase, boundary status, start point distance |
| `missionCompletionProvider` | Progress percentages |
| `hlbLocalCacheProvider` | Hive access |

Query key: `EbMissionQuery(ebId, projectId)`.

---

## 6. Core user flows (detailed)

### 6.1 HLO import & georef wizard

**Screen:** `LayoutGeorefWizardScreen`  
**Route:** `/mission/:projectId/eb/:ebId/georef`

**Phases (`_WizardPhase`):**

1. **`upload`** — pick PDF/image via file_picker
2. **`analyzing`** — stepped progress overlay ("Aligning to Google Maps…", etc.)
3. **`pdfEditor`** — `HloPdfGeorefEditor` full-screen PDF interaction
4. **`verifyLandmarks`** — landmark anchor verification panel
5. **`mapExperience`** — satellite reveal + mission review bottom sheet
6. **`adjust`** — corner adjust OR PDF overlay nudge (dual focus modes)

**Import pipeline (`LocalMissionImportService`):**

```
PDF/image file
  → saveMissionLayoutBytes(ebId)
  → runSpatialCvPipeline(bytes)           // boundary polygon in UV space
  → LandmarkAnchorService.prepare()       // OCR/Places anchor candidates
  → user places ≥3 georef pins on PDF
  → SatelliteAlignMath / layout_georef_math compute ImageBounds + GPS ring
  → buildIntelligence() → persist to HlbLocalState
  → hydrateOfficialBoundary()
```

**Minimum georef pins:** `kMinGeorefMatchedPins = 3` (`pdf_georef_models.dart`).

### 6.2 PDF georef editor (game-style HUD)

**File:** `mobile/lib/features/mission/widgets/hlo_pdf_georef_editor.dart`

Recent UX (intentionally minimal chrome):

- **No AppBar** after PDF loaded + boundary traced
- **+ pin orb** top-right (red pin with + badge, no "Add pin" text)
- **Dual virtual joysticks** (`MissionMapVirtualJoystick` in `mission_map_game_hud.dart`):
  - Left stick: pan PDF OR nudge selected pin
  - Right stick: rotate PDF
- **Pin nudge D-pad** bottom-left when pin selected
- **Progressive boundary animation**: 3-second red line draw after CV boundary (`AnimationController` + `_BoundaryPainter`)
- **Scan overlay** while CV runs (`_BoundaryScanOverlay`, `_BoundaryRevealBanner`)
- **Pin search**: `PinPlacesAutocompleteField` with **inline suggestions** (`overlaySuggestions: false`)

Pin model: `PdfGeorefPin` with Google Places match.

### 6.3 Mission game map (primary mapping UX)

**File:** `mobile/lib/features/mission/presentation/mission_game_map_screen.dart`

Full-screen **`MissionMapCanvas`** with HUD overlays:

**Layer toggles** (`MissionMapLayersDrawer`):
- Official map (PDF overlay), region pins, boundary, route, start marker, draft buildings, walk path
- PDF opacity slider (0–1)
- Basemap: hybrid / satellite / normal

**Navigation:**
- Turn-by-turn banner when `_navigateMode` + Google Maps + start point set
- Compass fallback without Google Maps (`BearingArrow`)

**Auto-focus behavior:**
- Fit boundary button increments `_fitToken` → camera fits boundary
- **`MissionMapCameraSession.hasAutoCenteredOnUser`** — GPS auto-center **once at launch only**, not on every GPS tick (`mission_map_helpers.dart`, wired in `google_mission_map.dart`)

**Layers dismiss:**
- `MissionMapLayersDismissBarrier` closes drawer on tap outside map controls

### 6.4 PDF fine-tune alignment (post-fit)

**Trigger:** After tapping **Fit boundary** (`center_focus_strong`), a **tune icon** appears top-left if `canFineTune`:

```dart
_canFineTune =>
  hasOfficialBoundary &&
  AppConfig.hasGoogleMaps &&
  session.imageBounds != null &&
  session.layoutImagePath != null &&
  session.uvRing.length >= 3
```

**Flow:**
1. Enter fine-tune → map camera locked (`lockCameraGestures: true`)
2. `MissionPdfFineTuneLayer` captures pinch/scale/rotate/drag gestures
3. Updates `ImageBounds` → recomputes GPS boundary via `SatelliteAlignMath.gpsBoundaryFromUvRing(bounds, uvRing)`
4. **Confirm** → `applyReorientedBoundary()` persists to Hive
5. **Cancel** → restores saved bounds

**Files:**
- `mission_pdf_fine_tune_layer.dart` — gesture layer + confirm/cancel bar
- `google_mission_map.dart` — `lockCameraGestures`, ground overlay rendering

**Recent fixes (critical):**
- **Bearing normalization:** Google `GroundOverlay` requires bearing ∈ [0, 360). `SatelliteAlignMath.normalizeMapBearing()` applied in `rotateBounds()` and overlay creation.
- **Stable overlay ID:** `GroundOverlayId('hlo_layout_overlay')` — no epoch bump on bounds-only changes (prevents platform view remount storm / hang).
- **Gesture throttling:** Fine-tune layer notifies parent max ~30fps; accumulates in local `_liveBounds`.
- **Opacity during fine-tune:** Uses `_pdfOpacity` from layers drawer (was briefly hardcoded to 0.55 — fixed).

---

## 7. Map rendering stack

### 7.1 Abstraction layer

```
MissionMapCanvas
  ├── GoogleMissionMap     (if AppConfig.hasGoogleMaps && !kIsWeb issues)
  └── MissionSatelliteMap  (flutter_map + Esri tiles fallback)
```

Both consume: boundary polylines, PDF ground overlay, markers, route polyline.

### 7.2 Google Maps specifics

**File:** `google_mission_map.dart`

- PDF rendered as **`GroundOverlay.fromBounds`** with bitmap from `loadLayoutGroundOverlayBitmap()`
- Bearing from `ImageBounds.rotation` (normalized)
- Transparency = `1 - pdfOpacity`
- Boundary draw animation via `boundaryDrawProgress` (0–1)
- **`followUserLocation`**: respects `MissionMapCameraSession.hasAutoCenteredOnUser`

### 7.3 ImageBounds & alignment math

**File:** `satellite_align_math.dart`

```dart
class ImageBounds { north, south, east, west, rotation }

SatelliteAlignMath.normalizeMapBearing(degrees)  // [0, 360)
SatelliteAlignMath.shiftBounds(bounds, dNorth, dEast)
SatelliteAlignMath.scaleBounds(bounds, factor)
SatelliteAlignMath.rotateBounds(bounds, deltaDegrees)
SatelliteAlignMath.gpsBoundaryFromUvRing(bounds, uvRing)
SatelliteAlignMath.gpsFromUv(bounds, u, v)
```

UV ring is the CV-traced boundary in normalized PDF coordinates. GPS ring is derived by mapping UV → lat/lng through current `ImageBounds`.

**Rigid boundary adjust:** `boundary_rigid_align_math.dart` + `BoundaryCornerAdjustMap` for corner-handle alignment in wizard adjust mode.

---

## 8. Spatial CV pipeline

**Version:** `spatialCvVersion = '1.2.0-mobile'`

**File:** `core/spatial_cv/spatial_cv_pipeline.dart`

Current mobile pipeline (simplified vs full spec):

1. Load RGB image (max 1600px)
2. `detectBoundary()` → UV polygon + confidence
3. Returns `CvExtractionResult` with empty observation targets/roads (stubs for future)

Optional **block center hint:** OCR finds EB number on PDF panel → biases boundary detection.

**Worker:** `mission_cv_worker.dart` may isolate heavy work.

---

## 9. Discovery & mapping (implemented)

Once `hasOfficialBoundary`:

**Screen:** `mission_game_map_screen.dart`

- **Crosshair placement:** Pan/zoom the map; center crosshair marks the spot. Tools: **Building**, **Feature**, **Road/line** → tap **Place**.
- **`MissionHlbMarkSheet`:** Confirms building type, house count, landmark name, or road segment after placement.
- **Navigation to NW corner:** More menu (☰) → **Navigate to NW corner** when boundary + start point exist.
- **`DiscoveryStatus`** from `HlbStateComputer.discovery()` — breadcrumbs, buildings, gaps, start point bearing/distance.
- **Coverage gaps:** `HlbStateComputer.detectGaps()` — road-without-building, unvisited regions, etc.
- **Building workflow:** per-building status in listing phase (`BuildingWorkflowScreen`).

**Principle:** Enumerator places and confirms structures on the map. There is **no camera-based discovery walk** in the current app.

Spec reference (partial / target): `docs/DISCOVERY_ENGINE_SPEC.md`, `docs/MISSION_KNOWLEDGE_ENGINE.md`.

---

## 10. Cloud sync (Firebase)

**When signed in**, `MissionLocalFirstService`:

1. Writes to Hive immediately (never blocked by network).
2. Pushes EB state JSON to Firestore `users/{uid}/projects/{projectId}/ebs/{ebId}`.
3. Uploads layout PDF/PNG to Firebase Storage when present.
4. Pulls remote state on `syncInBackground()` and merges by timestamp.

**OTA updates:** `AppUpdateService` watches `system/android_release`, downloads APK from Storage.

There is **no Node/Fastify API** in this repository.

---

## 11. UI / theme

- **Dark theme:** `AppTheme.darkTheme` (`core/theme/app_theme.dart`)
- **Glass-style cards:** `AppTheme.glassDecoration()`
- **Game HUD components:** `mission_map_game_hud.dart`
  - `MissionMapHudIconButton`, `MissionMapLayersDrawer`, `MissionMapBottomBar`
  - `MissionMapVirtualJoystick`, `MissionMapLayersDismissBarrier`
  - `MissionMapBasemap` enum → GoogleMapType

UX contract: `docs/MISSION_MAP_UX.md` (satellite-first, PDF as import artifact).

---

## 12. File index (mission-critical)

| File | Responsibility |
|------|----------------|
| `mission_game_map_screen.dart` | Primary map screen, fine-tune state, HUD wiring |
| `layout_georef_wizard_screen.dart` | Full import/georef wizard (~2000 lines) |
| `hlo_pdf_georef_editor.dart` | Interactive PDF georef UI |
| `google_mission_map.dart` | Google Maps canvas + overlays |
| `mission_map_canvas.dart` | Map backend selector |
| `mission_map_game_hud.dart` | Shared HUD widgets |
| `mission_pdf_fine_tune_layer.dart` | Post-fit PDF alignment gestures |
| `satellite_align_math.dart` | ImageBounds math + bearing normalize |
| `local_mission_import_service.dart` | Import pipeline + `applyReorientedBoundary` |
| `mission_map_session.dart` | Session hydration for map |
| `hlb_local_state.dart` / `hlb_local_cache.dart` | On-device state |
| `hlb_state_computer.dart` | Discovery, gaps, phase computation |
| `mission_providers.dart` | Riverpod providers |
| `run-debug.ps1` | Android USB dev launcher |

---

## 13. Known issues & constraints

### 13.1 Resolved recently

| Issue | Fix |
|-------|-----|
| Fine-tune crash: `bearing >= 0 && bearing <= 360` assertion | `normalizeMapBearing()` everywhere |
| Fine-tune hang: new GroundOverlay ID every frame | Stable `hlo_layout_overlay` ID, no epoch bump on bounds change |
| Fine-tune opacity ignored | Removed hardcoded 0.55; uses `_pdfOpacity` |
| Map re-centered on every GPS update | `MissionMapCameraSession.hasAutoCenteredOnUser` |
| Kotlin incremental build failure (C: vs D: drives) | `kotlin.incremental=false` |

### 13.2 Open / watch items

- **Performance during fine-tune:** Each bounds update still triggers full overlay rebuild + boundary ring recompute. Throttled to ~30fps but may jank on low-end devices (Xiaomi/Mali GPUs seen in logs).
- **CV pipeline stub:** Observation targets and roads not extracted in mobile CV v1.2 — wizard may show minimal region data.
- **Web support:** Partial — platform-specific storage/database connections exist but primary dev is Android.
- **`mobile/README.md`:** Still default Flutter template; not maintained.

### 13.3 Device log noise (benign)

- `ProxyAndroidLoggerBackend: Too many Flogger logs` — Google Maps SDK
- `err write to mi_exception_log` — Xiaomi MIUI
- `MALI DEBUG` — MediaTek GPU

---

## 14. Testing & verification checklist

### Import flow
- [ ] Pick HLO PDF → analyzing steps → PDF editor appears
- [ ] Trace/adjust boundary → place ≥3 pins with Places search
- [ ] Confirm → satellite map with animated boundary reveal
- [ ] Mission review sheet → official boundary persisted

### Mission map
- [ ] PDF overlay visible with opacity slider
- [ ] Fit boundary → camera fits once; tune icon appears
- [ ] Layers drawer closes on outside tap
- [ ] GPS auto-center only once at launch

### Fine-tune
- [ ] Enter tune mode → map locked, gestures adjust PDF
- [ ] Twist rotate without crash (bearing stays 0–360)
- [ ] Opacity slider works during fine-tune
- [ ] Confirm saves → boundary updates; cancel restores

### Build
- [ ] `.\run-debug.ps1` on USB Android
- [ ] Hot reload (`r`) for Dart-only changes
- [ ] Full rebuild after `pubspec.yaml` or native plugin changes

---

## 15. Related specification documents

| Doc | Topic |
|-----|-------|
| `docs/PRODUCT_ARCHITECTURE_SPEC.md` | Overall product architecture |
| `docs/MISSION_MAP_UX.md` | Map-first UX contract |
| `docs/DISCOVERY_ENGINE_SPEC.md` | Discovery candidate lifecycle |
| `docs/MISSION_KNOWLEDGE_ENGINE.md` | Intelligence package schema |
| `docs/ARCHITECTURE_FREEZE.md` | Frozen architectural decisions |
| `docs/SPATIALVERIFY_APP_MANUAL.md` | User-facing manual |

---

## 16. Quick commands

```powershell
# Primary Android dev (from mobile/)
.\run-debug.ps1

# Faster reconnect to running app
.\run-debug.ps1 -Attach

# Dart-only, skip Gradle
.\run-debug.ps1 -NoBuild

# After plugin/native changes
.\run-debug.ps1 -Clean -Pub
```

**Google Maps key:** set in `mobile/android/local.properties`:
```
GOOGLE_MAPS_API_KEY=your_key_here
```

---

## 17. Mental model for the next AI

1. **Everything mission-related flows through `HlbLocalState` in Hive** — not Drift.
2. **The map is the product** — PDF is an overlay on satellite, not the main canvas.
3. **`hasOfficialBoundary` is the main feature flag** — unlocks navigation, fine-tune, placement tools.
4. **`ImageBounds` + `uvRing` together define PDF placement** — changing bounds recomputes GPS boundary ring.
5. **Google Maps ground overlays are strict** — bearing must be normalized; overlay IDs should be stable during gesture updates.
6. **Firebase login is required** — sync and multi-device backup need a signed-in user.
7. **Building placement is map crosshair-based** — not a separate camera discovery screen.

When continuing work, read **`mission_game_map_screen.dart`** and **`layout_georef_wizard_screen.dart`** first for UI state, then **`local_mission_import_service.dart`** for persistence semantics.
