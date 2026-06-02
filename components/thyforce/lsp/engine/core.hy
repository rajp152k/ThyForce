"Public entry module for the generic LSP engine.

The engine is a data-first Language Server Protocol engine-generation framework:
registries and server state are plain dictionaries, dispatch threads state
immutably, and transport is isolated from server generation.

Submodules form the public surface and are re-exported here:

- `spec`      registry data model + authoring macros + validation
- `server`    server-map generation, dispatch, lifecycle, effects
- `jsonrpc`   JSON-RPC 2.0 message constructors and error codes
- `stdio`     LSP Content-Length framing and the serve loop
- `workspace` generic document state + position/offset conversions
- `protocol`  LSP data-shape helpers (positions, ranges, diagnostics, capabilities)

Macros (`defregistry`, `on-request`, `on-notification`, `on-command`) must be
required directly from `thyforce.lsp.engine.spec`, since Hy macros are required, not
imported.
"

(import thyforce.lsp.engine.spec :as spec)
(import thyforce.lsp.engine.server :as server)
(import thyforce.lsp.engine.jsonrpc :as jsonrpc)
(import thyforce.lsp.engine.stdio :as stdio)
(import thyforce.lsp.engine.workspace :as workspace)
(import thyforce.lsp.engine.protocol :as protocol)

;; Most-used entry points, surfaced flat for ergonomics.
(setv make-server server.make-server)
(setv dispatch server.dispatch)
(setv dispatch-message server.dispatch-message)
(setv dispatch-json server.dispatch-json)
(setv effect server.effect)
(setv handlers-from-namespace server.handlers-from-namespace)
(setv registry spec.registry)
(setv combine-registries spec.combine-registries)
(setv validate-registry spec.validate-registry)
(setv assert-valid-registry spec.assert-valid-registry)
(setv serve stdio.serve)
