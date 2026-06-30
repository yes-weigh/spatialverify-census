# Mission Map UX Specification

> **Implementation status:** Partially implemented — georef wizard, satellite map, and PDF overlay match this doc. Building placement uses a **map crosshair**, not camera validation. See [`AI_HANDOFF_CURRENT_STATE.md`](./AI_HANDOFF_CURRENT_STATE.md).

**Version:** 1.0  
**Status:** Frozen UX contract — implementation guide for mobile  
**Parent:** [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md)  
**Related:** [`MOBILE_EVIDENCE_TRANSITION.md`](./MOBILE_EVIDENCE_TRANSITION.md), [`ARCHITECTURE_FREEZE.md`](./ARCHITECTURE_FREEZE.md)  

---

## Design principle

> **The satellite map is always the main canvas.**  
> The HLO PDF is the import artifact — not the daily interface.

The enumerator should feel immediately after import:

> **"This is my area in the real world."**

Not: *"This is an uploaded PDF."*

Reference feeling: **Google Maps navigation**, not a government data-entry app.

---

## Import flow (6 steps)

### Step 1 — Import Official HLO Mission

```
Import Official HLO Mission
[ Choose HLO PDF or satellite image ]
```

Copy: PDF decodes boundary, metadata, roads — user never lives in the PDF viewer.

### Step 2 — Analyzing (stepped progress)

```
Detecting Boundary…
Extracting Roads…
Finding Observation Regions…
```

Full-screen dark overlay; satellite map loads underneath when GPS/bounds known.

### Step 3 — Full-screen satellite map

- **Esri World Imagery** (or Google/Mapbox satellite when licensed)
- Centered and zoomed to HLB boundary
- **No PDF overlay** by default

### Step 4 — Animated reveal (Prediction Mode)

Sequence on satellite canvas:

1. **Boundary draws itself** (green line, route-style animation) → "Boundary complete"
2. **Roads fade in** (if available from intelligence)
3. **Observation regions fade in one-by-one** (grey/blue prediction markers)
4. Water / landmarks last (subtle)

Colors in **Prediction Mode:**

| Layer | Color |
|-------|--------|
| Boundary | Green stroke |
| Regions | Grey / blue (hypothesis) |
| Roads | Yellow tint |

### Step 5 — Mission Review (bottom sheet on map)

```
HLB 0595
Expected Regions    84
Roads               17
Landmarks           5
Mission Confidence  92%

[ LOOKS CORRECT ]  [ Adjust ]
```

Map stays visible behind sheet — never navigate away from satellite.

### Step 6 — Mission Mode (after Looks Correct)

Transition: Prediction Mode → **Mission Mode**

| Layer | Color |
|-------|--------|
| Boundary | Green (solid) |
| Regions (remaining) | Grey |
| Confirmed buildings | Green |
| You | Blue dot |
| Roads walked | Yellow |
| Start point | Green pin |

---

## During discovery walk

Satellite remains full canvas (Discovery Hub → map-first where implemented):

```
🟢 Boundary
🟡 Roads walked
⚪ Remaining regions
🟢 Confirmed buildings
🔵 You
```

Region confirm: grey → green with brief ✓ animation.

End of mission: entire HLB visually complete (green coverage, no red gaps) — glanceable "I finished."

---

## Official HLO PDF access

**Do not** show PDF after import unless requested.

App bar action:

```
📄 View Official HLO Map
```

Opens **split view**:

| Official HLO PDF | Live satellite |
|------------------|----------------|
| Source document  | Validated world |

---

## Map modes

```dart
enum MissionMapMode {
  prediction,  // import reveal — hypotheses visible
  mission,     // post-confirm — field validation
}
```

`WorldRepository` / map widget reads projection state; UI does not branch on online vs offline source.

---

## Non-goals (this spec)

- Replacing flutter_map with Mapbox globally (satellite tiles sufficient for v1)
- Showing PDF as primary canvas
- Percentage-only completion (prefer visual map completeness)

---

## Implementation files

| File | Role |
|------|------|
| `mission_satellite_map.dart` | Satellite canvas, layers, animation hooks |
| `layout_georef_wizard_screen.dart` | Import → analyze → reveal → review |
| `discovery_hub_screen.dart` | Map-first discovery entry (future) |
| `world_repository.dart` | Projection source abstraction (future) |

**End of Mission Map UX Specification v1.0.**
