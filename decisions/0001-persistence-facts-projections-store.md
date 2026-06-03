# 0001. Persistence model: facts, projections, and a store interface

- Status: Proposed
- Date: 2026-06-01

## Context

Capabilities beyond the language server — capture, an event-driver ingest, and
eventually assistant-style adapters — need durable state. Before any of them bake
in a persistence assumption, the model has to be decided explicitly.

Operating constraints that bound the design:

- **Single user, single VPS, single writer.** There is exactly one operator and,
  in practice, one writing process. There is no multi-tenant or
  high-write-concurrency requirement.
- **Auditability and rebuildability matter.** A personal system that remembers
  things must be able to explain *why* its current state is what it is, and to
  reconstruct state after a bug or schema change.
- **Data-first.** State is plain data (maps/lists); persistence must not leak an
  ORM or object graph into the domain.
- **Avoid premature distribution.** Postgres, replication, and a separate query
  engine are complexity this system does not yet need.

## Decision

Model durable state as an append-only fact log with derived projections behind a
small store interface.

### Facts

A **fact** is an immutable record of something that happened:

```
{"id"   <monotonic-ordinal>     ; total order within a store
 "time" <instant>               ; when it was recorded
 "type" <string>                ; what kind of thing happened
 "data" <plain-map>}            ; the payload, plain data
```

Facts are never updated or deleted. `id` defines a total order; `time` is
informational. Schema evolution of `data` is handled by versioning *through the
`type`* (e.g. a new `type`, or a `version` key inside `data`), never by mutating
existing facts.

### Projections

A **projection** is a pure function folding an ordered fact stream into a view:

```
(projection initial-view fact) -> next-view
```

Projections are deterministic: replaying the same facts yields the same view.
Current state is always derivable from the log; the log is the source of truth,
projections are caches.

### Store

A `store` Polylith component exposes a small interface, independent of backend:

- `append-fact` — append one fact, assign its `id`, return the stored fact.
- `read-facts` — read facts in `id` order, optionally over a range.
- `project` / `snapshot` — fold a projection over the log to produce a view.

Backends are selected by **config data**, not hardcoded:

- **SQLite (WAL mode) is the default** backend. A single-writer file database is
  sufficient and operationally trivial on a single VPS; WAL gives durable,
  concurrent reads.
- An **in-memory** backend exists for tests (credential-free, CI-runnable).

### Explicitly deferred

A Datalog / XTDB-style query layer over the fact log is **not** built now. It is
revisited only when projection-based reads become genuinely insufficient (YAGNI).
When that happens it is recorded as a new ADR.

## Consequences

- **+** Auditable and rebuildable: state is replayable from an immutable log.
- **+** Testable: projections are pure; backends are swappable; the memory backend
  keeps tests offline.
- **+** Cheap to operate: one SQLite file, no server to run or back up specially.
- **+** Backend-agnostic domain: callers depend on the `store` interface, not SQLite.
- **−** Single-writer ceiling. Acceptable given the single-user constraint; a
  future multi-writer need would supersede this ADR.
- **−** Discipline cost: projections must stay pure, and fact `data` schema
  evolution must be additive/versioned rather than destructive.

## Validation

This ADR is `Proposed`. It moves to `Accepted` once the `store` component
implements this interface (SQLite + memory backends) and its tests confirm
append/read ordering and projection determinism. The implementation is the proof;
this record is the decision it proves.
