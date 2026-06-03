# 0000. Record architecture decisions

- Status: Accepted
- Date: 2026-06-01

## Context

ThyForce is a long-running personal Polylith monorepo that accumulates reusable
engineering capabilities over years. Decisions that shape the architecture — the
dispatch spine, the persistence model, deployment topology, publishing strategy —
are made once and depended on for a long time. Without a durable record, the
*reasons* behind a decision evaporate: future-me re-litigates settled questions,
or worse, silently violates a constraint whose rationale was never written down.

The repository already treats its own evolution as event-sourced (facts →
projections). The same discipline should apply to architecture: each decision is
a fact, recorded when made, never rewritten after the fact.

## Decision

Use **Architecture Decision Records (ADRs)** in the
[Michael Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

- ADRs live in `decisions/` as `NNNN-kebab-case-title.md`, four-digit
  zero-padded, monotonically increasing. `0000` is this record.
- Every ADR has: **Title**, **Status**, **Date**, **Context**, **Decision**,
  **Consequences**.
- Status lifecycle: `Proposed` → `Accepted` → (`Deprecated` | `Superseded by NNNN`).
  - `Proposed` means the decision is written down but not yet validated/agreed.
  - A `Proposed` ADR that drives an implementation flips to `Accepted` only once
    that implementation exists and confirms the decision (decide on paper, then
    prove with the thinnest real slice).
- ADRs are **append-only facts**. An `Accepted` ADR is immutable except for its
  Status line. To change a decision, write a *new* ADR that supersedes it and set
  the old one's status to `Superseded by NNNN`. Never rewrite the reasoning of an
  accepted record — the chain of superseding ADRs *is* the history.
- `decisions/index.md` lists every ADR with its current status.
- ADRs are versioned in the same repo and branch as the code they govern, so a
  checkout carries its own rationale.

This is deliberately low-ceremony: plain markdown, no tooling. An `adr` brick is
*not* warranted — the cost of a directory and a template is near zero, and a
microcomponent to manage four files would violate the workspace's own rule
against premature abstraction.

## Consequences

- Rationale is durable, greppable, and travels with the code.
- The supersede-don't-edit rule keeps a truthful history of how the architecture
  evolved, rather than a smoothed-over "current truth".
- Small per-decision overhead: a decision worth depending on is worth a page.
- Markdown (not `.cfg.hy`) is correct here: ADRs are narrative prose, not
  application/tooling behavior. The `.cfg.hy` policy governs *behavior config*,
  which an ADR is not.
