# SpatialVerify Census — Documentation Index

**Last updated:** 2026-06-30

Use this index to find the right document. Several specs describe **target architecture** that is not built yet; do not use them alone to understand the shipping app.

## Current implementation (accurate today)

| Document | Audience | Contents |
|----------|----------|----------|
| [`../README.md`](../README.md) | Engineers | Repo overview, Firebase stack, OTA CI, quick start |
| [`AI_HANDOFF_CURRENT_STATE.md`](./AI_HANDOFF_CURRENT_STATE.md) | Engineers / AI agents | What is implemented in `mobile/`, routes, data model, CI |
| [`SPATIALVERIFY_APP_MANUAL.md`](./SPATIALVERIFY_APP_MANUAL.md) | Field enumerators | Map-first workflow, HUD, troubleshooting |
| [`firebase-github-actions.md`](./firebase-github-actions.md) | DevOps | GitHub secrets, Firebase deploy, OTA publish |
| [`LICENSING.md`](./LICENSING.md) | Product / ops | Mission credits, UPI payments, admin portal |

## UX & product contracts (partially implemented)

| Document | Status |
|----------|--------|
| [`MISSION_MAP_UX.md`](./MISSION_MAP_UX.md) | UX contract for georef + satellite map; largely matches wizard/map screens |
| [`MISSION_KNOWLEDGE_ENGINE.md`](./MISSION_KNOWLEDGE_ENGINE.md) | Import/CV/intelligence package — **partial**; see “Planned vs implemented” in doc |

## Target architecture (not in repo yet)

These documents are **roadmap / design specs**. The production app uses **Firebase Auth + Firestore + Storage** and **`HlbLocalState` in Hive**, not a Node API or evidence pipeline.

| Document | Topic |
|----------|--------|
| [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md) | Product vision, census domain, full platform design |
| [`DIGITAL_TWIN_SPEC.md`](./DIGITAL_TWIN_SPEC.md) | Evidence → facts → reasoning → projections |
| [`EVIDENCE_SPEC.md`](./EVIDENCE_SPEC.md) | Evidence envelope, hash chain, REST API |
| [`EVENT_CATALOG.md`](./EVENT_CATALOG.md) | Event types for future pipeline |
| [`EXPECTATIONS_SPEC.md`](./EXPECTATIONS_SPEC.md) | Expectations domain |
| [`DISCOVERY_ENGINE_SPEC.md`](./DISCOVERY_ENGINE_SPEC.md) | Discovery lifecycle (API-oriented) |
| [`MOBILE_EVIDENCE_TRANSITION.md`](./MOBILE_EVIDENCE_TRANSITION.md) | `WorldRepository` migration plan |
| [`ARCHITECTURE_FREEZE.md`](./ARCHITECTURE_FREEZE.md) | Guardrails when building evidence pipeline |
| [`PR_INVARIANTS.md`](./PR_INVARIANTS.md) | PR checklist for evidence architecture |

## What the shipping stack is

```
Flutter Android app (mobile/)
  → Hive (HlbLocalState) + Drift (SQLite) on device
  → Firebase Auth, Firestore, Storage when signed in
  → Firebase Hosting (public/ APK download page)
  → GitHub Actions: test, build, OTA publish
```

**Not present:** `backend/`, Cloud Functions, PostgreSQL, supervisor web portal, camera-based discovery walk.
