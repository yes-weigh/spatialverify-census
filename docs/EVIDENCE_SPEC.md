# Evidence Domain Specification

**Version:** 1.0  
**Parent:** [`PRODUCT_ARCHITECTURE_SPEC.md`](./PRODUCT_ARCHITECTURE_SPEC.md)  
**Execution contract:** [`EVENT_CATALOG.md`](./EVENT_CATALOG.md)  
**Status:** Living — bounded context for append-only mission evidence  

---

## Purpose

Evidence is a **first-class bounded context**, not a table. All producers (GPS, camera, OCR, CV, documents, supervisor corrections, ML, GIS, future IoT) emit the same **EvidenceEnvelope**.

## Components

| Component | Role |
|-----------|------|
| **EvidenceStore** | Append-only persistence (`evidence_events`) |
| **EvidenceValidator** | Schema + payload validation per `evidenceType@schemaVersion` |
| **EvidenceSerializer** | Row ↔ envelope mapping |
| **EvidenceHash** | SHA-256 chain: `hash(previousHash + canonicalBody)` |
| **EvidenceReplay** | Ordered load + chain verification |
| **EvidenceAPI** | `POST /api/v1/mission/ebs/:ebId/evidence` |

## Canonical envelope

```ts
EvidenceEnvelope {
  id, missionId, aggregateId, aggregateType
  evidenceType, schemaVersion, payload
  occurredAt, receivedAt
  actor, device
  hash, previousHash, sequenceNum
}
```

## Hash chain (audit, not blockchain)

```
E1 → E2(hash(E1)) → E3(hash(E2)) → …
```

Proves nobody silently modified history. Verified on replay via `verifyEvidenceChain()`.

## Schema versioning

Evidence types are versioned independently: `region_confirmed@1`, `gps_visit@2`. Replay ten years later uses `evidenceType + schemaVersion` to select parsers.

## Facts are ephemeral

Facts are **not** persisted long-term. They are compiler tokens:

```
Evidence → Facts (in-memory) → Reasoning → Knowledge Graph (persist)
```

If `VisitedRegion` is always derivable from evidence, it does not need permanent storage.

## PR invariants

See [`PR_INVARIANTS.md`](./PR_INVARIANTS.md).

**End of Evidence Domain Specification v1.0.**
