"LSP engine: the dispatch spine plus LSP lifecycle, transport, and protocol.
This is the LSP-specific layer over `thyforce/dispatch`. `make-server` builds a
dispatch server and injects the LSP lifecycle `builtins` (initialize, shutdown,
exit, executeCommand). The generic dispatch surface is re-exported for callers;
LSP data shapes live in the submodules `lifecycle`, `stdio`, `workspace`, and
`protocol`.
Registry authoring macros (`defregistry`, `on-request`, `on-notification`,
`on-command`) must be required directly from `thyforce.dispatch.registry`.
"
(import thyforce.dispatch.core :as spine)
(import thyforce.dispatch.registry :as reg)
(import thyforce.dispatch.jsonrpc :as jsonrpc)
(import thyforce.lsp.engine.lifecycle :as lifecycle)
(import thyforce.lsp.engine.stdio :as stdio)
(import thyforce.lsp.engine.workspace :as workspace)
(import thyforce.lsp.engine.protocol :as protocol)
(defn make-server [name version registry handlers [state None] [capabilities None] [metadata None] [strict-handlers True]]
  "Build an LSP server: a dispatch server with LSP lifecycle builtins injected."
  (setv server (spine.make-server name version registry handlers
                 :state state :capabilities capabilities :metadata metadata
                 :strict-handlers strict-handlers))
  (setv out (dict server))
  (setv (get out "builtins") lifecycle.BUILTINS)
  out)
;; Re-export the dispatch spine surface for callers that go through the engine.
(setv dispatch spine.dispatch)
(setv dispatch-message spine.dispatch-message)
(setv dispatch-json spine.dispatch-json)
(setv effect spine.effect)
(setv handlers-from-namespace spine.handlers-from-namespace)
(setv with-state spine.with-state)
(setv update-state spine.update-state)
(setv merge-maps spine.merge-maps)
(setv dispatch-command spine.dispatch-command)
(setv registry reg.registry)
(setv combine-registries reg.combine-registries)
(setv validate-registry reg.validate-registry)
(setv assert-valid-registry reg.assert-valid-registry)
(setv serve stdio.serve)