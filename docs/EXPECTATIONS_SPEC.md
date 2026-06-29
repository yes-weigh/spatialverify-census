# Expectations Specification

**Version:** 1.0  
**Parent:** [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) v1.0 (frozen)  
**Related:** [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md), [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md)  
**Status:** Living specification — bounded context  
**Audience:** Backend engineers, data platform, supervisors  

---

## Document purpose

**Expectations** are what the system believes a mission *should* look like — and eventually **how to plan it** (enumerator count, duration, supervisor focus, rejection-risk blocks). **Reality** comes from projections over the evidence-backed Knowledge Graph. **Delta** drives supervisor UI and learning.

Expectations are a **first-class bounded context** — not owned by Mission Knowledge long-term.

```
Mission Knowledge  →  Expectations  →  Execution  →  Reality  →  Delta  →  Learning
```

---

## 1. Why a separate domain

Expectations will eventually come from many sources:

| Source | Example expectation |
|--------|---------------------|
| Spatial CV (import) | 84 observation regions |
| Document metadata | HLB area 1.2 km² |
| Historical mission (V(n-1)) | ~80 buildings in 2026 |
| Neighbouring HLBs | Higher density near border |
| Census statistics | Avg households per urban block |
| Satellite (non-HLO) | New roof clusters since last mission |
| GIS / demographics | Expected road length from OSM |

Mission Knowledge Engine produces **initial** expectations at import. Expectations domain **aggregates, versions, and compares** them over the mission lifecycle.

---

## 2. Expectation snapshot

```
ExpectationSnapshot {
  mission_id
  version                    // recomputed when sources change
  generated_at
  sources[]                  // { type, version, weight }

  expected_buildings: 84
  expected_road_length_km: 2.8
  expected_water_crossings: 3
  expected_coverage_time_hours: 5.2
  expected_gps_complexity: high | medium | low
  expected_gap_count: 12
  expected_listing_units: null    // after classification pass if inferrable

  freshness_score: 1.0            // ages — see Knowledge Freshness
}
```

Stored as **expectation evidence** at import (immutable snapshot ref) plus **mutable expectation knowledge** when sources are merged or decayed.

---

## 3. Reality (not owned here)

Reality metrics come from **projections** over the evidence log — never from UI counters:

| Metric | Projection source |
|--------|-------------------|
| Structures validated | `WorldModelProjection` |
| Road / interior coverage | `CoverageProjection` |
| Open gaps | `CoverageProjection` |
| Listing progress | `ListingProjection` |
| Walk duration | `ReplayProjection` + inference |

Expectations domain **reads** projections; it does not compute reality.

---

## 4. Delta and comparison

```
ExpectationsProjection {
  expected: ExpectationSnapshot
  actual:   { from CoverageProjection, WorldModelProjection, ... }
  delta: {
    buildings: { expected: 84, actual: 71, diff: -13 }
    road_coverage_pct: { expected: 100, actual: 87, diff: -13 }
    open_gaps: { expected_max: 12, actual: 4, ok: true }
    walk_hours: { expected: 5.2, actual: 3.1, flag: early_finish }
  }
  freshness: { expectation_stale: false, ... }
}
```

**API:** `GET /expectations` returns this projection.

Supervisor and Discovery Hub show delta when useful — field UI shows actionable subset only.

---

## 5. Freshness

Expectations **age** differently from evidence:

- Import expectations start at freshness 1.0
- New neighbour HLB data or historical replay may **supersede** with new snapshot + evidence ref
- Unreinforced expectations decay — stale expectations flagged, not deleted
- GPS, photos, HLO, user confirmations **never** decay (see twin spec §6)

---

## 6. Learning handoff

On mission freeze:

```
LearningFeedback {
  expectation_snapshot_id
  reality_projection_hashes
  delta_features
  geography_context
}
```

Feeds [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md) §10 and cross-mission change reports.

---

## 7. Integration points

| Producer | Consumes |
|----------|----------|
| Mission Knowledge Engine | Seeds initial ExpectationSnapshot at import |
| Historical missions | Prior snapshots; operational planning inputs |
| Census statistics / demographics | Enumerator staffing, duration estimates |
| Expectations Engine (this domain) | Merges sources, versions snapshots |
| Reasoning Engine | May use expectations as priors (non-binding) |
| ExpectationsProjection builder | Builds `GET /expectations` read model |
| Learning pipeline | Reads delta at freeze |

---

---

## 8. Operational planning (long-term)

Expectations become an **operational planning engine**, not just import-time prediction:

- How many enumerators does this HLB need?
- Which blocks will take longest?
- Which HLBs have high predicted rejection rates?
- Where should supervisors focus?

Sources expand beyond CV: historical missions, neighbour HLBs, census statistics, demographics, GIS. Mission Knowledge seeds initial snapshots; this domain owns merge, freshness, delta, and planning outputs.

---

## 9. Planned vs implemented

| Capability | Status |
|------------|--------|
| ExpectationSnapshot at import | Spec / partial in Mission Knowledge |
| Multi-source expectation merge | Planned |
| ExpectationsProjection API | Planned |
| Freshness on expectations | Planned |
| Learning delta export | Stub |

---

## Appendix — Related documents

- [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) — evidence, inference, projections
- [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md) — import pipeline seeding expectations
- [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) — root invariants

**End of Expectations Specification v1.0.**
