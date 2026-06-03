# 0002. Extract a transport-agnostic dispatch spine from the LSP engine

- Status: Accepted
- Date: 2026-06-01

## Context

`lsp/engine` commingled two things: a generic message-dispatch core (a registry
of handlers, effects-as-data, immutable state threading, a JSON-RPC envelope) and
LSP-specific concerns (the `initialize`/`initialized`/`shutdown`/`exit` lifecycle,
`workspace/executeCommand` routing, Content-Length framing, text-document state,
LSP data shapes). The lifecycle was **hardcoded** in `dispatch-message`'s `cond`.

A second dispatch consumer then appeared — the `events` instance (ADR work in
this session) — which records inbound events as facts. It needed only the generic
feature-registry path and no lifecycle, yet it imported `thyforce.lsp.engine`,
which is semantically wrong: an event recorder is not a language server.

With two genuinely different instances in hand — LSP (request/response +
notifications + a rich lifecycle) and events (fire-and-forget + persistence, no
lifecycle) — the boundary between "generic spine" and "LSP layer" could be drawn
from evidence rather than guessed from one example.

## Decision

Extract a flat component **`thyforce/dispatch`** as the transport-agnostic spine,
and reduce `lsp/engine` to an LSP layer built on top of it.

### `thyforce/dispatch` (the spine)

Internal modules:

- `registry.hy` — registry data model, spec constructors, authoring macros
  (`defregistry`, `on-request`, `on-notification`, `on-command`), and validation.
  Renamed from `spec.hy` to avoid colliding with the `thyforce/spec` validation
  component.
- `jsonrpc.hy` — JSON-RPC 2.0 message constructors and error codes. The spine
  owns this because **both** instances speak JSON-RPC.
- `core.hy` — server-map generation, effects-as-data, immutable state threading,
  command dispatch, and a **table-driven** `dispatch-message`.

### Lifecycle-as-data

`dispatch-message` routes a method in this order: (1) a `builtins` map supplied by
the caller — `method -> (server message has-id) -> {server, messages}`; (2) a
registry feature; (3) method-not-found. The spine hardcodes **no** lifecycle. A
protocol layer supplies its lifecycle and command routing as data via `builtins`.

### `lsp/engine` (the LSP layer)

Depends on `dispatch`. Adds:

- `lifecycle.hy` — the LSP lifecycle handlers and `workspace/executeCommand`
  routing, exposed as the `BUILTINS` data map.
- `protocol.hy`, `workspace.hy`, `stdio.hy` — LSP data shapes, text-document
  state, and Content-Length framing (the spine's transport is framing-agnostic;
  Content-Length stays here because `events` uses line-delimited transport).
- `make-server` — builds a dispatch server and injects `lifecycle.BUILTINS`; also
  re-exports the spine surface for callers that go through the engine.

### Dependency graph after extraction

```
dispatch        -> (none)
spec            -> (none)
store           -> spec
lsp/engine      -> dispatch
lsp/analyzer    -> spec
lsp/providers   -> dispatch, lsp/analyzer, lsp/engine
lsp/server      -> lsp/engine, lsp/providers
events/recorder -> dispatch, store        (no longer lsp/engine)
events/console  -> dispatch, events/recorder, store
```

## Consequences

- **+** Adapters are thin and correctly placed: a non-LSP instance reuses the
  spine with zero LSP coupling. `events/recorder` no longer imports `lsp/engine`.
- **+** Lifecycle is pluggable data; a new protocol registers its own `builtins`
  rather than editing the dispatch core.
- **+** The dependency graph now reflects reality, and `polhy check` enforces it
  (no cycles, no dangling intra-namespace refs).
- **+** The spine has its own test brick (`tests/thyforce/dispatch`) proving it
  works standalone, including that lifecycle is data.
- **−** One more component, plus a thin re-export layer in `lsp/engine`.
- **−** `dispatch` (and, for event adapters, `store`) join every dependent
  project's `force-include` set; project closures grow accordingly.

## Validation

Triangulated against both instances and verified end-to-end:

- LSP: 36 engine + 13 providers + 1 stdio e2e tests green on the extracted spine.
- events: 4 tests green; the recorder builds on the bare spine (no lifecycle).
- spine: 8 tests green, including `test-lifecycle-is-data-not-hardcoded`.
- The shipped `hyground` entrypoint was driven through a real
  `initialize`/`initialized`/`shutdown`/`exit` handshake and returned full
  capabilities + `serverInfo` (exit 0).
- `polhy sync` regenerated `projects/hyground` to force-include `dispatch`;
  `polhy check` is clean.
