# Architecture Freeze

> **Implementation status:** Target architecture — **not in the shipping app**. Guardrails for a future evidence pipeline; the frozen stack described here is not what runs in production today (see [`AI_HANDOFF_CURRENT_STATE.md`](./AI_HANDOFF_CURRENT_STATE.md)).

**Effective:** 2026-06-25  
**Status:** Frozen — no changes to core pipeline for several months  

---

## Frozen (do not redesign)

- Evidence envelope model and hash chain
- Three persistence classes (Evidence / Knowledge Graph / Projections)
- Fact Engine → Reasoning Engine → Domain Events → Graph Builder → Projection Builders
- Ephemeral facts (not persisted)
- Projection isolation (builders never read other projections)
- Independent projection builder versioning

## Every new capability must answer

1. **Which evidence does it append?** (type + schemaVersion + payload)
2. **Which reasoning rules / domain events does it trigger?**
3. **Which projection builder consumes the result?**

If a feature cannot be expressed in those three terms, it does not belong in the current architecture.

## Allowed changes without freeze break

- New evidence types (catalog + validator + fact + domain events)
- New reasoning rules and domain event types
- New projection builders (independent version)
- New evidence producers (camera, OCR, HLO import, …)
- Mobile `WorldRepository` offline replay (same pipeline, local store)

## Not allowed without architecture review

- Persisting facts long-term
- Projections reading other projections
- PATCH endpoints as write authority
- Single global reducer version
- Hidden state not traceable to evidence

## Primary docs during implementation

1. [`EVENT_CATALOG.md`](./EVENT_CATALOG.md) — execution contract
2. [`PR_INVARIANTS.md`](./PR_INVARIANTS.md) — PR checklist
3. [`EVIDENCE_SPEC.md`](./EVIDENCE_SPEC.md) — evidence bounded context
4. Code + tests (`ReplayInvariantTest`)

**End.**
