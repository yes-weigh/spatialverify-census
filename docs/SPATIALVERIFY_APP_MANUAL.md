# SpatialVerify — Field Enumerator Manual

**App name:** SpatialVerify  
**Purpose:** Guide census enumerators through their **House Listing Block (HLB)** on a live map. The app helps you align the official layout PDF, walk to the correct starting corner, mark buildings and landmarks, and review a draft field map.

**Important:** This app does **not** collect census household data (names, demographics, etc.). It is a **map and navigation tool** only. Actual census enumeration happens in your official census system.

---

## 1. What you need before starting

| Requirement | Why |
|-------------|-----|
| Android phone with GPS | Live location, walk path, building pins |
| Location permission **Allow all the time** or **While using** | Map follow-me and navigation |
| Camera permission | Discovery walk (building marking) |
| Official **HLO layout PDF** for your HLB | Boundary and PDF overlay |
| Google Maps configured (release APK) | Satellite map, PDF overlay, bike/walk route to start |

**Install the APK:** Copy `app-release.apk` to the phone and open it, or install via USB with `adb install -r app-release.apk`. Allow installation from unknown sources if prompted.

On first launch, grant **Location** and **Camera** when asked. The app briefly shows **Finding your location…** while it gets a GPS fix, then opens the map centered on **you** (blue dot).

---

## 2. One HLB per enumerator

SpatialVerify is built for **one enumerator → one HLB**:

- You do **not** type an EB code or HLB name when starting.
- The app **creates or reuses** your single mission automatically.
- Your **EB number is read from the HLO PDF** (printed in the map sidebar, e.g. `0595`). Until you import the PDF, the header may show a generic label like **HLB**.
- There is no separate “choose mission source” screen — you go straight to **Import HLO PDF**.

If you already have work in progress, opening the app returns you to **your map** for that block.

---

## 3. App home screen

When you open SpatialVerify:

| Situation | What you see |
|-----------|--------------|
| **Active HLB in progress** | Full-screen **mission map** with gamified HUD (quests, layers, action buttons) |
| **No setup yet** | **Map lobby** centered on your GPS, with **Import HLO PDF** |

The map is always the main view. Controls appear as semi-transparent panels in the corners (game-style HUD). On launch, the map **follows your location** — it does not jump to the HLB boundary until you tap **Fit boundary** or start navigation.

---

## 4. The four main quests

The orange **Quest** banner (top-left) tells you what to do next:

| Quest | Meaning |
|-------|---------|
| **Import HLO PDF & draw boundary** | You have not set up the official HLB boundary yet |
| **Reach NW start corner** | Boundary is ready; go to the official north-west entry point |
| **Walk & mark buildings on video** | You are at (or near) the start; begin the discovery walk |
| **Complete field map coverage** | Buildings are being marked; fill gaps and finish walking the block |

Progress bar (when boundary exists) shows **% mapped** based on coverage, roads walked, and targets completed.

---

## 5. Step-by-step workflow

### Step A — Import your HLO PDF (first time)

1. From the **map lobby**, tap **Import HLO PDF**.  
   *(If you already have an active mission but no boundary, tap **Import PDF** on the mission map instead.)*
2. The **layout georeference wizard** opens — there is no EB code form.
3. Tap **Choose HLO PDF** and select your official HLO file.  
   *(Optional: **Photograph printed map** if you only have a paper copy.)*
4. The app reads the **EB number from the PDF** and traces the **white HLB border** automatically.

You then continue with boundary alignment (Step B).

### Step B — Align pins and confirm the boundary

On the **PDF editor** screen:

1. Review the **red traced boundary** on your HLO sheet.
2. Add **numbered control pins** on the PDF (landmarks, road junctions, etc.).
3. Use the **bottom HUD** for each pin:
   - Tap a **pin chip** to select it.
   - **Search** for the matching real-world place (Google Places).
   - Use the **arrow nudge pad** (2 / 5 / 10 / 20 px steps) to fine-tune pin position on the PDF.
4. When at least **three pins are matched** and the boundary has **3+ points**, tap **Show on satellite map**.
5. On satellite view, watch the **boundary draw** animation. Open the **review sheet** and confirm.
6. **Align corners** (if needed):
   - Tap a blue corner pin, then use the **arrow pad** (bottom-left) to nudge in **0.5–5 m** steps on the ground.
   - **Lock** two corners, then **Save** when aligned.
7. Tap to confirm when the review sheet appears.

**Result:** Red dotted **HLB boundary** on the map + optional **PDF overlay** aligned to ground. The top-left title updates to your real HLB code (e.g. **HLB 0595**).

### Step C — Navigate to the NW start corner

Census blocks are walked from the **north-west corner** (official start point).

1. On the mission map, tap **Go to start** (bottom-right, blue).
2. A **blue bike/walk route** appears from your location to the green **start marker**.
3. Follow the **turn banner** at the bottom (distance, ETA, current step).
4. When within ~25 m of the start, a banner offers **START CAPTURE**.

You can tap **Stop nav** anytime to cancel routing.

### Step D — Discovery walk (mark buildings)

1. Tap **Start capture** (green) or **START CAPTURE** after arriving at the start.
2. The **camera screen** opens:
   - Point the camera at buildings and structures as you walk.
   - The app suggests detections; tap to **confirm** or **reject**.
   - Confirm **building type** (pucca / kutcha / non-residential), **CN number**, and **house count** when prompted.
   - Your **walk path** is recorded on GPS (breadcrumbs every ~30 s).
3. Use the **mini-map** on the camera screen to see where you are inside the boundary.
4. When finished for the session, go **back** to the main map.

**Result:** Orange **building pins** and green **walk path** appear on the live map.

### Step E — Review the draft census map

1. On the mission map, tap **Draft map** (bottom-right, purple).
2. A **bottom sheet** shows the schematic draft map (buildings, landmarks, serpentine order).
3. Tap the **expand** icon for the full **Draft HLB Map** screen (export to PDF optional).

This draft is for **field review and correction**, not official census submission by itself.

---

## 6. Map HUD reference

### Top-left — Status

- HLB code (e.g. **HLB 0595** — from your PDF after import)
- Buildings count and distance walked
- **Quest** objective
- **Progress** bar (% mapped)

### Top-right — Layers & menu

**Layers button** (stack icon) opens:

| Layer | What it shows |
|-------|----------------|
| **Basemap** | Hybrid · Satellite · Map · Terrain |
| **HLB boundary** | Red dotted polygon |
| **PDF overlay** | Official HLO sheet on the ground |
| **Blue pins** | Observation / intelligence regions |
| **Buildings** | Confirmed structure pins (orange) |
| **Walk path** | Your GPS trail (green dashed) |
| **Route** | Navigation line to start |
| **Start marker** | NW corner entry point |

**PDF opacity** slider appears when PDF overlay is on (5%–95%).

**Other top-right buttons:**

| Button | Action |
|--------|--------|
| **Fit boundary** (crosshair) | Zoom map to fit HLB + markings |
| **Basemap** (quick toggle) | Cycle Hybrid → Satellite → Map → Terrain |
| **Menu** (☰) | Dashboard, replay, gaps, reorient, classic hub |

Google Maps’ own **My location** button is also available to re-center on your blue dot.

### Bottom-right — Primary actions

| Button | When it appears |
|--------|-----------------|
| **Draft map** | Always |
| **Import PDF** | No boundary yet |
| **Go to start** | Boundary set, not at start |
| **Stop nav** | During navigation |
| **Start capture** | At start or ready to walk |
| **Listing** | After at least one building discovered |

---

## 7. Mission menu (☰)

| Item | Purpose |
|------|---------|
| **Dashboard** | Discovery stats and analytics |
| **Replay** | Replay your walk and map build-up |
| **Coverage gaps** | Areas not yet walked or verified |
| **Reorient boundary** | Fine-tune boundary after confirm (layout-map source only) |
| **Classic hub** | Older card-based discovery screen (same data) |

The **Projects** folder icon (top-right on lobby or map) opens the project list — rarely needed in normal field use when you have one HLB.

---

## 8. Reorienting the boundary

If the boundary shifted slightly after confirmation:

1. Menu → **Reorient boundary**
2. Full-screen adjust map (same as wizard adjust mode)
3. Select a corner → nudge with **↑ ↓ ← →** pad → **Lock** two corners → **Save**

---

## 9. Map legend

| Symbol | Meaning |
|--------|---------|
| Red dotted line | HLB boundary |
| Semi-transparent sheet | Official PDF overlay |
| Blue marker | Observation region pin |
| Green marker | NW start / navigation destination |
| Orange marker | Confirmed building |
| Blue thick line | Navigation route |
| Green dashed line | Your walk path |
| Blue dot | Your current GPS location |

---

## 10. Tips for accurate field work

1. **Stand still briefly** when placing PDF control pins or locking boundary corners.
2. **Use Hybrid basemap** outdoors; switch to **Satellite** if you need clearer roofs.
3. **Lower PDF opacity** (30–50%) when matching boundary to hedges, walls, or roads.
4. Use the **bottom search bar** on the PDF editor — match each pin to a well-known landmark for better alignment.
5. **Walk the block systematically** (serpentine NW → SE) so building numbers stay in order.
6. **Confirm only what you see** — reject false camera detections.
7. Check **Coverage gaps** before leaving the HLB.
8. Open **Draft map** anytime to compare with the official PDF overlay.

---

## 11. Troubleshooting

| Problem | What to try |
|---------|-------------|
| Map is blank / grey | Ensure Google Maps API key is in the build; check mobile data or Wi‑Fi |
| No GPS / location stuck | Enable location services; go outdoors; grant location permission |
| Map not centered on you | Wait for **Finding your location…** to finish; tap Google **My location** |
| Route not showing | Tap **Go to start** again; move until GPS fixes; check internet for Directions API |
| PDF overlay misaligned | Menu → **Reorient boundary** or re-run georef with better control pins |
| Wrong or missing HLB code | Re-import the official HLO PDF; code is taken from the PDF sidebar |
| Camera black screen | Grant camera permission; close other camera apps |
| Buildings not on map | Return to main map after confirming in camera; enable **Buildings** layer |
| Need to start over | Use **Reorient boundary** or re-import PDF; contact support before uninstalling |

**Standalone mode:** The release APK runs **offline-first**. Mission data is stored on the device. Sync to a backend only applies when a server is configured in the build.

---

## 12. Data on your device

The app stores locally for your HLB:

- Official boundary polygon and start point  
- Layout PDF image and alignment  
- EB code parsed from the HLO PDF  
- Building and landmark pins with GPS  
- Walk breadcrumbs and gap resolutions  
- Draft map for review  

Uninstalling the app may delete this data unless backed up by your deployment process.

---

## 13. Quick reference — typical day

```
Open app → Map centered on your GPS
    ↓ (first time — no boundary yet)
Import HLO PDF → EB code read from PDF → Trace boundary → Match pins → Confirm on satellite
    ↓
Go to start → Follow route → Arrive NW corner
    ↓
Start capture → Walk block → Confirm buildings
    ↓
Draft map → Coverage gaps → Re-walk if needed
    ↓
(Optional) House listing phase in app when mapping complete
```

**Resume next day:** Open app → same HLB map picks up where you left off.

---

## 14. Support & version

- **App:** SpatialVerify (Flutter mobile)  
- **Release APK:** `mobile/build/app/outputs/flutter-apk/app-release.apk`  
- **Package ID:** `com.spatialverify.spatialverify`

For technical setup (API keys, debug builds), see `mobile/run-debug.ps1` and `mobile/android/local.properties`.

---

*This manual describes the map-first enumerator experience (single HLB, PDF-only setup, no manual EB entry). Features may vary slightly by build configuration (standalone vs server-connected).*
