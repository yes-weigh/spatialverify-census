# Discovery Engine Specification (Mission Execution)

**Version:** 1.2  
**Parent:** [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) v1.0 (frozen)  
**World Model:** [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md)  
**Status:** Living specification  
**Audience:** Mobile engineers, CV engineers, field UX designers  

---

## Document purpose

**Mission Execution** is how enumerators validate the predicted world during the mapping phase. Discovery is the primary mapping-phase capability within Mission Execution.

Discovery **appends evidence only**. Facts, inferences, knowledge, and projections are derived server-side (or on-device with matching engine versions).

```
Observation  →  Evidence  →  Fact Engine  →  Reasoning Engine  →  Knowledge Graph  →  Projection builders
```

UI reads projections (`GET /world`, `/coverage`, …). Detail: [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) §1, §5, §8.

---

## 1. Discovery philosophy

### 1.1 Core rules (unchanged from root spec)

1. **The system predicts, human verifies** — Discovery never auto-confirms structures
2. **Observation Regions, not buildings** — until facts say otherwise; a region may become house, shed, shop, church, transformer, tree, or empty plot
3. **Camera validates, not detects** — camera confirms the region you're at
4. **Discovery before Listing** — mapping phase gates listing phase
5. **Coverage-first** — prove spatial completeness
6. **Zero Exclusion** — every gap resolves with evidence-backed facts

### 1.2 Discovery's job: append evidence

| User action | Evidence written | Downstream (not written by UI) |
|-------------|------------------|--------------------------------|
| Start walk | Walk session | Inference → coverage session active |
| Enter region proximity | `gps_visit` | Fact `VisitedRegion` → OBSERVED inference |
| Open camera | Camera session | Supports photo facts |
| Confirm | confirm + photo + gps bundle | Reasoning → BuildingValidated → WorldProjection |
| Reject | reject bundle | Reasoning → StructureAbsent |
| Ignore | ignore tap | Fact RegionIgnored → freshness decay |
| Resolve gap | gap bundle | Reasoning → GapResolved |
| GPS breadcrumb | breadcrumb | Reasoning → coverage knowledge (not a fact) |

Coverage complete is **reasoned** from breadcrumbs, roads, cells, gaps, and boundary — never written by the client.

---

## 2. Entry conditions

Discovery unlocks when:

1. Authenticated enumerator owns EB assignment
2. Official Mission Package imported
3. Boundary knowledge ≥ **VALIDATED** (Mission Review passed)
4. Twin snapshot available locally (offline-first)

EB phase must be `mapping` (or equivalent draft mapping state).

---

## 3. Discovery Hub

### 3.1 Purpose

Mission control for mapping — **not** a data entry screen. Answers: "What should I do next in this HLB?"

### 3.2 Data sources (all from twin)

| UI element | Twin query |
|------------|------------|
| Region count | `observation_regions where state >= PREDICTED` |
| Confirmed buildings | `buildings where state >= VALIDATED` |
| Completion Index | derived rollup (see twin spec §7) |
| Open gaps | `gaps where state < COMPLETE` |
| Ignored count | `regions where ignored = true` |
| Road / path metrics | coverage graph |
| Mission Knowledge summary | import snapshot counts (read-only) |

### 3.3 Primary actions

| Action | Behavior |
|--------|----------|
| **Start Discovery Walk** | GPS tracking + region proximity engine |
| **Draft Map** | Read-only or light-adjust map view |
| **Coverage Gaps** | Gap list sorted by priority |
| **Replay** | Timeline of evidence on map |
| **Transition to Listing** | Gated by completion rules |

### 3.4 Copy and UX

- "Validate Region 18" not "Confirm detection"
- Show AI confidence small; "Needs your confirmation" prominent
- Heatmap over raw percentages for spatial decisions

---

## 4. Discovery Walk

### 4.1 Walk session lifecycle

```
Start Walk
    │
    ├── Load serpentine suggestion (road graph + unvisited regions)
    ├── Begin GPS breadcrumb stream (configurable interval)
    ├── Proximity engine: nearest unvisited region
    │
    ▼
Approach region (< proximity threshold)
    │
    ├── Highlight region on map
    ├── Prompt: Open Camera / Confirm / Reject / Skip
    │
    ▼
Complete walk or pause
    │
    └── Session evidence closed; coverage graph updated
```

### 4.2 Serpentine ordering

**Goal:** Minimize backtracking for listing-phase efficiency.

**Inputs:**

- Road graph entry points
- Unvisited / OBSERVED regions
- Confirmed building adjacency (optional weight)

**Output:** Ordered region ids — **suggestion only**; enumerator may deviate.

### 4.3 GPS breadcrumbs

| Property | Rule |
|----------|------|
| Interval | Adaptive (motion-based); default ~5–10 m |
| Storage | Local queue → sync as evidence |
| Privacy | Scoped to mission boundary context |
| Coverage | Buffers intersect coverage cells → heatmap |

**Offline:** Full local persistence; no walk blocking on network.

### 4.4 Proximity engine

For each breadcrumb:

1. Point-in-polygon test against boundary (validated)
2. Distance to region centroids / footprints
3. If `< threshold` and region state = PREDICTED → transition OBSERVED + `gps_visit` evidence
4. Neighbour HLB warning if point near boundary edge (future: neighbour polygon refs)

Threshold configurable per environment (urban dense vs rural).

---

## 5. Observation region validation

### 5.1 Region states in discovery

```
PREDICTED ──gps/camera──► OBSERVED ──confirm──► VALIDATED (→ Building)
                │                │
                │                └──reject──► rejected (terminal)
                └──ignore──► ignored (terminal for completion)
```

### 5.2 Validation UI flow

1. Map shows region footprint + id ("Region 18")
2. Enumerator physically at location
3. Optional: open camera (binds session to `region_id`)
4. Actions:
   - **Confirm** — create Building, link region, classification prompt
   - **Reject** — "Not a structure" + optional photo
   - **Ignore** — "Skip for now" (counts against completion policy)

### 5.3 Manual discovery

When enumerator finds unmapped structure:

1. Long-press / "Add structure" at GPS
2. Creates manual Observation Region at pin → immediate confirm path
3. Same evidence rules as predicted regions

### 5.4 Classification (post-confirm)

Structure type selection moves Building VALIDATED → **CLASSIFIED**:

- Residential pucca / kutcha
- Commercial / shop
- Shed / ancillary
- Under construction
- Other (free text + photo encouraged)

Classification is **human authoritative**; CV may suggest in future but not commit.

---

## 6. Discovery Camera

### 6.1 Role: validator, not detector

Production path:

```
Enumerator selects region (or proximity auto-selects)
        │
        ▼
Camera opens WITH region context
        │
        ▼
Photo captured → evidence linked to region_id
        │
        ▼
Enumerator confirms/rejects structure
```

**Not** production path: run ONNX on every frame → auto-create buildings.

### 6.2 Camera session model

```
CameraSession {
  region_id          // required binding
  twin_id
  started_at
  photos[]           // each → Evidence
  ended_at
}
```

### 6.3 Overlay behavior

- Show region id and distance
- Optional: faint footprint overlay (map projection to camera — future AR path disabled in field-test builds)
- No bounding boxes from live detection in v1 field path

### 6.4 Future CV assist (non-blocking)

Optional low-confidence hints ("roof-like texture") — **display only**, never auto-confirm. Aligns with root spec AI philosophy.

---

## 7. Coverage system

### 7.1 Heatmap tessellation

1. Tessellate interior of validated boundary (grid or hex)
2. Each cell tracks: `unvisited` | `partial` | `covered` | `suspicious`
3. Update from breadcrumb density + region validations + road buffers

### 7.2 Coverage metrics

| Metric | Definition |
|--------|------------|
| Boundary coverage | Walk path within boundary / expected perimeter visit |
| Road coverage | Length of road graph within buffer of breadcrumbs |
| Interior coverage | Cells in `covered` / total cells |
| Structure coverage | VALIDATED regions / (PREDICTED - ignored) |

Completion Index combines weighted metrics (config in twin spec).

### 7.3 Suspicious cells

Flag cells where:

- High CV density predicted region but no OBSERVED visit
- Breadcrumbs pass through but no validation event
- Long time gap in walk through populated area

Surface in Gap list as **coverage_gap** type.

---

## 8. Gap detection and resolution

### 8.1 Gap types

| Type | Trigger |
|------|---------|
| `region_unvisited` | PREDICTED region, no OBSERVED before deadline/heuristic |
| `road_no_structure` | Road segment with no VALIDATED building within buffer |
| `coverage_hole` | Interior cell unvisited after walk pass |
| `prediction_mismatch` | High-confidence CV region rejected (learning signal) |
| `neighbour_fence` | GPS near boundary without intentional visit (warning) |

### 8.2 Gap entity (twin)

```
Gap {
  id
  twin_id
  gap_type
  reference: { entity_type, entity_id }
  priority: low | medium | high
  knowledge_state
  resolution: enum | null
  evidence[]
}
```

### 8.3 Resolution workflow

1. Gap appears on Hub + Coverage Gaps screen
2. Enumerator navigates to location
3. Investigate: photo + GPS + narrative
4. Select resolution:
   - **building_found** → spawn confirm path
   - **no_building** → document empty plot / vegetation
   - **not_accessible** → locked gate, etc.
   - **investigated** → other documented reason
5. Gap → COMPLETE + evidence

**Zero Exclusion:** Export blocked if any `high` priority gap open.

### 8.4 Gap priority rules

- Unvisited high-confidence region near road → high
- Interior coverage hole in dense cluster → high
- Ignored region → medium (policy)
- Neighbour fence warning → low (informational)

---

## 9. Replay

### 9.1 Purpose

Supervisor and enumerator review **what happened when** on the map.

### 9.2 Data source

Evidence graph ordered by timestamp:

- Breadcrumbs as polyline animation
- Confirm/reject pins
- Gap resolutions
- Photos as thumbnails on map

### 9.3 Use cases

- Audit trail demonstration
- Training replay for new enumerators
- Dispute resolution ("enumerator never visited sector 4")

---

## 10. Offline architecture

### 10.1 Local-first requirements

| Requirement | Behavior |
|-------------|----------|
| Start walk offline | Yes |
| Confirm/reject offline | Yes |
| Camera capture offline | Yes; photos queued |
| Gap resolution offline | Yes |
| Hub metrics | Computed from local twin |
| Sync | Background when connectivity returns |

### 10.2 Sync payload

Upload:

- Evidence records (ordered)
- State transitions (derived server-side from evidence preferred)
- Photo blobs → object storage

Download:

- Twin patches from other devices (if multi-enumerator — future)
- Supervisor flags

Conflict policy: see twin spec §8 — evidence-ordered reducer.

---

## 11. Spatial CV integration (discovery-time)

Discovery **consumes** CV output from import; it does not re-run full CV on device during walk (v1).

| CV artifact | Discovery use |
|-------------|---------------|
| Region footprints | Map overlays, proximity |
| Road graph | Serpentine, road coverage |
| Water / vegetation | Expectation context ("no structure expected in pond") |
| Boundary | All spatial tests |

**Adjust flow:** If enumerator adjusts boundary at Mission Review, regions re-clipped to new boundary — may invalidate out-of-boundary regions with evidence.

On-device CV assist (future): optional hint layer only.

---

## 12. API contracts (behavioral)

### 12.1 Read (projections)

Target API (migration from legacy twin endpoints):

- `GET /world` — WorldModelProjection (map, regions, buildings)
- `GET /coverage` — CoverageProjection (heatmap, gaps, completion index)
- `GET /listing` — ListingProjection
- `GET /replay` — ReplayProjection
- `GET /expectations` — ExpectationsProjection — see [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md)

Legacy: `GET /twin` → aliases `/world` during migration.

### 12.2 Write (evidence only)

Production path:

- `POST /evidence` — append only; immutable

Clients do **not** send facts, inferences, or projection patches. Offline: queue evidence; projections refresh on sync.

Admin / migration only:

- `PATCH` entity endpoints — deprecated; remove when reducer path complete

### 12.3 Walk session

- `POST walk/start`
- `POST walk/breadcrumb` (batch acceptable)
- `POST walk/end`

---

## 13. Error handling (field)

Errors must say **what to do next**:

| Condition | User message direction |
|-----------|------------------------|
| No GPS fix | "Move to open sky; walk continues when GPS ready" |
| Outside boundary | "You are outside HLB 0595 — return to boundary" |
| Camera permission denied | "Enable camera to photograph this region" |
| Sync failed | "Saved on device — will upload when online" |

Never show HTTP codes on field screens.

---

## 14. Planned vs implemented

| Feature | Status |
|---------|--------|
| Discovery Hub | Implemented (partial) |
| Walk + breadcrumbs | Partial |
| Region confirm → building | Partial (local HLB state) |
| Camera bound to region_id | Planned |
| Gap entity formal workflow | Partial |
| Heatmap UX | Conceptual / partial |
| Replay timeline | Planned |
| Serpentine suggestion | Planned |
| Neighbour HLB warnings | Planned |

---

## Appendix — Related documents

- [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) — entity model, knowledge states, evidence
- [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md) — how regions are predicted at import
- [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) — vision and field workflow overview

**End of Discovery Engine Specification v1.2.**
