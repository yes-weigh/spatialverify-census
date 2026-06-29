# Mobile Evidence Transition

**Status:** Phase A guidance — do not remove local mutations immediately  

---

## Principle

The UI reads **WorldProjection** from `WorldRepository`. It does not know whether the projection came from server replay or local replay.

## Phase A (online)

```
Confirm Region
    → POST /evidence (region_confirmed@1)
    → Server pipeline
    → GET /world
    → WorldRepository.replace(projection)
    → UI rebinds
```

## Phase A (offline)

```
Confirm Region
    → POST /evidence → Offline evidence queue (local EvidenceStore)
    → Local replayPipeline (same Fact/Reasoning/Graph/World builders, same versions)
    → WorldRepository.replace(local projection)
    → UI rebinds (identical code path)
```

On sync: flush evidence queue to server in sequence order; replace local projection from `GET /world`.

## WorldRepository (mobile)

Single interface:

```dart
abstract class WorldRepository {
  Stream<WorldProjection> watch(String ebId);
  Future<WorldProjection> refresh(String ebId);  // GET /world or local replay
  Future<void> appendEvidence(EvidenceEnvelopeInput input);
}
```

Implementations:

- `RemoteWorldRepository` — online GET /world after POST /evidence
- `OfflineWorldRepository` — local evidence queue + shared replay logic (or sync when online)
- `HybridWorldRepository` — delegates by connectivity

## Do not

- Remove `hlb_local_state` until WorldRepository covers confirm/reject/ignore
- Mutate building/region state in UI without appending evidence
- Read twin PATCH responses as authority

## Supervisor audit (future UI)

```
GET /evidence/integrity  →  "347 evidence records — 0 integrity violations"
GET /replay              →  timeline + domain events
```

**End.**
