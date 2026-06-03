"LSP lifecycle builtins for the dispatch engine.

Implements the LSP server lifecycle (initialize / initialized / shutdown / exit)
and routes `workspace/executeCommand` to the dispatch spine's command handler.
Exposed as the data map `BUILTINS`, which the LSP `make-server` injects into a
dispatch server. This is the LSP-specific complement to the transport-agnostic
dispatch spine: the spine knows nothing about `initialize`; lifecycle is data.
"

(import thyforce.dispatch.core :as spine)
(import thyforce.dispatch.jsonrpc [response])

(defn _update-lifecycle [server updates]
  (setv state (dict (get server "state")))
  (setv lifecycle (dict (.get state "lifecycle" {})))
  (for [[key value] (.items updates)]
    (setv (get lifecycle key) value))
  (setv (get state "lifecycle") lifecycle)
  (spine.with-state server state))

(defn _initialize-result [server]
  {"capabilities" (get server "capabilities")
   "serverInfo" {"name" (get server "name")
                 "version" (get server "version")}})

(defn handle-initialize [server message has-id]
  (setv params (or (.get message "params") {}))
  (setv next-server
    (_update-lifecycle
      server
      {"initializeParams" params
       "initialized" False
       "shutdown" False
       "exiting" False}))
  {"server" next-server
   "messages" (if has-id [(response (.get message "id" None) (_initialize-result next-server))] [])})

(defn handle-initialized [server message has-id]
  {"server" (_update-lifecycle server {"initialized" True}) "messages" []})

(defn handle-shutdown [server message has-id]
  {"server" (_update-lifecycle server {"shutdown" True})
   "messages" (if has-id [(response (.get message "id" None) None)] [])})

(defn handle-exit [server message has-id]
  {"server" (_update-lifecycle server {"exiting" True}) "messages" []})

(setv BUILTINS
  {"initialize" handle-initialize
   "initialized" handle-initialized
   "shutdown" handle-shutdown
   "exit" handle-exit
   "workspace/executeCommand" spine.dispatch-command})
