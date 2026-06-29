# Event Catalog

**Version:** 1.0  
**Status:** Execution contract — update when adding events  
**Audience:** Every engineer touching field capture, import, or pipeline  

This document is the **contract between services**. Architecture docs say *why*; this says *what happens* for each event.

## Event record template

| Field | Description |
|-------|-------------|
| **Producer** | Who emits (mobile Discovery, Mission Knowledge import, supervisor UI) |
| **Payload** | Required fields for `schemaVersion` |
| **Evidence created** | Envelope appended to EvidenceStore |
| **Facts expected** | Ephemeral facts from Fact Engine |
| **Reasoning expected** | Knowledge graph mutations |
| **Projection builders affected** | Which caches invalidate/rebuild |

**Rule:** Projection builders read **Knowledge Graph or Evidence only** — never another projection.

---

## Import & boundary

### `mission_imported@1`

| | |
|-|-|
| **Producer** | Mission Knowledge Engine (HLO import) |
| **Payload** | `{ regions: [{ id, confidence?, lat?, lng? }], boundary?: … }` |
| **Evidence** | One envelope on `aggregateType: mission` |
| **Facts** | `RegionPredicted` per region |
| **Reasoning** | Mission → PREDICTED; regions created |
| **Projections** | `WorldProjection` |

### `boundary_accepted@1`

| | |
|-|-|
| **Producer** | Mission Review UI |
| **Payload** | `{}` or `{ source: 'enumerator_confirmed' }` |
| **Facts** | `BoundaryAccepted` |
| **Reasoning** | Boundary aggregate → VALIDATED |
| **Projections** | `WorldProjection` |

### `boundary_adjusted@1`

| | |
|-|-|
| **Producer** | Adjust boundary UI |
| **Payload** | `{ ring: …, transform?: … }` |
| **Facts** | (future) `BoundaryAdjusted` |
| **Reasoning** | Boundary geometry update; regions reclip |
| **Projections** | `WorldProjection` |

---

## Discovery walk

### `walk_started@1`

| | |
|-|-|
| **Producer** | Discovery Hub |
| **Payload** | `{ sessionId }` |
| **Facts** | — |
| **Reasoning** | Walk session active (future) |
| **Projections** | `ReplayProjection` (future) |

### `breadcrumb_recorded@1`

| | |
|-|-|
| **Producer** | GPS stream |
| **Payload** | `{ lat, lng, accuracy?, sessionId? }` |
| **Facts** | — |
| **Reasoning** | Coverage cell coverage (future) |
| **Projections** | `CoverageProjection` (future) |

### `gps_visit@1` / `entered_region@1`

| | |
|-|-|
| **Producer** | Proximity engine |
| **Payload** | `{ regionId, lat, lng }` |
| **Facts** | `VisitedRegion` |
| **Reasoning** | Region → OBSERVED if PREDICTED |
| **Projections** | `WorldProjection`; `CoverageProjection` (future) |

### `camera_opened@1`

| | |
|-|-|
| **Producer** | Discovery camera |
| **Payload** | `{ regionId, sessionId }` |
| **Facts** | — |
| **Reasoning** | Camera session bound (future) |
| **Projections** | `ReplayProjection` (future) |

### `photo_captured@1`

| | |
|-|-|
| **Producer** | Discovery camera |
| **Payload** | `{ regionId, photoHash, uri? }` |
| **Facts** | `PhotoCaptured` |
| **Reasoning** | Supports validation evidence chain |
| **Projections** | `ReplayProjection` (future) |

---

## Region validation

### `region_confirmed@1` ✅ implemented

| | |
|-|-|
| **Producer** | Discovery confirm tap |
| **Payload** | `{ regionId, lat?, lng?, photoHash? }` |
| **Facts** | `StructurePresent`, optional `PhotoCaptured` |
| **Reasoning** | Region → VALIDATED; Building created VALIDATED |
| **Projections** | `WorldProjection` |

### `region_rejected@1` ✅ implemented

| | |
|-|-|
| **Producer** | Discovery reject |
| **Payload** | `{ regionId, reason? }` |
| **Facts** | `StructureAbsent` |
| **Reasoning** | Region → REJECTED |
| **Projections** | `WorldProjection` |

### `region_ignored@1` ✅ implemented

| | |
|-|-|
| **Producer** | Discovery ignore |
| **Payload** | `{ regionId }` |
| **Facts** | `RegionIgnored` |
| **Reasoning** | Region → IGNORED; freshness decay eligible |
| **Projections** | `WorldProjection` |

---

## Gaps (planned)

### `gap_detected@1`

| | |
|-|-|
| **Producer** | Reasoning Engine (system) |
| **Payload** | `{ gapId, gapType, referenceId }` |
| **Reasoning** | GapOpen, GapPriority |
| **Projections** | `CoverageProjection` |

### `gap_resolved@1`

| | |
|-|-|
| **Producer** | Coverage Gaps UI |
| **Payload** | `{ gapId, resolution, narrative?, photoHash? }` |
| **Facts** | `GapInvestigated` |
| **Reasoning** | Gap → resolved |
| **Projections** | `CoverageProjection`, `WorldProjection` |

---

## Listing & closure (planned)

### `building_classified@1`

| | |
|-|-|
| **Producer** | Classification UI |
| **Payload** | `{ buildingId, structureType }` |
| **Reasoning** | Building → CLASSIFIED |
| **Projections** | `WorldProjection`, `ListingProjection` |

### `listing_completed@1`

| | |
|-|-|
| **Producer** | House listing form |
| **Payload** | `{ censusEntityId, buildingId, formRef }` |
| **Reasoning** | Census entity → LISTED |
| **Projections** | `ListingProjection` |

### `mission_completed@1` / `mission_audited@1`

| | |
|-|-|
| **Producer** | Supervisor / submit flow |
| **Reasoning** | Mission rollup states |
| **Projections** | All; freeze evidence append (policy) |

---

## Domain events (consequences)

Reasoning emits **domain events** — not evidence, not facts. Graph Builder applies them. Projections subscribe to graph (built from events) or to event streams for Replay.

| Domain event | Triggered by fact | Graph effect | Projections |
|--------------|-------------------|--------------|-------------|
| `RegionPredicted` | RegionPredicted | Region created PREDICTED | World, Replay |
| `RegionObserved` | VisitedRegion | Region → OBSERVED | World, Replay |
| `RegionValidated` | StructurePresent | Region → VALIDATED | World, Replay |
| `BuildingCreated` | StructurePresent | Building VALIDATED | World, Replay |
| `RegionRejected` | StructureAbsent | Region → REJECTED | World, Replay |
| `RegionIgnored` | RegionIgnored | Region → IGNORED | World, Replay |
| `BoundaryValidated` | BoundaryAccepted | Boundary VALIDATED | World, Replay |
| `MissionProgressChanged` | any progress fact | mission aggregateVersion++ | Replay, Metrics |

Pipeline: `Evidence → Facts → Reasoning → Domain Events → Graph Builder → Projections`

---

```
POST /api/v1/mission/ebs/:ebId/evidence            → append envelope, run pipeline
GET  /api/v1/mission/ebs/:ebId/world               → WorldProjection
GET  /api/v1/mission/ebs/:ebId/replay              → ReplayProjection ✅
GET  /api/v1/mission/ebs/:ebId/evidence/integrity  → hash chain audit ✅
GET  /api/v1/mission/ebs/:ebId/metrics/flow        → flow timing metrics ✅
GET  /api/v1/mission/ebs/:ebId/evidence            → list evidence
```

---

## Adding a new event

1. Add row to this catalog (all columns).
2. Add `evidenceType` + validator in `EvidenceValidator`.
3. Add Fact Engine case(s) if atomic.
4. Add Reasoning Engine case(s) if derived.
5. List projection builders affected — update builders only, never cross-projection reads.
6. Add `ReplayInvariantTest` fixture event.

**End of Event Catalog v1.0.**
