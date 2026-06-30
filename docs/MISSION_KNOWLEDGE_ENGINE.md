# Mission Knowledge Engine Specification

> **Implementation status:** Partially implemented — PDF import and georef exist in the app. Backend CV/intelligence pipeline and evidence packaging described below are **not built**. See [`AI_HANDOFF_CURRENT_STATE.md`](./AI_HANDOFF_CURRENT_STATE.md).

**Version:** 1.2  
**Parent:** [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) v1.0 (frozen)  
**Twin output:** [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md)  
**Field consumer:** [`DISCOVERY_ENGINE_SPEC.md`](./DISCOVERY_ENGINE_SPEC.md)  
**Status:** Living specification  
**Audience:** Backend engineers, CV/ML engineers, data platform  

---

## Document purpose

The **Mission Knowledge Engine** transforms an **Official HLO map** into **initial evidence and expectations** — the first entries on the evidence log and the seed for [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md).

This document covers import pipeline stages. It does **not** own expectations long-term or materialize the World Model directly.

**Naming:**

| Term | Meaning |
|------|---------|
| **Mission Knowledge Engine** | Domain orchestrator — document + spatial + packaging |
| **Spatial Intelligence Engine** | CV and geometry extraction subsystem |
| **Document Intelligence** | HLO metadata and layout parsing subsystem |

Avoid "Mission Intelligence Engine" in new docs and UI — it sounds like an implementation detail.

This document covers:

- Import pipeline stages
- Document Intelligence (HLO PDF)
- Spatial CV Engine (boundary-first)
- GPS alignment and Mission Review payload
- Initial evidence at import (document, satellite CV)
- Expectation snapshot seed → [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md)
- Learning loop (expectation vs reality delta)

---

## 1. Engine position in architecture

```
Official Mission (HLO PDF)
        │
        ▼
┌─────────────────────────────────────────────┐
│        Mission Knowledge Engine              │
│  Document Intelligence → Spatial CV          │
│         → Alignment → Knowledge Packaging    │
└─────────────────────┬───────────────────────┘
                      │ initial evidence appended
                      ▼
              Evidence Log (immutable stream)
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
 Expectations domain          Fact → Reasoning → Knowledge Graph (persist)
 (EXPECTATIONS_SPEC)                 │
         │                    Projection builders
         │                           ▼
         └──────── Delta ◄── Reality (projections)
                      │
                      ▼
                 Learning loop
```

Mission Knowledge **seeds** the log. Expectations domain **owns** planning and delta. **Projection builders** materialize read models from the persisted graph.

---

## 2. Input: Official HLO Map

### 2.1 Assumptions (primary path)

Official Census HLO export contains:

- Georeferenced satellite panel
- White/contrast HLB boundary polygon
- Left or margin panel with admin metadata
- Neighbour HLB labels on map edges
- Named roads, north arrow, scale bar
- Generation timestamp

### 2.2 Secondary path (sketch / non-standard)

Hand-drawn sketches may exist — landmark georef wizard — but **not** the critical path. Engine must degrade gracefully:

- Lower confidence scores
- Mandatory Mission Review adjust
- Fewer auto-predicted regions

### 2.3 Ingest responsibilities

1. Store immutable source blob (hash addressed)
2. Rasterize PDF pages at sufficient DPI for CV
3. Classify document layout variant (satellite official vs other)
4. Emit `document` evidence on twin

---

## 3. Document Intelligence

### 3.1 Purpose

Extract **deterministic administrative facts** and **layout structure** without requiring ML for critical metadata.

### 3.2 Extraction targets

| Field | Source region | Method |
|-------|---------------|--------|
| HLB number | Header/footer text band | OCR + regex |
| State, District, Village, Ward | Metadata panel | OCR + label anchors |
| Generated date | Footer | OCR + date parse |
| Neighbour HLB ids | Map margin text | OCR + pattern |
| North bearing | North arrow glyph | Geometry + OCR |
| Road names | Map annotations | OCR overlay on CV roads |
| Declared area | Metadata panel | OCR + unit parse |
| Legend | Margin | Template match |

### 3.3 Layout segmentation

Partition page into:

1. **Satellite panel** — feed to Spatial Intelligence Engine only
2. **Metadata panel** — OCR only; exclude from structure detection
3. **Decorative margins** — neighbour labels, logos

**Critical:** Structure detection never runs on metadata panel text blocks (false roof clusters).

### 3.4 Output: MissionDocumentMetadata

Attached to Official Mission Package and copied to twin document node.

Validation gate: extracted HLB must match enumerator assignment (or explicit override with supervisor evidence).

### 3.5 Planned enhancements

- PDF vector layer parse (when HLO exports vectors)
- Multi-page HLB stitching
- Language variants (regional scripts)

---

## 4. Spatial Intelligence Engine (CV)

### 4.1 Design principles

1. **Boundary first** — never analyze outside assigned HLB
2. **Deterministic** — same input → same output (versioned algorithms)
3. **Offline-capable** — no cloud ML on critical path
4. **Pluggable models** — ONNX behind stable interface; heuristics as fallback
5. **Observation regions, not buildings** — roof-like clusters only

### 4.2 Mandatory operation order

```
1. Detect boundary polygon (closed loop on satellite)
2. Mask to interior
3. Detect observation regions (texture / contour clusters)
4. Detect road segments (linear features)
5. Detect water bodies, canals
6. Detect vegetation patches
7. Infer landmark candidates (low confidence)
```

### 4.3 Boundary detection

**Input:** Satellite panel RGB  
**Output:** UV polygon ring, confidence score

Heuristics (current): high-contrast closed polyline (white boundary on imagery).  
Future: learned boundary detector with heuristic fallback.

**Failure:** confidence < threshold → Mission Review mandatory adjust.

### 4.4 Observation region detection

**Output per region:**

- `region_id` (stable within extraction version)
- Centroid UV
- Footprint polygon (approximate)
- Confidence score
- Feature tags (roof-like, shadow, etc.) — not building type

**Non-goals:** Household count, building use class, address.

### 4.5 Road graph extraction

- Centerline polylines in UV space
- Nodes at intersections and boundary crossings
- Merge with OCR road names from Document Intelligence when polyline proximity matches

### 4.6 Environmental layers

Water and vegetation reduce **expectation** of structures — used by gap heuristics in Discovery, not to delete regions automatically.

### 4.7 Output: CvExtractionResult

```
CvExtractionResult {
  version
  boundary: { ring_uv, confidence }
  observation_regions[]
  roads: { segments[], nodes[] }
  water_features[]
  vegetation_patches[]
  landmarks[]   // low confidence
  processing_ms
}
```

All geometry in **UV space** until alignment stage.

---

## 5. Alignment and georeferencing

### 5.1 Purpose

Project UV geometry to WGS84 for field GPS comparison.

### 5.2 Auto-align (primary)

**Inputs:**

- Boundary UV polygon
- Enumerator GPS seed at import (or last known near HLB)
- Optional: known road/name landmark from metadata

**Process:**

1. Estimate similarity/affine transform UV → lat/lng
2. Score alignment confidence from boundary shape vs satellite implied orientation
3. Project all regions, roads, water to GPS

### 5.3 Mission Review gate

Payload to mobile **Mission Review** screen:

```
MissionKnowledgeSnapshot {
  metadata
  boundary_gps
  region_count
  road_count
  water_count
  confidence: {
    boundary, structures, roads, alignment, overall
  }
  quality_label: excellent | good | needs_review
  summary_text
}
```

Enumerator actions:

- **Looks Correct** → evidence + fact `BoundaryAccepted` → twin recomputes with boundary VALIDATED
- **Adjust** → manual corner drag / shift → re-project → new evidence → facts → recompute

**No silent acceptance.**

### 5.4 Manual adjust

Adjust UI produces:

- `manual_adjust` evidence
- Updated transform matrix
- Re-clipped regions (drop outside new boundary with evidence)

---

## 6. Expectation seed (import)

At import, Mission Knowledge produces an **ExpectationSnapshot** and appends it as **expectation evidence**. Ongoing expectation merging, freshness, delta, and `GET /expectations` are owned by [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md).

Initial snapshot fields (examples): expected buildings (region count), road length, water crossings, coverage time, GPS complexity. Derived from CV + metadata at import time.

---

## 7. Import evidence bootstrap

After alignment + review acceptance, the engine **appends evidence** to the log — not projection patches:

| Evidence type | Content |
|---------------|---------|
| `document` | HLO parse result, hash, parser version |
| `satellite` | CV extraction payload (regions, boundary, roads) |
| `enumerator_confirmed` | Boundary accepted at Mission Review |
| `expectation_snapshot` | Initial ExpectationSnapshot ref |

Fact Engine + Reasoning Engine derive the Knowledge Graph; projection builders serve read APIs. See [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) §5, §12.

---

## 8. Mission Knowledge API (behavioral)

### 8.1 Import

- `POST /mission/import` — source file + eb_id + gps_seed
- Returns: job id or synchronous snapshot (size dependent)

### 8.2 Status

- `GET /mission/import/:id/status` — processing | ready | failed

### 8.3 Review

- `GET /mission/:eb_id/knowledge` — MissionKnowledgeSnapshot
- `POST /mission/:eb_id/boundary/accept`
- `POST /mission/:eb_id/boundary/adjust`

### 8.4 Re-run policy

Re-import same HLB:

- New evidence chain; does not delete prior frozen twin
- Active mission: supervisor policy for replace vs merge

---

## 9. Confidence model

### 9.1 Component scores

| Component | Drives |
|-----------|--------|
| boundary | Adjust prompt severity |
| structures | Region count trust |
| roads | Road coverage baseline |
| landmarks | Alignment validation |
| alignment | Overall georef trust |
| overall | Mission Review UI badge |

### 9.2 Quality labels

- **excellent** — all components above high threshold
- **good** — field walk recommended; minor warnings
- **needs_review** — adjust or supervisor before walk

Scores are **informational** — they do not auto-validate regions.

---

## 10. Learning Engine

### 10.1 Strategic role

Long-term moat — **the system predicts** via CV, heuristics, OCR, GIS rules, and learned models; reality is what the field proves:

```
Official Map (mission N)
        │
        ▼
Expectations + Predictions
        │
        ▼
Reality (recomputed twin, frozen)
        │
        ▼
Feedback (delta features)
        │
        ▼
Model / heuristic / expectation improvement
        │
        ▼
Next Mission (N+1) — better predictions + expectations
        │
        ▼
Historical diff (Twin V(n) vs V(n+1))
```

### 10.2 Feedback record (conceptual)

```
LearningFeedback {
  twin_id
  mission_id
  cv_version
  predicted_region_count
  validated_building_count
  rejected_region_count
  manual_discovery_count
  gap_count
  boundary_adjust_delta
  region_iou_distribution[]   // predicted vs validated geometry
  false_positive_regions[]    // rejected ids
  false_negative_regions[]    // manual discoveries
  geography_context: { district, urban_rural, ... }
  created_at
}
```

### 10.3 Use cases

| Signal | Improvement target |
|--------|-------------------|
| Systematic false positives on water edge | Water mask expansion |
| Boundary offset pattern in district X | Alignment calibration |
| Roof texture false clusters on tar roads | Region classifier |
| Neighbour label OCR errors | Document template update |

### 10.4 Privacy and governance

- Learning uses **aggregated** feedback across missions
- Individual household listing data **not** used in CV training
- Frozen twin exports may be anonymized for model training per org policy

### 10.5 Current implementation status

**Stub:** in-memory feedback collector. Production path:

1. Post-freeze job emits LearningFeedback
2. Queue to analytics store
3. Periodic retrain or heuristic tuning
4. Version bump on Spatial Intelligence Engine with rollback

---

## 11. Versioning and reproducibility

Every import stamps:

- `document_parser_version`
- `cv_engine_version`
- `alignment_algorithm_version`

Reproducibility requirement: given same source PDF + versions + GPS seed → identical UV extraction (deterministic CV).

Alignment may vary slightly with GPS seed — document in evidence.

---

## 12. Failure modes

| Failure | Engine behavior |
|---------|-----------------|
| PDF corrupt | Fail import; user retry |
| HLB mismatch | Block; show extracted vs assigned |
| No boundary | needs_review; manual digitize |
| CV timeout | Retry; fallback reduced resolution |
| GPS seed missing | Prompt enumerator; defer align |

All failures produce user-actionable messages, not stack traces.

---

## 13. Planned vs implemented

| Component | Status |
|-----------|--------|
| PDF rasterize + store | Partial |
| Document Intelligence OCR | Planned |
| Spatial CV heuristics | Implemented |
| ONNX models | Planned |
| GPS auto-align | Implemented (partial) |
| Mission Review API | Implemented |
| Expectation seed at import | Partial |
| Expectations bounded context | [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md) |
| Learning feedback pipeline | Stub |
| Historical expectation diff | Planned |
| Neighbour HLB warnings | Planned |

---

## Appendix A — Golden fixture

Use official sample `HLB_Map_0595.pdf` (HLB 0595) as regression fixture:

- Expected: boundary detected, non-zero regions, metadata HLB 0595
- CI: run CV on rasterized page; snapshot UV region count within tolerance

---

## Appendix B — Related documents

- [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) — product vision, Official Mission Package
- [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md) — expectations domain, delta, learning
- [`DISCOVERY_ENGINE_SPEC.md`](./DISCOVERY_ENGINE_SPEC.md) — field validation of predictions

**End of Mission Knowledge Engine Specification v1.2.**
