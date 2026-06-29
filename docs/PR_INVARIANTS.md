# Pull Request Invariants

Every PR must satisfy these rules. If a change violates one, fix the code or update the **Event Catalog** and companion spec for that subsystem only.

## Architecture

1. **Traceability:** Every UI-visible value traces to evidence → facts → reasoning → graph → projection.
2. **Write path:** Production code appends **evidence only** (`POST /evidence`). No `PATCH` on buildings/regions as authority.
3. **Three persistence classes:**
   - Evidence Log — append-only, source of truth
   - Knowledge Graph — canonical derived state (persist)
   - Projections — disposable cache
4. **Facts are ephemeral** — do not add permanent fact tables without explicit review.
5. **Projection isolation:** Builders read Knowledge Graph or Evidence (Replay only). **Never read another projection.**
6. **Domain events** are consequences of reasoning — graph builder applies them; catalog must list domain events per evidence type.
7. **Architecture freeze** — see [`ARCHITECTURE_FREEZE.md`](./ARCHITECTURE_FREEZE.md). New features: evidence + domain events + projection.

## Versioning

- Bump **Fact Engine** version when evidence→fact derivation changes.
- Bump **Reasoning Engine** version when rules/policy change.
- Bump **individual projection builder** version when read-model shape changes — not a global reducer version.
- Bump **evidence `schemaVersion`** when payload shape changes.

## Tests

- `ReplayInvariantTest` must pass (`npm test`).
- New events require catalog entry in [`EVENT_CATALOG.md`](./EVENT_CATALOG.md).

## Documentation

- **Do not** expand root spec for implementation details.
- Update [`EVENT_CATALOG.md`](./EVENT_CATALOG.md) when adding/changing events.
- Update companion spec only when **observable behavior** changes.

**End.**
