# SpatialVerify — Product & Architecture Specification

> **Implementation status:** Target architecture — **not in the shipping app**. The current product is Flutter + Hive/Firestore only (see [`AI_HANDOFF_CURRENT_STATE.md`](./AI_HANDOFF_CURRENT_STATE.md) and [`README.md`](../README.md)). No Node API, evidence pipeline, or camera discovery walk.

**Version:** 1.0 (frozen)  
**Document type:** Canonical product architecture — source of truth  
**Audience:** Engineers, designers, AI agents (Cursor, ChatGPT), future contributors  
**Status:** Frozen at v1.0. Subsystem detail lives in companion specs (see Appendix D).  
**First deployment:** Indian Census field enumeration (HLB / House Listing Block)  
**Platform class:** Evidence-driven spatial operating system with deterministic world-state reconstruction  
**Product framing:** Human-in-the-Loop Spatial Knowledge Platform (Census = first deployment)

---

## Document purpose

This specification defines **what the product is**, **why it exists**, **how Census field work maps to software**, and **how every major subsystem behaves**. It is written so that a new engineer can understand the entire system without reading prior conversations, Slack threads, or exploratory design notes.

Behavioral contracts, user journeys, architectural boundaries, and design rationale are in scope. **Implementation details live in code**; companion specs change only when subsystem *behavior* changes (see Appendix C).

**Companion specifications (authoritative for subsystem depth):**

| Document | Scope |
|----------|--------|
| [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) | Persistence classes, Reasoning Engine, projection pipeline, implementation phases |
| [`DISCOVERY_ENGINE_SPEC.md`](./DISCOVERY_ENGINE_SPEC.md) | Mission Execution — evidence capture, projection read APIs |
| [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md) | Import pipeline, initial prediction, learning loop |
| [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md) | Expectations domain — prediction, delta, learning |
| [`EVIDENCE_SPEC.md`](./EVIDENCE_SPEC.md) | Evidence bounded context — envelope, hash chain |
| [`EVENT_CATALOG.md`](./EVENT_CATALOG.md) | Execution contract — every event |
| [`PR_INVARIANTS.md`](./PR_INVARIANTS.md) | PR guardrails |
| [`ARCHITECTURE_FREEZE.md`](./ARCHITECTURE_FREEZE.md) | **Frozen** — pipeline locked; feature gate |
| [`MOBILE_EVIDENCE_TRANSITION.md`](./MOBILE_EVIDENCE_TRANSITION.md) | Mobile Phase A — WorldRepository |

---

## 0. Central architectural model

**Evidence is the source of truth.** Facts, the Knowledge Graph, and projections are **derived**. Projections are **disposable**; the Knowledge Graph is **canonical derived state** (rebuildable from evidence, but persisted). See §0.4.

> **System-wide invariant:** Every value visible in the system must be traceable to evidence through a deterministic chain of fact derivation, reasoning, and projection. If a developer cannot explain how a UI field traces back to evidence, they have introduced hidden state.

Most GIS platforms are **state-based** (store the current map). Most survey systems are **form-based** (store answers). This platform is **evidence-based** (store observations, derive facts, reason over knowledge, project optimized views).

### 0.1 Linear pipeline (no circular terminology)

```
Official Mission (HLO PDF)
        │
        ▼
Mission Knowledge (initial prediction)     ← import only; seeds first evidence
        │
        ▼
Evidence Stream                            ← append-only; immutable core
        │
        ▼
Fact Engine                                ← evidence → atomic facts
        │
        ▼
Reasoning Engine                           ← facts + context → derived knowledge
        │
        ▼
Knowledge Graph                            ← canonical derived semantic state (persisted)
        │
        ▼
Projection Pipeline                        ← independent builders (no single reducer)
        │
        ├── WorldProjection
        ├── CoverageProjection
        ├── ListingProjection
        ├── ReplayProjection
        ├── ExpectationsProjection
        └── LearningProjection
        │
        ▼
Mission Execution UI                       ← consumes projections; appends evidence only
```

There is **no single reducer.** Each projection builder evolves independently (e.g. `CoverageProjection v3` without bumping `ReplayProjection v1`).

### 0.2 Compiler analogy

```
Evidence  →  Facts  →  Reasoning  →  Knowledge Graph  →  Projection builders  →  Read Models
```

| Layer | Owns truth? | Disposable? |
|-------|-------------|-------------|
| Evidence Log | Yes (source) | Never |
| Knowledge Graph | Canonical derived | Rebuildable; **persist** |
| Projections | No | Yes — cache only |

### 0.3 Independent versioning

Engines and projections version **separately** — they change for different reasons:

| Component | Version example | Changes when… |
|-----------|-----------------|---------------|
| Fact Engine | v1.4 | New evidence types |
| Reasoning Engine | v2.1 | Rules, policy, ML-assisted logic improve |
| Knowledge Graph Builder | v2.1 | Tied to reasoning output schema |
| WorldProjection | v2 | Map UX / entity shape |
| CoverageProjection | v3 | Heatmap redesign |
| ReplayProjection | v1 | Unchanged while coverage evolves |
| LearningProjection | v7 | Export format for training |

Historical replay: same evidence log + updated **Reasoning Engine v2.1** → new Knowledge Graph → rebuild only projections that need it.

### 0.4 Three persistence classes

| Layer | Mutable | Rebuildable | Source of truth |
|-------|---------|-------------|-----------------|
| **Evidence Log** | Append-only | No | **Yes** |
| **Knowledge Graph** | Recomputed on new evidence | Yes (from evidence + engine versions) | **Derived canonical** |
| **Projections** | Cache refresh | Yes (from Knowledge Graph) | No |

This table resolves most implementation debates: never PATCH projections as authority; persist the graph; append evidence only on writes.

### 0.5 Critical invariants

1. **Write path:** Mission Execution **appends evidence only**.
2. **Read path:** Clients consume **projections** (`GET /world`, `/coverage`, …).
3. **Fact ≠ Reasoning:** `VisitedRegion` (fact) does not imply `CoverageComplete` (reasoned knowledge).
4. **Traceability:** Every UI-visible value → projection → knowledge → facts → evidence.
5. **Evidence immutable; knowledge temporal** — Knowledge Freshness in [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) §6.

Detail: [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md). Expectations: [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md). Implementation order: twin spec §12.

**Terminology:**

| Term | Meaning |
|------|---------|
| **Evidence Stream** | Append-only log — sole source of truth |
| **Fact Engine** | Evidence → atomic facts (deterministic, pure) |
| **Reasoning Engine** | Facts + context → knowledge (rules, policy, stats, ML — formerly "Inference Engine") |
| **Knowledge Graph** | Canonical derived semantic state — **persist**; not a projection |
| **Projection builder** | Knowledge Graph → one read model (independently versioned) |
| **Knowledge Freshness** | Temporal aging of knowledge — evidence never ages |

---

## 1. Vision

### 1.1 What this product is not

This is **not** a generic survey app. It is not a GIS editor. It is not an autonomous mapping drone. It is not a replacement for the enumerator. It is not a paper-form digitization tool with a map attached.

Survey apps collect points. GIS tools let experts construct geometry. This product does neither as its primary mode.

### 1.2 What this product is

SpatialVerify (working product name; see Section 1.5) is a **Human-in-the-Loop Spatial Knowledge Platform**.

The platform accepts an **official spatial mission** (for Census: the HLO-generated HLB map). **The system predicts** what exists inside that mission — using CV, heuristics, OCR, GIS rules, and learned models as appropriate — and **guides** a field worker to **validate** that prediction while collecting **evidence**. The output is a **verified World Model** (Digital Twin) of the assigned geographic unit with auditable proof that coverage was achieved.

Core philosophy:

> **The system predicts.**  
> **Human verifies.**  
> **System proves coverage.**

Prediction without verification is worthless in Census. Verification without prediction wastes enumerator time. Coverage proof without evidence fails audit.

### 1.3 Census as first deployment, not final product

Census is the **first customer** and the **hardest constraint set**:

- Zero exclusion: every structure inside the boundary must be found or explicitly ruled out with evidence.
- Official boundaries and administrative hierarchy are legally meaningful.
- Enumerators are not GIS professionals; they work under time pressure, often offline, often in heat and monsoon conditions.
- Supervisors and auditors require explainable completion, not black-box AI counts.

The architecture must generalize beyond Census:

- Any organization that assigns a **bounded geographic mission** with an **official map artifact** and requires **field validation with coverage proof** is a future customer.
- Census-specific terms (HLB, EB, Census House) are **domain labels** on generic concepts (mission unit, observation region, validated structure).

### 1.4 The strategic shift (Official HLO PDF)

Early design assumed enumerators might upload **hand-drawn sketches** requiring landmark-based georeferencing, control points, and affine alignment wizards.

Real Census artifacts — exemplified by official HLO PDF maps — are already:

- Georeferenced satellite imagery with visible ground truth
- Official HLB boundary polygons (typically white lines on imagery)
- Administrative metadata (State, District, Village, HLB number, area)
- Neighbouring HLB identifiers
- Named roads, north arrow, and official landmarks

Therefore the input is redefined:

| Old mental model | Correct mental model |
|------------------|----------------------|
| Upload image / PDF | **Import Official Census Mission** |
| Georeference manually | **Decode mission package** |
| Detect buildings | **Predict observation regions** |
| Configure mission | **Review mission knowledge** |
| Walk and search | **Validate predicted world** |

The HLO PDF is **not an input file**. It is an **official machine-readable mission package waiting to be decoded**. The PDF is the **container**; the application's internal object is the **Official Mission Package**.

### 1.5 Naming (product vs module)

The repository may retain the name **SpatialVerify** while the Census-facing module is conceptually **Mission Twin** or **Official Mission Import**. Long-term brand options include Mission Twin, HLB Navigator, FieldTwin, Census Mission OS. The architectural name that matters internally is **Official Mission Package** and **Digital Twin** — not screen names.

---

## 2. Understanding Census Field Work

### 2.1 Geographic and administrative units

**HLB (House Listing Block)**  
The smallest mappable unit assigned to an enumerator for house listing. It has a official boundary, an identifier (e.g. 0595), and a defined area. Everything inside the boundary is the enumerator's responsibility for completeness.

**Enumeration Block (EB)**  
Software/API term for the same unit as HLB in this product. An EB record tracks status, assigned enumerator, layout artifacts, discovery state, and listing progress.

**Official HLO PDF**  
Generated by the Census House Listing Operation (HLO) application. Contains high-resolution satellite imagery, the official white (or high-contrast) HLB boundary polygon, road names, neighbouring HLB numbers, north arrow, administrative header/footer, area statement, and sometimes labelled landmarks (e.g. churches, schools). This document is **authoritative** for "what area was assigned."

**Official Boundary**  
The legally/administratively assigned perimeter of the HLB. In the product, once accepted, the official boundary constrains all discovery, coverage analysis, and neighbour-boundary warnings. It may originate from: (a) imported official GIS from HLB boundary service, (b) confirmed boundary extracted from officer satellite map via spatial CV, or (c) deprecated manual walk (discouraged).

**Draft Map**  
The enumerator-built spatial representation during the **mapping phase**: confirmed observation regions become buildings, walked paths become breadcrumbs, landmarks and road coverage accumulate. The draft map is **ground truth in progress**, not the official HLO map.

**House Listing**  
The **listing phase** after mapping is sufficiently complete: the enumerator visits each confirmed building in a sensible order, verifies identity where required, and records census house data. Listing assumes discovery has already answered "what structures exist and where."

### 2.2 Zero Exclusion principle

Census doctrine: **no structure inside the HLB may be omitted without explicit justification and evidence.**

The product must support:

- Predicting where structures likely exist (observation regions)
- Proving the enumerator walked the block (breadcrumbs, road coverage)
- Proving the boundary was understood (official boundary confirmation)
- Surfacing **gaps** (walked road segments without nearby confirmed building, unwalked cells near buildings, open boundary loop, dense areas without records)
- Resolving gaps with enumerated outcomes: building found, no building, not accessible, investigated

Zero exclusion is why **coverage** matters more than **detection accuracy alone**. Finding 90% of obvious buildings but missing one lane is failure.

### 2.3 What the enumerator actually does (real world)

1. Receives assignment: HLB number, area, official map (PDF or printout from HLO).
2. Understands boundary and entry points (often verbally + map).
3. Walks the block systematically, noting structures, lanes, empty plots, sheds, shops.
4. Marks or records structures for listing.
5. Returns to complete house listing forms per structure.
6. Supervisor checks completeness before submission.

The enumerator is **not** creating a GIS dataset. They are **executing an assignment** and **proving they did not miss habitation.**

### 2.4 Four distinct activities

These must never be conflated in UX or data model:

| Activity | Question answered | Who is authoritative | System role |
|----------|-------------------|----------------------|-------------|
| **Prediction** | What likely exists here? | AI / CV / document parser | Hypothesis generation |
| **Validation** | Did I confirm or reject this hypothesis? | Enumerator | Evidence capture |
| **Listing** | What are the census attributes of this structure? | Enumerator + rules | Structured data entry |
| **Completion** | Can I prove nothing was missed? | System + enumerator | Coverage graph, gaps, index |

Prediction happens **before** or **during** walk from satellite/document intelligence. Validation happens **at the camera** and **at gaps**. Listing happens **after** structure identity is established. Completion is **continuous** and **summative**.

---

## 3. Product Philosophy

### 3.1 Three truths

**Truth 1 — The officer provides the mission.**  
The state does not ask the enumerator to invent the HLB. The HLO PDF (or official GIS boundary) defines the assignment. The application's job is to **decode** that mission into actionable intelligence, not to replace the officer's cartography.

**Truth 2 — The app predicts the world.**  
From the official map and satellite imagery, the system predicts: boundary, observation regions, roads, water, vegetation, landmarks, neighbour context, suggested entry, suggested walk order, and confidence scores. These are **hypotheses** attached to evidence type `satellite` or `document`.

**Truth 3 — The enumerator validates reality.**  
Only the enumerator can classify a region as house, shop, shed, temple, vacant plot, or misdetection. Only the enumerator can confirm the boundary matches ground truth. Only the enumerator can resolve a coverage gap. The system **never** auto-creates an official building record from AI alone.

### 3.2 Why the enumerator is not doing GIS

GIS work requires projection knowledge, topology editing, and intent about layer semantics. Enumerators require **guided validation** and **proof of completeness**. All geometric heavy lifting — boundary extraction, region proposal, road graph estimation — happens in the **Mission Knowledge Engine** (via the Spatial Intelligence Engine) before and during the walk, with optional adjustment, not as a primary manual task.

### 3.3 Why the app never automatically creates buildings

Automatic building creation would:

- Violate Census accountability (who confirmed this structure?)
- Confuse listing phase (which records are real?)
- Poison the digital twin (hypothesis masquerading as confirmed)
- Destroy audit trails

**Buildings** exist in the data model only after **explicit enumerator confirmation** (or manual discovery at GPS with confirmation). Observation regions promote to buildings; they are not born as buildings.

### 3.4 Human authority

Humans remain authoritative for:

- Boundary acceptance or adjustment
- Region confirm / reject / ignore
- Structure classification (residential pucca, shop, shed, etc.)
- Gap resolution narrative
- House listing field values
- Mission submission decision

AI may **suggest**, **rank**, **highlight**, and **warn**. AI may **not** **commit** official census records.

---

## 4. Mission Knowledge Engine

The **Mission Knowledge Engine** transforms an official map artifact plus enumerator context into **initial twin state** — a predicted world consumable by Discovery, Coverage, and Listing. It is fed by the **Spatial Intelligence Engine** (document parsing + spatial CV). Detailed pipeline stages: [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md).

### 4.1 Pipeline overview (simplified)

```
Official HLO Map (PDF or raster)
        │
        ▼
Mission Knowledge Engine  ──writes──►  Digital Twin (initial hypotheses)
        │
        └── All downstream capabilities read/write the same twin
```

Legacy diagram (still valid as internal stages):

```
Official HLO Map → Document Intelligence → Spatial CV → Mission Knowledge → Digital Twin
        → Discovery → House Listing
```

Each stage produces artifacts stored **on the twin**, not in disconnected screen state. Downstream capabilities **read the Digital Twin** as the integration hub.

### 4.2 Stage: Official HLO Map

**Input:** PDF or high-resolution image from HLO export.  
**Assumption:** Satellite imagery with visible boundary; not a hand sketch (sketch path exists but is secondary).

**Responsibilities:**

- Ingest and store immutable source artifact
- Rasterize PDF if needed
- Classify document type (official satellite map vs other)

**Output:** Stored source key + preliminary document bounds.

### 4.3 Stage: Document Intelligence

**Purpose:** Extract deterministic metadata without ML where possible.

**Extract:**

- HLB number (e.g. 0595)
- Ward / Town / Village / District / State
- Generated timestamp
- Neighbour HLB numbers visible on map margins
- North arrow orientation
- Legend keys
- Declared area if printed

**Design note:** OCR and layout rules on header/footer bands; satellite panel cropped for CV. Left information panel is **excluded** from structure detection.

**Output:** `MissionDocumentMetadata` attached to Official Mission Package.

### 4.4 Stage: Spatial CV Engine

**Purpose:** Offline, deterministic, reproducible extraction from imagery inside the HLB.

**Order of operations (mandatory):**

1. Detect boundary polygon (white/high-contrast closed loop on satellite)
2. Crop/mask to interior — **never analyze outside assigned HLB**
3. Detect observation regions (roof-like texture clusters — not classified building types)
4. Detect road segments (linear features, contrast-aligned)
5. Detect water bodies, canals, vegetation patches
6. Infer landmark candidates (low confidence unless OCR/name overlap)

**Non-goals at this stage:** Building type classification, address assignment, census house counts.

**Output:** `CvExtractionResult` with UV-space geometry and per-layer confidence.

**Future:** ONNX models pluggable behind same interface; heuristics remain fallback.

### 4.5 Stage: Mission Knowledge packaging

**Purpose:** Geospatially anchor UV extraction to the real world and write initial hypotheses into the twin.

**Process:**

- Auto-align boundary to enumerator GPS seed (refinement via Adjust UI if confidence low)
- Project observation regions, roads, landmarks, water to lat/lng
- Compute spatial confidence: boundary, structures, roads, landmarks, alignment, overall
- Score quality: excellent / good / needs_review
- Build human-readable summary counts

**Output:** Mission Knowledge snapshot — the review screen payload before field walk (implementation type may retain `MissionIntelligence` naming).

**Critical UX gate:** Enumerator sees **Mission Review** with confidence and **Looks Correct / Adjust**. No silent acceptance.

### 4.6 Stage: Twin bootstrap

**Purpose:** Canonical derived graph integrating spatial hypotheses and validated knowledge. Field work **appends evidence**; the Fact Engine **recomputes** the graph — screens do not mutate entities in place.

**Contains:** Twin objects (boundary, observation regions, roads, landmarks, water, vegetation) each with knowledge state derived from facts. Graphs: road, region/building, coverage, discovery, evidence.

**Rule:** Mission Execution screens **read the World Model** and **write evidence/facts** — not raw twin patches. See [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md).

### 4.7 Stage: Discovery

**Purpose:** Convert hypotheses to confirmed ground truth through walked validation.

**Activities:** Walk with GPS breadcrumbs; validate regions via camera; confirm/reject/ignore suggestions; resolve coverage gaps; attach photos and timestamps.

**Output:** Updated twin (hypothesis → observed → confirmed/rejected); confirmed buildings in local HLB state; gap resolutions.

### 4.8 Stage: House Listing

**Purpose:** Census data collection per confirmed building.

**Prerequisite:** Mapping phase reached submission threshold or enumerator explicitly transitions after draft finalize.

**Activities:** GPS-guided visit order; arrival detection; identity verification hook; house form; completion status per building.

---

## 5. Official Mission Package

The **Official Mission Package** is the internal aggregate produced by import. It is the single conceptual object replacing "uploaded layout image."

### 5.1 Package structure

```
OfficialMissionPackage
├── document          # provenance, metadata, source file reference
├── imagery           # cropped satellite raster, dimensions, north bearing
├── metadata          # HLB id, admin hierarchy, neighbours, area, generatedAt
├── boundary          # official UV ring, GPS ring, confidence, source
├── observationRegions[]  # predicted visit targets, not buildings
├── roadGraph         # segments, nodes, optional road names from OCR
├── waterFeatures[]   # ponds, canals, rivers
├── vegetationPatches[]
├── landmarks[]       # named + CV candidates merged when matched
├── neighbours        # adjacent HLB ids for fence warnings
├── entryPoints[]     # suggested walk starts (road-boundary intersections)
├── missionConfidence # spatial confidence scores + overall quality
├── digitalTwin       # graph representation for runtime
└── evidence[]        # document-level evidence (import timestamp, parser version)
```

### 5.2 Metadata

Administrative and assignment facts extracted from HLO document. Used for:

- Display on Mission Review
- Validation that enumerator opened correct HLB
- Neighbour fence labels in warnings
- Audit exports

### 5.3 Boundary

**Fields:** UV polygon, GPS polygon (post-alignment), confidence, source (`cv_detected`, `document`, `manual_adjust`), acceptance timestamp, accepting user.

**Rule:** Coverage analysis and "inside HLB" tests use official boundary once confirmed.

### 5.4 Observation Regions

**Definition:** A polygon or point region representing "something worth visiting" — likely roof or built surface — without asserting building type.

**Fields:** region id, centroid, footprint estimate, confidence, status (predicted → …), linked twin object id.

**Not a building until:** enumerator validates and optionally classifies.

### 5.5 Road Graph

Nodes at intersections and boundary entry points; edges as walked or detected segments. Enables:

- Road coverage percentage
- Suggested serpentine route
- Gap detection "road without building nearby"

Road names from OCR (e.g. "NAD Road") attach as edge labels, not separate geometry.

### 5.6 Water, Vegetation, Landmarks

**Water:** ponds, tanks, canals — affect walk planning and exclusion from structure expectations.

**Vegetation:** tree cover patches — explain false roof detections.

**Landmarks:** church, school, etc. — anchor enumerator mental model; match OCR labels to CV points when possible.

### 5.7 Mission Confidence

Structured scores 0–1 (displayed as percent):

- boundary
- observation regions (structures layer)
- roads
- landmarks
- alignment (map to GPS)
- overall

Drives Review UI and gates "Start Discovery Walk" when below threshold (policy configurable).

### 5.8 Digital Twin (within package)

Initial twin is **hypothesis-only** with satellite evidence on every object. Field work appends camera, GPS visit, enumerator_confirmed evidence.

### 5.9 Evidence (package-level)

Import event, parser version, CV engine version, checksum of source PDF, enumerator who confirmed mission review.

---

## 6. Digital Twin

The Digital Twin is **the product** — an **evidence-backed spatial knowledge graph** for one Official Mission (one EB/HLB). It is not a 3D mesh. It is not a subsection of the architecture; it is the **runtime heart** and **persistence model** for all mission activity.

**Authoritative detail:** entity relationships, knowledge states (`UNKNOWN` → `AUDITED`), twin evolution lifecycle, evidence-first causality, and geometry-vs-knowledge separation are defined in [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md).

### 6.1 Summary (see twin spec for full model)

**Geometry layer:** Boundary, observation region footprints, road segments, landmarks (spatial facts).

**Knowledge layer:** Knowledge state per entity, classifications, census entities (houses), gap resolutions (semantic facts).

**Evidence layer:** Append-only records that **cause** knowledge transitions — not decorative attachments.

**Capabilities on the twin:** Discovery, Listing, Coverage, Identity, Replay, Learning, Export — each reads/writes defined twin partitions.

| Entity | Description |
|--------|-------------|
| **Boundary** | Closed polygon; separates in-mission vs out-of-mission |
| **Observation Region** | Predicted or manually added visit target |
| **Building** | Confirmed structure (geometry + knowledge); container for census houses |
| **Census Entity (Census House)** | Official listing unit — many may exist inside one building |
| **Road segment** | Linear feature for coverage |
| **Landmark** | Point/area reference feature |
| **Water / Canal / Vegetation** | Environmental features affecting expectations |
| **Evidence** | Typed record attached to any entity |
| **Coverage cell** | Heatmap tessellation state (derived, not primary stored entity) |

### 6.2 Evidence types

- `satellite` — from CV on official map
- `document` — from HLO metadata parser
- `camera` — from discovery camera capture
- `gps_visit` — enumerator entered region proximity
- `enumerator_confirmed` — explicit tap confirm
- `photo` — attached image
- `timestamp` — temporal anchor

Evidence arrays are append-only during mission; corrections add new evidence, not silent overwrites.

### 6.3 Knowledge states (summary)

Full state machine: [`DIGITAL_TWIN_SPEC.md` §3](./DIGITAL_TWIN_SPEC.md#3-knowledge-states).

```
UNKNOWN → PREDICTED → OBSERVED → VALIDATED → CLASSIFIED → LISTED → COMPLETE → AUDITED
```

Legacy twin object statuses (`hypothesis`, `observed`, `confirmed`, `rejected`) map to subsets of this chain. **Buildings** require at least `VALIDATED`. **Census entities** require `LISTED` for form data. Mission closure requires `COMPLETE` on coverage; audit export requires `AUDITED`.

**Building listing status (operational axis, parallel to knowledge):**

```
not_visited → visited → completed
              ↘ revisit_required
```

**Evidence-first rule:** Every transition above must be explainable from an evidence chain — see twin spec §5.

### 6.4 Confidence

Each twin object carries confidence from origin (CV score). Field evidence may increase effective confidence. Confidence is **informational** for enumerator; it does not auto-promote status.

### 6.5 Graphs

- **Road graph** — coverage routing
- **Region/building graph** — adjacency for serpentine ordering
- **Coverage graph** — cells vs walk path
- **Discovery graph** — visit order history
- **Evidence graph** — audit linkage

### 6.6 Digital Twin as integration point

| Consumer | Reads from twin |
|----------|-----------------|
| Discovery Hub | completion, gaps, region counts |
| Discovery Camera | nearest unvisited region, overlay |
| Heatmap | cell state derived from twin + breadcrumbs |
| Coverage Gaps | open gaps linked to regions/roads |
| House Listing | confirmed buildings only |
| Supervisor export | evidence chain |

---

## 7. Discovery Workflow

Discovery is the **mapping phase** field experience. Goal: validate predicted world and prove spatial coverage before listing.

### 7.1 Entry conditions

Enumerator has:

- Authenticated session
- EB in `draft` or mapping-eligible `published` state
- Official Mission Package imported and reviewed (boundary confirmed)
- Optional: navigated to suggested start point

### 7.2 Discovery Hub

**Purpose:** Mission control for mapping phase — not a form screen.

**Shows:**

- Official boundary summary + link to start point navigation
- Mission Knowledge summary (region count, roads, landmarks, water)
- Mission Completion Index (weighted percent + can submit flag)
- Metric grid: boundary coverage, road coverage, path walked, structures confirmed
- Gap summary card (open/high priority counts)
- Ignored suggestions count
- Actions: Start Discovery Walk, Draft Map, Coverage Gaps, Replay, Dashboard, transition to House Listing when ready

**Philosophy:** One screen answers "where am I in the mission?" and "what should I do next?"

### 7.3 Discovery Camera

**Purpose:** Validate observation regions — **not** open-ended object detection.

**Behavior:**

- Full-screen camera
- Overlays nearest/highest-priority unvisited region
- Quick confirm → promotes region, creates building at GPS, attaches camera evidence
- Long press / detail → classify, add notes, attach photo
- Ignore → records ignored suggestion (feeds learning stub, reduces repeat prompts)
- Merge satellite hypotheses with on-device hints — satellite authoritative for **which** region; camera for **confirmation**

**Anti-pattern:** Showing generic "possible structure" without mission context.

### 7.4 Mini Map

Embedded in camera or hub — enumerator position, official boundary, regions by status, breadcrumbs. Read-only during walk; no editing.

### 7.5 Heatmap

**Purpose:** Answer "where should I walk next?" without reading percentages.

**Cell states (recommended palette):**

| State | Meaning |
|-------|---------|
| Grey | Predicted but not visited |
| Orange | Walked / observed, not validated |
| Green | Validated / confirmed |
| Red | Needs investigation (gap, high suspicion) |

Heatmap derives from twin + breadcrumb tessellation — not a separate truth source.

### 7.6 Coverage Gaps

**Purpose:** Zero exclusion enforcement UI.

**Gap types include:** road segment without nearby building, walked cluster without building, unwalked grid cell near buildings, open boundary loop, low coverage percentage.

**Enumerator actions:** Navigate (bearing arrow), resolve with outcome (building found, no building, not accessible, investigated), attach note/photo.

**Resolution updates:** twin, gap registry, completion index.

### 7.7 Discovery Replay

Animated breadcrumb path with confirmation events timeline — for self-review and supervisor conversation. Not vanity; audit aid.

### 7.8 Discovery Dashboard

2D map visualization of progress — alternative view to hub metrics for supervisors or confused enumerators.

### 7.9 Completion (mapping phase)

**Mission Completion Index** combines coverage, region validation rate, road walk, boundary verification, open gaps.

**Submit gate (policy):** official boundary + at least one confirmed building + zero open gaps + overall ≥ threshold.

**Finalize draft map** transitions EB toward listing phase (`published`, phase `listing`).

---

## 8. Camera Philosophy

### 8.1 Camera is validation, not search

The camera does not ask "what do you see in the world?" in the abstract. It asks:

> **"Is Observation Region 18 what we predicted? If not, what is it?"**

This reduces cognitive load and prevents duplicate buildings from repeated detections.

### 8.2 The system suggests; enumerator confirms

Suggestion sources:

- Satellite/CV observation regions (primary)
- On-device detector (secondary hint only — may be disabled in lean builds)

Neither source creates records alone.

### 8.3 Interaction model

| Gesture | Meaning |
|---------|---------|
| Tap confirm | Region validated → building created |
| Long press | Classification sheet (house, shop, shed, reject as tree, etc.) |
| Ignore | Suppress re-prompt; log for learning |
| Capture photo | Attach evidence without confirming |

### 8.4 Overlays

Bounding region hull, region id label, distance to centroid, status chip (Not Visited / Observed / Confirmed). Minimize chrome; one-handed use.

### 8.5 Evidence attachment

Every confirm attaches: GPS fix, timestamp, optional photo, device id, region id reference, enumerator id.

---

## 9. Coverage Philosophy

### 9.1 Why coverage beats detection

High building detection F1 with poor walk coverage still fails Census. The product optimizes **provable spatial completeness** over **maximum detections**.

### 9.2 Road coverage

Breadcrumbs compared to road graph and inferred paths. Thresholds: minimal walk vs substantive network coverage. Unwalked segments near dense regions raise gaps.

### 9.3 Boundary completion

Official boundary accepted vs enumerator walked perimeter (when manual walk used) or implicit acceptance when CV boundary confirmed. Open loop = high severity gap.

### 9.4 Coverage heatmap

Visual prioritization layer — see Section 7.5.

### 9.5 Gap confidence

Each gap has severity (high/medium/low) and optional distance/bearing from enumerator. High near dense building clusters.

### 9.6 Mission Completion Index

Weighted scalar for supervisors; **canSubmit** boolean for hard gates. Components:

- Coverage inside boundary (breadcrumbs)
- Observation regions validated vs predicted
- Roads walked (path length heuristic)
- Boundary verified
- Open gaps penalty

Percentages alone are insufficient UX; heatmap + gap list carry operational meaning.

### 9.7 Expected vs Actual (future-facing)

Satellite predicted N regions; field confirmed M buildings + K sheds + rejections. Digital Twin delta report for supervisor — **the richest audit artifact**.

---

## 10. House Listing

### 10.1 Sequencing

**Discovery finishes first** (mapping phase). **Listing starts afterwards** unless policy allows parallel for large blocks with partial finalize.

Transition trigger: `finalizeDraftMap` or supervisor unlock.

### 10.2 Today's Mission (listing home)

GPS-aware **next building** recommendation; distance and bearing; progress counts; link to end-of-day review.

### 10.3 Building navigation

Serpentine or route-optimized order from confirmed buildings. Arrival geofence auto-marks **visited**.

### 10.4 Identity verification

Optional integration with Identity Engine: visual/GPS fingerprint vs prior observations — **same asset / possible match / new asset**. Listing should not block on identity unless policy requires.

### 10.5 House data

Census house count, building type enum (pucca residential, non-residential pucca, kutcha variants), notes. Domain forms live here — minimal during discovery.

### 10.6 Completion

Per-building `completed` status; EB-level progress percent; end-of-day review with remaining list and ETA estimate.

---

## 11. AI Responsibilities

AI and CV **may**:

| Capability | Detail |
|------------|--------|
| Predict observation regions | Roof-like clusters inside boundary |
| Suggest boundary | Extract white polygon; allow human adjust |
| Detect roads | Segment graph inside boundary |
| Suggest landmarks | CV + OCR fusion |
| Estimate confidence | Per-layer and overall |
| Find coverage gaps | Compare walk to prediction |
| Rank next region | Proximity + unvisited + severity |
| Warn neighbour HLB exit | GPS vs boundary + OCR neighbour ids |
| Optional field assistant | Natural language help — non-blocking |

AI and CV **must not**:

| Prohibition | Reason |
|-------------|--------|
| Auto-create official building records | Accountability |
| Auto-finalize mission | Human sign-off |
| Auto-classify census building type from satellite alone | Requires ground truth |
| Replace gap investigation judgment | Narrative outcomes |
| Silently override official HLO metadata | Document authority |
| Operate only online without local fallback | Field reality |

**Gemini / LLM vision:** Optional assistant tier only — **never on critical path** for boundary, regions, or listing. Spatial CV engine is critical path.

---

## 12. Human Responsibilities

| Responsibility | Description |
|----------------|-------------|
| Boundary verification | Accept or adjust official boundary |
| Structure confirmation | Promote region to building |
| Classification | Building type and use |
| Rejection | Tree, shadow, debris — with ignore/reject |
| House listing | Census attributes |
| Gap investigation | On-ground resolution with outcome |
| Mission completion | Submit when index gates satisfied |
| Neighbour awareness | Respond to cross-HLB warnings |

Supervisors additionally: review replay, audit evidence graph, approve exceptions.

---

## 13. Offline-first Architecture

### 13.1 Principle

Mapping phase assumes **intermittent or zero connectivity**. Listing phase tolerates offline with queue but prefers sync for dashboard accuracy.

### 13.2 Local-first mapping

**HLB Local State** on device is source of truth during mapping:

- Boundary vertices, buildings, landmarks, breadcrumbs
- Gap resolutions, ignored suggestions
- Cached mission intelligence and layout georef
- Official boundary snapshot
- Phase and block status

**Mission Local First Service** writes locally first, syncs in background.

### 13.3 Background sync

On connectivity:

- Flush offline operation queue (breadcrumbs, buildings, boundary, landmarks, gap resolve, finalize)
- Pull server offline snapshot
- Merge without blocking UI

Conflicts: server wins for supervisor locks; enumerator wins for unsubmitted field confirmations (policy documented per entity type).

### 13.4 Caches

| Cache | Contents |
|-------|----------|
| Digital Twin cache | Twin objects + statuses |
| Discovery cache | Regions, candidates |
| Gap cache | Open/resolved gaps |
| Evidence cache | Pending photo uploads |
| Mission package cache | Metadata + intelligence JSON |
| General survey sync | Assets, detections (platform-level) |

### 13.5 Offline invisibility

Enumerator never taps "sync now" as primary action. Sync indicators subtle; errors retry with backoff.

---

## 14. Screen-by-screen Specification

### 14.1 Authentication

**Login** — Email/password; device id registration; routes to Mission Landing on success.

### 14.2 Mission Landing

Post-login home. Resumes active EB if draft/published mapping or listing in progress; else project picker or single-project "New HLB Mission" prompt.

### 14.3 Mission Hub (EB List)

Lists EBs grouped: **HLB Mapping** (draft), **House Listing** (published), **Completed**. Entry to create new EB.

### 14.4 Mission Source

Choose boundary source:

- **Official GIS** — preloaded boundary from HLB boundary service
- **Officer Satellite Map (recommended)** — import HLO PDF/image → Mission Review path
- **Manual walk (deprecated)** — discouraged; legacy only

### 14.5 Mission Review (Layout Georef Wizard)

**Phases:** Upload → Analyzing → Review → Adjust (optional)

**Purpose:** Import Official Census Mission; show confidence; **Looks Correct** commits intelligence to twin; **Adjust** allows scale/opacity/bounds tweak.

**Not:** Multi-step landmark georeferencing wizard.

### 14.6 Discovery Hub

Mapping mission control — see Section 7.2.

### 14.7 Start Point

Turn-by-turn or map navigation to suggested NW entry or nearest road-boundary entry.

### 14.8 Discovery Camera

Region validation camera — see Section 8.

### 14.9 Coverage Gaps

Gap list + map + navigation + resolution — see Section 7.6.

### 14.10 Discovery Dashboard

Map-centric analytics view.

### 14.11 Discovery Replay

Path + event timeline replay.

### 14.12 Ignored Structures

Review ignored AI/region suggestions; restore if mistaken.

### 14.13 Draft HLB Map

Review/export draft PDF before listing.

### 14.14 Today's Mission (Listing Home)

Next building GPS navigation; progress; links to scanner and end-of-day.

### 14.15 Building Workflow

Per-building arrive → scan/verify → complete.

### 14.16 End of Day Review

Remaining buildings; progress ring; morale/ planning aid.

### 14.17 Projects / Project Detail

Secondary entry for multi-project supervisors; sync; links to legacy map/scanner/analytics.

### 14.18 Scanner / Identity Verification

Platform-level asset scanning and identity resolution — used heavily in listing, optionally in discovery.

### 14.19 Settings

Device, sync status, logout — minimal.

### 14.20 Deprecated / orphan screens (do not productize)

- Layout Map Editor (server-first plan drawing)
- Discovery Mission Screen (superseded hub+camera)
- AR View (disabled in field builds)
- Manual boundary walk primary flow

---

## 15. Backend Architecture

### 15.1 Service boundaries

| Engine | Role |
|--------|------|
| **Mission Knowledge Engine** | Orchestrate CV + alignment + twin bootstrap |
| **Spatial CV** | Boundary, regions, roads, water/vegetation |
| **Document Intelligence** | PDF/metadata/OCR (planned formalization) |
| **Digital Twin** | Build and merge twin graphs |
| **Coverage** | Gap detection, coverage analysis |
| **Identity** | Observations, embeddings, resolve, link |
| **Learning** | Feedback ingest (stub → future training) |
| **Sync** | Push/pull, conflicts, offline snapshot |
| **Storage** | S3-compatible object store for maps/photos |
| **Auth** | JWT, roles (admin, supervisor, field_worker) |

### 15.2 API responsibility groups

| Group | Responsibility |
|-------|----------------|
| `/auth` | Login, refresh, logout |
| `/projects` | Project CRUD, categories, membership |
| `/mission` | EB lifecycle, discovery, gaps, breadcrumbs, buildings, finalize, offline snapshot |
| `/hlb-boundaries` | Official GIS import, boundary audit |
| `/layout-georef` | Map upload, intelligence generate/confirm, learning feedback, optional assistant |
| `/identity` | Resolve, observations, resolutions |
| `/survey` | Generic survey sync, assets, conflicts |
| `/detections` | Platform detection verification |
| `/assets` | Verified spatial assets |

### 15.3 Critical path vs optional

**Critical path:** Spatial CV → Mission Knowledge → Mission APIs → Offline snapshot.

**Optional:** Gemini assistant, learning persistence, AR, photogrammetry.

### 15.4 Worker

Background jobs: fingerprint queue, async processing — listing phase enrichment.

---

## 16. Long-term Roadmap

### 16.1 Near-term (0–3 months)

- Formal **Official Mission Package** type and import pipeline for HLO PDF
- Document Intelligence: metadata + neighbour OCR + satellite panel crop
- White-boundary detector tuned for HLO style
- Golden fixture: HLB 0595 PDF regression tests
- Rename UI: Observation Target → **Observation Region**
- Discovery Camera binds to region ids
- Neighbour HLB GPS warnings
- Mission Review as default import UX
- Rebuild/deploy discipline for API routes in Docker
- Heatmap on Discovery Hub
- Expected vs Actual summary on completion

### 16.2 Medium-term (3–9 months)

- Road graph → suggested entry + walk loop
- ONNX models behind Spatial CV interfaces
- Learning engine persistence (DB, not in-memory)
- Supervisor web dashboard for twin + evidence graph
- PDF export with evidence appendix for audit
- Improved offline conflict policies
- Field assistant (optional LLM) strictly non-critical

### 16.3 Research (9–18 months)

- Weakly supervised region segmentation on satellite
- Neighbour HLB auto-boundary from national mesh
- Cross-mission learning (region appearance priors by region of country)
- Semi-automatic expected vs actual reconciliation
- Voice-first gap resolution notes

### 16.4 Future (18+ months)

- Multi-tenant Mission OS beyond Census
- Policy engine for state-specific listing rules
- Integration with official HLO APIs (direct mission pull, not file import)

### 16.5 Do not build until field data proves need

- Full ONNX replacement without heuristic fallback
- Autonomous re-prediction mid-mission without enumerator trigger
- National-scale learning models without consent and retention policy
- Automatic building creation under any circumstances
- 3D mesh or photogrammetry pipeline (see Non-goals)

---

## 17. Non-goals

Explicitly deferred or rejected:

| Non-goal | Rationale |
|----------|-----------|
| **Photogrammetry / 3D reconstruction** | Cost, skill, device burden; not needed for listing proof |
| **Mesh / AR-first workflows** | Distraction; AR disabled in production builds |
| **Automatic building creation** | Violates human authority |
| **Autonomous surveying** | Enumerator remains in loop |
| **Replacing human judgment on gaps** | Legal and practical accountability |
| **Gemini on critical path** | Non-deterministic; offline failure |
| **Enumerator-as-GIS-editor** | Wrong persona |
| **Cloud-only mapping** | Field connectivity reality |
| **Perfect building typology from satellite** | Insufficient signal; use regions |

---

## 18. Design Philosophy

### 18.1 UI principles

1. **Camera first** — validation happens where eyes are, not in forms.
2. **Minimal forms during discovery** — tap confirm beats typing.
3. **One-handed operation** — thumb zone actions; large targets.
4. **Offline invisible** — no sync anxiety.
5. **Dark theme** — outdoor glare reduction (current app bias).
6. **Human confidence over AI confidence** — show AI percent small; show "Needs your confirmation" large.
7. **Actionable information only** — no dashboards for vanity metrics in field.
8. **Mission Review before walk** — never silent intelligence.
9. **Heatmap over percentages** for spatial decisions.
10. **Warnings are contextual** — neighbour HLB, gap severity, not alarm fatigue.

### 18.2 Copy principles

- Say **Import Official Mission**, not Upload File.
- Say **Observation Region 18**, not Possible Structure.
- Say **Validate**, not Detect.
- Say **House Listing**, not Phase 2.
- Cite **HLO** as authority source in help text.

### 18.3 Error philosophy

Errors explain **what the enumerator should do next** (e.g. adjust boundary, walk gap, retry import) — not HTTP codes on screen.

### 18.4 Accessibility and field reality

High contrast, outdoor-readable typography, tolerate gloved hands, low bandwidth, mid-range Android (e.g. Redmi-class devices), MIUI USB install quirks acknowledged in ops docs not product UI.

---

## Appendix A — Glossary

| Term | Definition |
|------|------------|
| HLB | House Listing Block — assigned geographic unit |
| EB | Enumeration Block — software record for HLB |
| HLO | House Listing Operation — Census system generating official maps |
| Observation Region | Predicted visit target; not yet a building |
| Building | Confirmed structure eligible for listing |
| Official Mission Package | Decoded HLO mission aggregate |
| Evidence Stream | Append-only mission log — source of truth |
| Fact | Atomic assertion from evidence (e.g. `VisitedRegion`, `StructurePresent`) |
| Reasoning Engine | Facts + context → knowledge (policy, rules, stats, ML) |
| Knowledge Graph | Canonical derived state — persisted, rebuildable from evidence |
| Projection builder | One independently versioned read model from the graph |
| Knowledge Freshness | Temporal aging of inferred knowledge — evidence never ages |
| Expectations | Predicted mission outcomes — bounded context; see EXPECTATIONS_SPEC |
| Census Entity | Official census house — distinct from building geometry |
| Knowledge State | Lifecycle stage from UNKNOWN through AUDITED |
| Zero Exclusion | No missed structures without documented gap resolution |
| Serpentine | Walk order pattern for efficient listing |

---

## Appendix B — Status reference

**EB block status:** `draft` | `published` | `archived`

**EB phase:** `mapping` | `listing`

**Twin object status (legacy):** `hypothesis` | `observed` | `confirmed` | `rejected` — maps to Knowledge States in [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md)

**Building listing status:** `not_visited` | `visited` | `completed` | `revisit_required`

**Gap resolution:** `building_found` | `no_building` | `not_accessible` | `investigated`

**Heatmap cell:** `unvisited` | `covered` | `partial` | `suspicious` (conceptual)

---

## Appendix C — Document maintenance (v1.0 policy)

**This document is frozen at Version 1.0** (§0 updated in v1.0 addendum for World Model / Fact Engine framing). Do not expand subsystem depth here.

**Hierarchy of truth:**

1. **This spec** — product vision, invariants, and boundaries (change rarely; version bump required).
2. **Companion specs** — subsystem *behavior* only; update when behavior changes, not when implementation details change.
3. **Code** — primary source for implementation details, APIs, and schemas.

When architecture changes:

1. Implement or prototype in code first when the change is implementation-only.
2. Update the **relevant companion spec** when *observable behavior* changes.
3. Amend this document **only** when a product-level invariant changes (version bump: 1.1, 2.0).
4. AI agents (Cursor) should read **this file + the relevant companion** when starting features — not re-derive architecture from code alone.

**Anti-pattern:** Updating four documents for every PR. If the Fact Engine reducer gains a new fact type, change code + twin spec §5; do not touch the root spec.

## Appendix D — Companion specifications

| Document | When to read |
|----------|--------------|
| [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) | Persistence classes, Reasoning Engine, projection pipeline, implementation phases |
| [`DISCOVERY_ENGINE_SPEC.md`](./DISCOVERY_ENGINE_SPEC.md) | Mission Execution — evidence capture, projection APIs |
| [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md) | Import pipeline, initial prediction evidence |
| [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md) | Expectations domain — prediction, delta, learning |
| [`EVIDENCE_SPEC.md`](./EVIDENCE_SPEC.md) | Evidence bounded context |
| [`EVENT_CATALOG.md`](./EVENT_CATALOG.md) | **Execution contract** — primary doc during implementation |
| [`PR_INVARIANTS.md`](./PR_INVARIANTS.md) | Required PR checks |
| [`ARCHITECTURE_FREEZE.md`](./ARCHITECTURE_FREEZE.md) | Pipeline frozen — feature gate |
| [`MOBILE_EVIDENCE_TRANSITION.md`](./MOBILE_EVIDENCE_TRANSITION.md) | Mobile WorldRepository Phase A |

**End of specification (v1.0).**
