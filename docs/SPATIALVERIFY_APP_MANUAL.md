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
| Official **HLO layout PDF** for your HLB | Boundary and PDF overlay |
| Google Maps configured (release APK) | Satellite map, PDF overlay, bike/walk route to start |
| **Firebase account** (provided by your supervisor) | Sign in and cloud backup of mission data |

**Install the APK:** Download from your organization's SpatialVerify page, copy `app-release.apk` to the phone, or install via USB with `adb install -r app-release.apk`. Allow installation from unknown sources if prompted.

On first launch, **sign in** with your email and password, then grant **Location** when asked. The app briefly shows **Finding your location…** while it gets a GPS fix, then opens the map centered on **you** (blue dot).

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
| **Mark buildings on the map** | Use the crosshair to place buildings, features, and roads |
| **Complete field map coverage** | Fill gaps and finish walking the block |

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

1. Open the **More** menu (☰ on the placement bar, or top-right menu).
2. Tap **Navigate to NW corner**.
3. A **blue bike/walk route** appears from your location to the green **start marker**.
4. Follow the **turn banner** at the bottom (distance, ETA, current step).

You can cancel navigation from the turn banner when finished.

### Step D — Mark buildings on the map

1. Pan and zoom the map so the **center crosshair** is over a structure or road.
2. Choose a tool on the bottom bar:
   - **Building** — residential or non-residential structure
   - **Feature** — temple, shop, landmark, etc.
   - **Road** — trace a road segment with multiple points
3. Tap **Place building** / **Place feature** / **Start road**, then confirm details in the sheet (type, house count, name).
4. Your **walk path** is recorded on GPS as you move (breadcrumbs).

**Result:** Orange **building pins**, feature markers, and road lines appear on the live map.

### Step E — Review the draft census map

1. Open **More** (☰) → **HLB layout map**, or use the layout map entry from the menu.
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
| **More** (☰) | Re-import PDF, fine-tune overlay, navigate to NW, layout map, dashboard, replay, gaps, language, projects |

### Bottom — Placement bar (when mapping)

| Control | Action |
|---------|--------|
| **Building / Feature / Road** | Select what the crosshair will place |
| **Place** | Confirm placement at crosshair and open detail sheet |
| **More** (☰) | Same menu as above |

Google Maps’ own **My location** button is also available to re-center on your blue dot.

---

## 7. Mission menu (☰)

| Item | Purpose |
|------|---------|
| **Re-import HLO PDF** | Run georef wizard again (when boundary exists) |
| **Fine-tune PDF overlay** | Nudge PDF alignment on satellite map |
| **Navigate to NW corner** | Turn-by-turn route to start point |
| **HLB layout map** | Draft schematic map (bottom sheet) |
| **Download HLB map PDF** | Export draft map as PDF |
| **House listing** | Building-by-building listing phase (after buildings placed) |
| **Dashboard** | Discovery stats |
| **Walk replay** | Replay your walk and map build-up |
| **Coverage gaps** | Areas not yet walked or verified |
| **Switch language** | English / Malayalam / Hindi |
| **Projects** | Project list (rarely needed for single-HLB use) |

---

## 8. Realigning the boundary

If the boundary shifted after confirmation:

1. More menu → **Re-import HLO PDF** (opens georef wizard in realign mode), or use **Fine-tune PDF overlay** for small PDF shifts only.
2. On the adjust map, select a corner → nudge with the arrow pad → **Lock** corners → **Save**.

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
5. **Walk the block systematically** (serpentine NW → SE) while placing buildings at the crosshair.
6. **Confirm only what you see** — correct mistakes by placing updated markers.
7. Check **Coverage gaps** before leaving the HLB.
8. Open **HLB layout map** anytime to compare with the official PDF overlay.

---

## 11. Troubleshooting

| Problem | What to try |
|---------|-------------|
| Map is blank / grey | Ensure Google Maps API key is in the build; check mobile data or Wi‑Fi |
| No GPS / location stuck | Enable location services; go outdoors; grant location permission |
| Map not centered on you | Wait for **Finding your location…** to finish; tap Google **My location** |
| Route not showing | More → **Navigate to NW corner** again; check internet for Directions API |
| PDF overlay misaligned | More → **Fine-tune PDF overlay** or re-import with better control pins |
| Wrong or missing HLB code | Re-import the official HLO PDF; code is taken from the PDF sidebar |
| Buildings not on map | Enable **Buildings** layer; confirm you tapped **Place** after moving crosshair |
| Cannot sign in | Check email/password; contact supervisor for account |
| Data not on second device | Sign in with same account; wait for sync when online |

**Cloud sync:** When signed in and online, mission data syncs to Firebase. Work continues offline; changes upload when connectivity returns.

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
Sign in → Open app → Map centered on your GPS
    ↓ (first time — no boundary yet)
Import HLO PDF → EB code read from PDF → Trace boundary → Match pins → Confirm on satellite
    ↓
More → Navigate to NW corner → Follow route
    ↓
Place buildings/features/roads with crosshair → Walk block
    ↓
HLB layout map → Coverage gaps → Re-walk if needed
    ↓
(Optional) House listing phase when mapping complete
```

**Resume next day:** Open app → same HLB map picks up where you left off.

---

## 14. Support & version

- **App:** SpatialVerify (Flutter mobile)  
- **Release APK:** `mobile/build/app/outputs/flutter-apk/app-release.apk`  
- **Package ID:** `com.spatialverify.spatialverify`

For technical setup (API keys, debug builds), see `mobile/run-debug.ps1` and `mobile/android/local.properties`.

---

*This manual describes the map-first enumerator experience (single HLB, PDF setup, Firebase sign-in, crosshair placement). OTA updates are delivered automatically when your supervisor publishes a new build.*
