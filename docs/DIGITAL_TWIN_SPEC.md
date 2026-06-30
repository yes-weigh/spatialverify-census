# Digital Twin Specification (World Model)

> **Implementation status:** Target architecture — **not in the shipping app**. World model, graph, and projection pipeline described here are not implemented. Current state is `HlbLocalState` in Hive + Firestore sync (see [`AI_HANDOFF_CURRENT_STATE.md`](./AI_HANDOFF_CURRENT_STATE.md)).

**Version:** 1.3  
**Parent:** [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) v1.0 (frozen)  
**Status:** Living specification — authoritative for evidence, reasoning, graph, and projections  
**Audience:** Backend engineers, mobile engineers, auditors, AI agents  

---

## Document purpose

**Evidence is the core.** The Knowledge Graph is **canonical derived state** (persisted). Projections are **disposable caches** from **independently versioned projection builders** — there is no single reducer.

1. **Three persistence classes** — evidence, graph, projections
2. **Fact Engine and Reasoning Engine** — atomic facts vs derived knowledge
3. **Knowledge Graph** — canonical semantic state (persist)
4. **Projection pipeline** — independent builders, independent versions
5. **Knowledge Freshness, lifecycle, export**
6. **Implementation phases** (§12)

Behavioral contracts in scope. Schemas live in **code**.

---

## 1. Evidence-first architecture

### 1.1 Three persistence classes

| Layer | Mutable | Rebuildable | Source of truth |
|-------|---------|-------------|-----------------|
| **Evidence Log** | Append-only | No | **Yes** |
| **Knowledge Graph** | Recomputed when evidence or engine versions change | Yes (from evidence) | **Derived canonical** |
| **Projections** | Cache refresh | Yes (from Knowledge Graph) | No |

```
Evidence          →  immutable
Knowledge Graph   →  canonical derived truth (persist this)
Projections       →  optimized views (delete freely)
```

**Rebuild tests:**

1. Delete all projections → rebuild from Knowledge Graph → identical read models.
2. Delete graph + projections → replay evidence through Fact + Reasoning engines → identical graph → rebuild projections.

### 1.2 Processing pipeline (no single reducer)

```
Evidence Log
    → Fact Engine v(x)           → Facts
    → Reasoning Engine v(y)      → Knowledge Graph  (PERSIST)
    → Projection Pipeline:
          WorldProjection v(a)
          CoverageProjection v(b)    ← independently versioned
          ListingProjection v(c)
          ReplayProjection v(d)
          ExpectationsProjection v(e)
          LearningProjection v(f)
```

**Reasoning Engine** subsumes inference, business rules, temporal policy, statistics, and ML-assisted logic. Legacy text may say "Inference Engine."

### 1.3 Compiler pipeline

```
Evidence → Facts → Reasoning → Knowledge Graph → Projection builders → Read models
```

### 1.4 Example: coverage is reasoned, not factual

```
Evidence:  gps_breadcrumb × 200, gps_visit at region 18
Facts:     VisitedRegion, WalkSessionActive
Reasoning: RegionKnowledge OBSERVED, CoverageCellKnowledge covered,
           MissionCoverageKnowledge 87%, GapPriority HIGH
Projection: CoverageProjection v(b) → heatmap
```

### 1.5 Mission Execution writes evidence only

```
Confirm Region → POST /evidence → Fact Engine → Reasoning → Graph persisted
              → WorldProjection builder → GET /world
```

### 1.6 Projection builders

| Builder | Built from |
|---------|------------|
| `WorldProjection` | Knowledge Graph + geometry |
| `CoverageProjection` | Coverage + gap knowledge |
| `ListingProjection` | Building + census knowledge |
| `ReplayProjection` | Evidence log (may bypass graph) |
| `ExpectationsProjection` | Expectations domain + graph |
| `LearningProjection` | Evidence + expectations + graph |

**Digital Twin** = legacy name for `WorldProjection`.

---

## 2. Twin Evolution

This section describes **how one HLB grows from import to audit export**. It is the lifecycle missing from the root spec.

### 2.1 End-to-end lifecycle (narrative)

```
Import HLO PDF
      │
      ▼
Twin created (bootstrap from Official Mission Package)
      │
      ▼
84 Observation Regions (PREDICTED) + boundary + roads + water
      │
      ▼
Enumerator reviews Mission Knowledge → boundary VALIDATED
      │
      ▼
Enumerator walks HLB (GPS breadcrumbs → OBSERVED on proximity)
      │
      ▼
Region 18 — camera + confirm → Building created (VALIDATED)
      │
      ▼
3 Census Houses classified and listed inside building (LISTED)
      │
      ▼
Coverage heatmap updates — cell transitions unvisited → covered
      │
      ▼
Gap detected (road segment without nearby validation)
      │
      ▼
Gap investigated — evidence attached — resolution recorded
      │
      ▼
Mission Completion Index crosses threshold
      │
      ▼
Listing phase completes — all required census entities LISTED
      │
      ▼
Supervisor review — twin state COMPLETE
      │
      ▼
Twin frozen (immutable write barrier)
      │
      ▼
Audit export (PDF/JSON bundle with evidence chain)
      │
      ▼
Learning feedback queued (prediction vs reality for next mission)
```

### 2.2 Phase breakdown

#### Phase A — Import and bootstrap

**Trigger:** Enumerator selects official HLO PDF for assigned HLB.

**Twin mutations:**

1. Create twin root bound to EB id
2. Attach `document` evidence (source hash, parser version, timestamp)
3. Write boundary geometry (`PREDICTED` → pending review)
4. Write observation region footprints from Spatial CV (`PREDICTED`)
5. Write road graph, water, vegetation, landmark candidates
6. Write neighbour HLB references (metadata, not geometry)
7. Set mission-level knowledge: `PREDICTED`

**Human gate:** Mission Review screen. Enumerator must accept boundary or adjust before field walk unlocks.

**Failure modes:**

- Wrong HLB metadata vs assignment → block import with explicit mismatch
- Boundary not detected → `needs_review`; manual adjust required
- Zero regions → warn but allow walk (manual discovery path)

#### Phase B — Boundary validation

**Trigger:** Enumerator taps "Looks Correct" or completes Adjust flow.

**Twin mutations:**

1. Boundary knowledge → `VALIDATED`
2. Append `enumerator_confirmed` evidence on boundary entity
3. Coverage tessellation initialized inside boundary
4. Discovery Hub unlocks

**Invariant:** Coverage analysis uses **validated** boundary only.

#### Phase C — Discovery walk

**Trigger:** Enumerator starts Discovery Walk from Hub.

**Twin mutations (continuous):**

1. GPS breadcrumb stream → `gps_visit` evidence on twin (mission-level)
2. Proximity to region → region `OBSERVED` (if was `PREDICTED`)
3. Camera open near region → bind session to `region_id`
4. Confirm → promote to Building (`VALIDATED`), link region → building
5. Reject → region `rejected` knowledge (remains on twin for audit)
6. Ignore → region `ignored` (excluded from completion numerator, retained for audit)

**Coverage side effects:**

- Heatmap cells mark `partial` or `covered` from breadcrumb density
- Road coverage increments when path intersects road segment buffer
- Open gaps may auto-close when region confirmed nearby

#### Phase D — Building and census entities

**Trigger:** Region confirmed or manual discovery at GPS.

**Twin mutations:**

1. Create **Building** entity with geometry from region (or manual pin)
2. Building knowledge → `VALIDATED`
3. Enumerator classifies structure type → `CLASSIFIED`
4. For each census house inside structure:
   - Create **Census Entity** child of Building
   - Listing form save → entity `LISTED`
5. Building operational status → `visited` / `completed`

**Critical distinction:** One Building, many Census Entities. A single roof may contain multiple households (pucca + shop + servant quarter). Never collapse census houses into building geometry.

#### Phase E — Gap resolution

**Trigger:** Coverage engine flags spatial inconsistency (e.g. road with no nearby validation, interior cell unvisited).

**Twin mutations:**

1. Create **Gap** entity referencing observation region, road segment, or coverage cell
2. Gap knowledge → `PREDICTED` (system) → `OBSERVED` (enumerator assigned)
3. Investigation walk → attach photo, GPS, narrative evidence
4. Resolution enum: `building_found` | `no_building` | `not_accessible` | `investigated`
5. Gap knowledge → `VALIDATED` or `COMPLETE`
6. If `building_found`, may spawn new region → building path

**Zero Exclusion:** Every gap must reach a documented resolution before mission `COMPLETE`.

#### Phase F — Mission completion

**Trigger:** Completion Index ≥ threshold AND open high-priority gaps = 0 AND listing requirements met (product rules).

**Twin mutations:**

1. Mission knowledge → `COMPLETE`
2. Lock mapping-phase writes (configurable: supervisor override)
3. Listing phase may continue if not already done

#### Phase G — Freeze and audit

**Trigger:** Supervisor approves submission OR enumerator submits for audit (workflow-dependent).

**Twin mutations:**

1. Mission knowledge → `AUDITED`
2. **Freeze:** no further mutations except admin correction (new evidence chain, never silent edit)
3. Generate export bundle:
   - Twin snapshot JSON
   - Evidence files (photos, hashes)
   - Human-readable PDF summary
   - Prediction vs reality delta report

#### Phase H — Learning handoff

**Trigger:** Post-freeze async job.

**Output:** Feedback records consumed by [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md) learning loop — not stored as mutable twin state.

### 2.3 Concurrent access rules

| Actor | Allowed during active mission | Allowed after freeze |
|-------|------------------------------|----------------------|
| Enumerator (field) | Read/write discovery, listing, gaps | Read only |
| Supervisor | Read + approve + override gap | Read + export |
| System (CV replay) | No silent overwrite | N/A |
| Learning pipeline | Read-only snapshot | Read-only snapshot |

Offline-first: mobile holds authoritative twin partition until sync merge. Server merge is **evidence-ordered**, not last-write-wins on knowledge state.

---

## 3. Knowledge States

### 3.1 State chain

Knowledge States apply to **twin entities** and **mission-level rollup**. They are richer than legacy `hypothesis | observed | confirmed`.

```
UNKNOWN
   │
   ▼
PREDICTED     ← CV, document parser, or system inference
   │
   ▼
OBSERVED      ← GPS proximity, camera session, breadcrumb coverage
   │
   ▼
VALIDATED     ← explicit human confirmation (structure exists, boundary accepted)
   │
   ▼
CLASSIFIED    ← structure type assigned (residential, commercial, shed, etc.)
   │
   ▼
LISTED        ← census entity form persisted (census houses only)
   │
   ▼
COMPLETE      ← all required work done for entity or mission scope
   │
   ▼
AUDITED       ← frozen, export-ready, supervisor accepted
```

### 3.2 State semantics by entity type

| Entity | Typical terminal state | Notes |
|--------|------------------------|-------|
| Boundary | VALIDATED → AUDITED | Must be VALIDATED before discovery |
| Observation Region | VALIDATED or rejected | Rejected stays on twin; never LISTED |
| Building | CLASSIFIED → COMPLETE | Listing ops parallel |
| Census Entity | LISTED → COMPLETE | Official census record |
| Gap | VALIDATED → COMPLETE | Resolution evidence required |
| Road segment | OBSERVED (coverage) | No LISTED state |
| Mission (root) | COMPLETE → AUDITED | Rollup of children |

### 3.3 Legacy mapping

| Legacy status | Knowledge State |
|---------------|-----------------|
| `hypothesis` | PREDICTED |
| `observed` | OBSERVED |
| `confirmed` | VALIDATED |
| `rejected` | PREDICTED + rejection evidence (terminal for region) |

Migration: store both during transition; UI shows Knowledge State.

### 3.4 Transition rules

1. **Forward only** by default — corrections append superseding evidence, may move state backward only via supervisor correction record
2. **Every transition** requires ≥1 evidence record (see §5)
3. **No skip** — cannot jump PREDICTED → VALIDATED without OBSERVED unless supervisor documents exception (e.g. office review of satellite)
4. **Analytics:** state timestamps enable funnel metrics per mission

### 3.5 Rollup logic (mission-level)

Mission knowledge state is the **minimum** of critical paths:

- Boundary ≥ VALIDATED
- All non-ignored regions ≥ VALIDATED or rejected with evidence
- All gaps ≥ COMPLETE
- All required census entities ≥ LISTED
- Completion Index ≥ threshold

Then mission → COMPLETE. AUDITED requires explicit approval event.

---

## 4. Entity Relationship Model

After six months, nobody remembers implicit relationships. This section is the canonical ER reference.

### 4.1 Diagram

```
                    ┌─────────────────┐
                    │  Official       │
                    │  Mission        │
                    │  (import pkg)   │
                    └────────┬────────┘
                             │ bootstraps
                             ▼
                    ┌─────────────────┐
                    │  Digital Twin   │◄─────── Evidence (many)
                    │  (root)         │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
  │  Boundary   │    │  RoadGraph  │    │  Neighbours │
  │  (1 per     │    │  (segments  │    │  (refs)     │
  │   twin)     │    │   + nodes)  │    └─────────────┘
  └──────┬──────┘    └──────┬──────┘
         │ contains         │ intersects
         ▼                  ▼
  ┌─────────────────────────────────┐
  │     Observation Region (N)       │
  └──────────────┬──────────────────┘
                 │ creates (on VALIDATED)
                 ▼
         ┌─────────────┐
         │  Building   │
         └──────┬──────┘
                │ contains (1..N)
                ▼
         ┌─────────────┐
         │ Census      │
         │ Entity      │
         └─────────────┘

  Evidence ──derives──► Fact ──drives──► Knowledge ──materializes──► Twin (recomputed)
```

**Observation Region** is deliberately assumption-free: satellite says only *"something deserves inspection."* After validation, the same region may become house, shed, shop, church, transformer, tree, or empty plot — classification is a separate fact, not baked into the region name.

### 4.2 Relationship table

| From | Relationship | To | Cardinality | Notes |
|------|--------------|-----|-------------|-------|
| Official Mission | bootstraps | Mission Knowledge | 1:1 | Import artifact |
| Mission Knowledge | seeds | Twin computation | 1:1 | Initial facts from CV/document |
| Evidence | derives | Fact | N:M | Fact Engine |
| Fact | input to | Reasoning | N:M | Reasoning derives knowledge |
| Knowledge | materializes | Twin entity | — | Recomputed snapshot |
| Digital Twin | contains | Boundary | 1:1 | Derived view |
| Boundary | contains | Observation Region | 1:N | Spatially inside polygon |
| Boundary | contains | Coverage Cell | 1:N | Derived tessellation |
| Observation Region | may become | Building | N:0..1 | Via `StructurePresent` fact |
| Building | contains | Census Entity | 1:N | Houses ≠ building |
| Building | has lineage from | Observation Region | 0..1:1 | Promotion link |
| Road Segment | adjacent to | Observation Region | N:M | For gap heuristics |
| Gap | references | Region / Road / Cell | N:1 | Polymorphic ref |
| Evidence | attached to | Context entity | N:1 | Append-only |
| GPS Breadcrumb | covers | Coverage Cell | N:M | Derived |
| Landmark | near | Observation Region | N:M | Navigation aid |
| Twin V(n) | compares to | Twin V(n-1) | 1:1 | Historical diff (same HLB, later mission) |

### 4.3 Referential integrity rules

1. **Census Entity** must have parent Building id; Building must be ≥ VALIDATED
2. **Building** created from region must retain `source_region_id`
3. **Gap** cannot reference entity outside twin boundary
4. **Evidence** cannot orphan — every record links to entity id + twin id
5. **Delete** is soft-delete via rejection evidence, never hard remove from audit graph

### 4.4 Geometry vs knowledge separation

**Observation Region**

- Geometry: footprint polygon, centroid, confidence from CV
- Knowledge: PREDICTED → OBSERVED → VALIDATED/rejected
- Purpose: visit target before structure commitment

**Building**

- Geometry: may inherit region footprint or refined polygon after field refine
- Knowledge: VALIDATED → CLASSIFIED → COMPLETE
- Purpose: confirmed structure container

**Census Entity (Census House)**

- Geometry: optional point-in-building (unit location); not independent footprint by default
- Knowledge: LISTED → COMPLETE
- Purpose: official enumeration record (forms, residents, amenities)

**Anti-pattern:** Storing household count only on Building without Census Entity children. Always materialize houses as entities when listed.

---

## 5. Fact Engine and Reasoning Engine

### 5.1 Two-stage derivation + graph persistence

```
Evidence  →  Fact Engine v(x)  →  Facts
          →  Reasoning Engine v(y)  →  Knowledge Graph  (PERSIST)
          →  Projection builders v(a…f)  →  Read models  (DISPOSABLE CACHE)
```

| Stage | Pure function? | Persist? |
|-------|----------------|----------|
| Fact Engine | Yes | Facts may be logged for audit; derivable from evidence |
| Reasoning Engine | Yes (given engine version) | **Knowledge Graph — yes** |
| Projection builders | Yes (given builder version) | Cache only |

**Rule:** Multi-fact or policy conclusions → **Reasoning Engine**, not Fact Engine.

### 5.2 Why persist the Knowledge Graph

- Graph queries simpler than replaying full evidence for every read
- Reasoning can build on prior knowledge nodes incrementally
- Projections stay lightweight — builders read graph, not raw evidence
- Projections rebuild from graph without re-running expensive reasoning (until evidence changes)

Graph is **not** source of truth. It is **canonical interpretation** of evidence under `(fact_engine_version, reasoning_engine_version)`.

### 5.3 Example: region confirmation

```
Evidence → Facts: StructurePresent, PhotoCaptured
Reasoning → Graph: BuildingKnowledge VALIDATED, RegionKnowledge superseded
WorldProjection builder → GET /world
```

### 5.4 Example: gap priority (reasoning ≠ pure inference)

```
Facts: VisitedRegion, StructureAbsent, RoadGraph context
Reasoning: GapKnowledge { open }, GapPriorityKnowledge { priority: HIGH }  ← policy
CoverageProjection builder → gap list sorted by priority
```

### 5.5 Core fact types (atomic)

| Fact type | Source evidence |
|-----------|-----------------|
| `RegionPredicted` | satellite |
| `VisitedRegion` | gps_visit |
| `StructurePresent` | confirm + photo + gps |
| `StructureAbsent` | reject |
| `RegionIgnored` | ignore |
| `BoundaryAccepted` | enumerator_confirmed |
| `PhotoCaptured` | photo |
| `CensusFormSubmitted` | listing_form |
| `GapInvestigated` | gap_resolution |

Not facts: `CoverageComplete`, `GapOpen`, `GapPriority`, `MissionComplete`.

### 5.6 Core reasoning outputs (derived)

| Knowledge | Depends on |
|-----------|------------|
| `BuildingValidated` | `StructurePresent` + boundary check |
| `CoverageCellCovered` | breadcrumbs + tessellation |
| `GapOpen` / `GapResolved` | coverage rules + gap facts |
| `GapPriority` | policy over gap + road + region knowledge |
| `MissionCoverageComplete` | thresholds over cells, roads, gaps |
| `KnowledgeStale` | freshness rules (§6) |

Reasoning rules version with **Reasoning Engine v(y)** — independent of projection versions.

### 5.7 Projection builder contract

Each builder reads **Knowledge Graph only** (Replay reads Evidence directly). **Never read another projection** — no `CoverageProjection → WorldProjection` dependencies.

**Facts are ephemeral** — deterministic compiler tokens regenerated on replay; persist Evidence + Knowledge Graph only.

Each builder:

```
WorldProjection_v2(graph) → world_read_model
CoverageProjection_v3(graph) → coverage_read_model
```

- **Deterministic** — same graph + same builder version → same projection
- **Independent versioning** — bump one builder without bumping others
- **Invalidation** — new evidence → re-run Fact + Reasoning → update graph → invalidate affected projection caches only
- **Conflict** — incompatible facts → `ConflictKnowledge` + supervisor queue

Historical replay: evidence log + Reasoning v2.1 → new graph → run selected projection builders.

### 5.8 Traceability (audit)

Every UI field: `projection field → graph node → reasoning rule → fact(s) → evidence id(s)`.

If that chain cannot be produced, hidden state was introduced.

---

## 6. Knowledge Freshness

Generalizes "confidence decay." **Evidence never ages.** **Inferred knowledge** is temporal.

### 6.1 What ages (freshness dimensions)

| Dimension | Ages? | Notes |
|-----------|-------|-------|
| GPS evidence | Never | Immutable log |
| Photo hashes | Never | Immutable log |
| Official HLO source | Never | Immutable provenance |
| User confirmation evidence | Never | Immutable human authority |
| Building knowledge confidence | Yes | Decay if not reinforced |
| Road inference confidence | Yes | Decay without re-walk |
| Landmark knowledge | Yes | |
| Alignment knowledge | Yes | Cross-mission drift |
| Expectations | Yes | Stale vs new CV/history — see [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md) |
| Classification certainty | Yes | May require reclassification in later mission |

Each aging dimension carries `freshness_score`, `last_reinforced_at`, optional `stale_after`.

### 6.2 Reinforcement

Confirm + photo + GPS at region → reinforcement restores freshness on related building/region knowledge. Freshness affects **priority** (revisit queues, supervisor flags), not evidence deletion.

### 6.3 Cross-mission freshness

Twin V2 for same HLB: V1 evidence remains in history. Inherited predictions start with decayed freshness unless revalidated. Change reports surface stale knowledge explicitly.

---

## 7. Historical rebuild

### 7.1 Lifecycle across censuses

```
Mission 2026  →  Evidence Log V1  →  Reasoning v2.1  →  Graph  →  Projections (frozen)
Mission 2032  →  Evidence Log V2  →  Reasoning v2.1  →  Graph  →  Projections (frozen)
                         │
                         ▼
              Compare projections + replay(V1 evidence, Reasoning v3)  →  Change Report
```

Same HLB id; new evidence stream per mission. **Historical rebuild:** replay 2026 evidence with 2032 inference rules — no re-fielding required for rule improvements.

### 7.2 Change report questions (examples)

- Which buildings disappeared?
- Which roads widened or shifted?
- Which canals were filled or dug?
- Which new settlements appeared?
- Which regions were repeatedly ignored then confirmed?

### 7.3 Platform evolution

This transforms the platform from a **single-mission census tool** into a **long-term spatial knowledge system**. Census remains the first deployment; historical diff is the long-term moat alongside Learning.

### 7.4 Storage model (conceptual)

```
HlbWorldHistory {
  hlb_id
  versions: [
    { mission_year, twin_snapshot_id, frozen_at, expectation_snapshot }
  ]
  latest_diff: ChangeReport | null
}
```

Diff computed from materialized twin snapshots — not from ad hoc table diffs.

---

Diff computed from projections — or by replaying both evidence logs through a common reducer version.

---

## 8. Projection pipeline (read models)

Graphs are **not** stored on a twin object. Each projection builder materializes its read model from the Knowledge Graph (or evidence, for Replay).

| Builder | API | Cache |
|---------|-----|-------|
| `WorldProjection` | `GET /world` | Disposable |
| `CoverageProjection` | `GET /coverage` | Disposable |
| `ListingProjection` | `GET /listing` | Disposable |
| `ReplayProjection` | `GET /replay` | Disposable (may read evidence directly) |
| `ExpectationsProjection` | `GET /expectations` | Disposable |
| `LearningProjection` | export job | Disposable |

Legacy `GET /twin` → `GET /world`.

**Invalidation:** new evidence → update graph → rebuild only builders whose graph slice changed (or all, if simpler initially).

---

## 9. Completion and export

### 9.1 Mission Completion Index (reference)

Weighted rollup (exact weights in product config):

- Boundary validated: gate (binary)
- Regions validated or rejected: %
- Road coverage: %
- Interior heatmap covered: %
- Gaps resolved: binary
- Ignored suggestions: informational penalty

Stored on twin as snapshot + component breakdown for supervisor UI.

### 9.2 Freeze semantics

When twin → AUDITED:

1. Set `frozen_at`, `frozen_by`
2. Reject all mutating APIs except admin correction workflow
3. Snapshot hash for export integrity

### 9.3 Export bundle contents

- Twin JSON (full graph)
- Evidence manifest (files + SHA-256)
- PDF human summary (counts, map thumbnails, gap table)
- Prediction vs reality report (regions predicted vs buildings validated)
- Parser/CV version stamps

---

## 10. Sync and offline

### 10.1 Partition strategy

Mobile holds:

- Twin read model (recomputed locally from evidence + facts)
- Write queue: **evidence only** (facts derived on device or server)
- Local photos until upload

Server merges by:

1. Evidence totally ordered by `(created_at, device_seq)`
2. Fact derivation (Fact Engine version stamped)
3. Twin = reducer(all evidence) — deterministic
4. Conflict: incompatible facts → supervisor queue

### 10.2 No last-write-wins on knowledge

Two enumerators must not silently overwrite each other's confirmations. Evidence append + reducer preserves both; conflicts surface in supervisor UI.

---

## 11. Planned vs implemented

| Capability | Status |
|------------|--------|
| EvidenceStore (append-only) | Planned |
| Fact Engine | Planned |
| Reasoning Engine | Planned |
| Knowledge Graph persistence | Planned |
| Independent projection builders | Planned |
| Projection APIs | Planned — legacy `/twin` partial |
| Knowledge Freshness | Planned |
| PATCH endpoints | Legacy — replace with POST /evidence |

---

## 12. Implementation phases (infrastructure-first)

Implement **vertically through infrastructure**, not feature-by-feature:

| Phase | Deliverable | Done when… |
|-------|-------------|------------|
| **1** | `EvidenceStore` | Append-only; nothing else required |
| **2** | `Fact Engine` | Deterministic pure function over evidence |
| **3** | `Reasoning Engine` | Deterministic pure function over facts + context |
| **4** | `Knowledge Graph Builder` | Persists canonical graph; version stamped |
| **5** | Projection builders | World, Coverage, Listing, Replay, Expectations, Learning — each versioned |
| **6** | Evidence-only writes | `POST /evidence` replaces `PATCH /building`; UI reads projections |

Do not skip phases. Phase 6 before Phase 1 introduces hidden state.

---

## Appendix A — Glossary (twin-specific)

| Term | Definition |
|------|------------|
| Twin bootstrap | Initial graph write from Official Mission Package |
| Promotion | Observation Region → Building on VALIDATED |
| Freeze | Write barrier after AUDITED |
| Reasoning Engine | Facts + context → Knowledge Graph (policy, rules, stats, ML) |
| Projection builder | Graph → one versioned read model |
| Census Entity | Official census house record; child of Building |

---

## Appendix B — Related documents

- [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) — vision, philosophy, field workflow
- [`DISCOVERY_ENGINE_SPEC.md`](./DISCOVERY_ENGINE_SPEC.md) — Mission Execution; field evidence and facts
- [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md) — expectations, delta, freshness

**End of Digital Twin Specification v1.3.**
