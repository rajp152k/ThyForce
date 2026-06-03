# Architecture decisions

Architecture Decision Records for ThyForce. Format and rules: [ADR-0000](0000-record-architecture-decisions.md).

ADRs are append-only. To change a decision, add a new ADR that supersedes the old
one; do not rewrite an accepted record.

| ADR | Title | Status |
| --- | --- | --- |
| [0000](0000-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0001](0001-persistence-facts-projections-store.md) | Persistence model: facts, projections, and a store interface | Accepted |
| [0002](0002-dispatch-spine-extraction.md) | Extract a transport-agnostic dispatch spine from the LSP engine | Accepted |

## Planned

Decisions identified but not yet written (recorded here so the queue is visible;
each becomes a numbered ADR when made):

- **Publishing strategy** — published versioned brick vs. `force-include`, and
  interface-as-semver. Deferred until a real external consumer needs a versioned
  dependency.
