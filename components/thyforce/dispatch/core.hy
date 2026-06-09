"Transport-agnostic dispatch engine: registries, effects, and immutable state."

(import thyforce.dispatch.jsonrpc [response error-response PARSE-ERROR METHOD-NOT-FOUND INVALID-REQUEST INTERNAL-ERROR])
(import thyforce.dispatch.registry [assert-valid-registry])
(import json)

(setv MISSING (object))

(defn merge-maps [#* maps]
  "Recursively merge dictionaries from left to right."
  (setv out {})
  (for [mapping maps]
    (when mapping
      (for [[key value] (.items mapping)]
        (if (and (isinstance value dict) (isinstance (.get out key) dict))
            (setv (get out key) (merge-maps (.get out key) value))
            (setv (get out key) value)))))
  out)

(defn _command-capabilities [commands]
  (if commands
      {"executeCommandProvider" {"commands" (list (sorted (.keys commands)))}}
      {}))

(defn _index-registry [registry]
  (setv features {})
  (setv commands {})
  (setv capabilities {})
  (for [spec registry]
    (setv kind (.get spec "kind"))
    (cond
      (= kind "command")
        (setv (get commands (get spec "command")) spec)
      (in kind ["request" "notification"])
        (do
          (setv (get features (get spec "method")) spec)
          (setv capabilities (merge-maps capabilities (.get spec "capability" {}))))
      True
        (raise (ValueError (.format "unknown spec kind: {!r}" kind)))))
  [features commands (merge-maps capabilities (_command-capabilities commands))])

(defn make-server [name version registry handlers [state None] [capabilities None] [metadata None] [strict-handlers True]]
  "Build and return a runtime server map from registry data and handler functions."
  (setv handler-map (or handlers {}))
  (assert-valid-registry registry handler-map strict-handlers)
  (setv [features commands registry-capabilities] (_index-registry registry))
  {"engine/type" "server"
   "name" (str name)
   "version" (str version)
   "metadata" (or metadata {})
   "registry" (tuple registry)
   "features" features
   "commands" commands
   "builtins" {}
   "handlers" handler-map
   "state" (if (is state None) {} state)
   "capabilities" (merge-maps (or capabilities {}) registry-capabilities)})

(defn with-state [server state]
  "Return a shallowly copied server map with replacement state."
  (setv out (dict server))
  (setv (get out "state") state)
  out)

(defn update-state [server updates]
  "Return a server whose state is merged with `updates`."
  (with-state server (merge-maps (get server "state") updates)))

(defn effect [[result None] [state MISSING] [notifications None]]
  "Wrap a handler result with optional state replacement and notifications."
  (setv out {"engine/effect" True "result" result})
  (when (is-not state MISSING)
    (setv (get out "state") state))
  (when (is-not notifications None)
    (setv (get out "notifications") notifications))
  out)

(defn handlers-from-namespace [namespace registry]
  "Collect handlers named by registry specs from a module/object or mapping."
  (setv out {})
  (for [spec registry]
    (setv name (get spec "handler"))
    (when (not (callable name))
      (setv value MISSING)
      (setv python-name (.replace name "-" "_"))
      (if (isinstance namespace dict)
          (do
            (when (in name namespace)
              (setv value (get namespace name)))
            (when (and (is value MISSING) (in python-name namespace))
              (setv value (get namespace python-name))))
          (do
            (when (hasattr namespace name)
              (setv value (getattr namespace name)))
            (when (and (is value MISSING) (hasattr namespace python-name))
              (setv value (getattr namespace python-name)))))
      (when (is-not value MISSING)
        (setv (get out name) value))))
  out)

(defn _result-messages [id has-id result notifications]
  (setv messages [])
  (when has-id
    (.append messages (response id result)))
  (for [message (or notifications [])]
    (.append messages message))
  messages)

(defn _error-result [server id has-id code message [data None] [force False]]
  {"server" server
   "messages" (if (or has-id force) [(error-response id code message data)] [])})

(defn _normalize-output [server value]
  (setv next-server server)
  (setv result value)
  (setv notifications [])
  (when (and (isinstance value dict) (.get value "engine/effect"))
    (setv result (.get value "result"))
    (setv notifications (or (.get value "notifications") []))
    (when (in "state" value)
      (setv next-server (with-state server (get value "state")))))
  {"server" next-server "result" result "notifications" notifications})

(defn _resolve-handler [server spec]
  (setv name (get spec "handler"))
  (if (callable name)
      name
      (do
        (setv handlers (get server "handlers"))
        (when (not (in name handlers))
          (raise (KeyError (.format "handler {!r} is not installed" name))))
        (get handlers name))))

(defn _event [server message spec [extra None]]
  (merge-maps
    {"server" server
     "state" (get server "state")
     "message" message
     "method" (.get message "method")
     "params" (.get message "params" {})
     "spec" spec}
    (or extra {})))

(defn _dispatch-spec [server message spec has-id]
  (setv id (.get message "id" None))
  (try
    (setv handler (_resolve-handler server spec))
    (setv value (handler (_event server message spec)))
    (setv normalized (_normalize-output server value))
    {"server" (get normalized "server")
     "messages" (_result-messages id has-id (get normalized "result") (get normalized "notifications"))}
    (except [exc Exception]
      (_error-result
        server id has-id INTERNAL-ERROR (str exc)
        {"exception" (getattr (type exc) "__name__")}))))

(defn dispatch-command [server message has-id]
  "Dispatch a registered command named by the message params `command` key."
  (setv id (.get message "id" None))
  (setv params (or (.get message "params") {}))
  (setv name (.get params "command"))
  (setv spec (.get (get server "commands") name))
  (when (is spec None)
    (return (_error-result server id has-id METHOD-NOT-FOUND (.format "unknown command: {}" name))))
  (try
    (setv handler (_resolve-handler server spec))
    (setv value (handler (_event server message spec {"command" name "arguments" (.get params "arguments" [])})))
    (setv normalized (_normalize-output server value))
    {"server" (get normalized "server")
     "messages" (_result-messages id has-id (get normalized "result") (get normalized "notifications"))}
    (except [exc Exception]
      (_error-result
        server id has-id INTERNAL-ERROR (str exc)
        {"exception" (getattr (type exc) "__name__")}))))

(defn dispatch-message [server message]
  "Dispatch one parsed JSON-RPC message against a server map; return `server` and `messages`."
  (when (not (isinstance message dict))
    (return {"server" server
             "messages" [(error-response None INVALID-REQUEST "message must be a JSON object")]}))
  (setv has-id (in "id" message))
  (setv id (.get message "id" None))
  (when (and (in "jsonrpc" message) (!= (get message "jsonrpc") "2.0"))
    (return (_error-result server id has-id INVALID-REQUEST "jsonrpc must be '2.0'" None True)))
  (setv method (.get message "method"))
  (when (is method None)
    (return (_error-result server id has-id INVALID-REQUEST "message is missing method" None True)))
  (setv builtins (.get server "builtins" {}))
  (cond
    (in method builtins)
      ((get builtins method) server message has-id)
    (in method (get server "features"))
      (_dispatch-spec server message (get (get server "features") method) has-id)
    True
      (_error-result server id has-id METHOD-NOT-FOUND (.format "unknown method: {}" method))))

(defn dispatch [server messages]
  "Dispatch a single message or a JSON-RPC batch, threading server state."
  (if (isinstance messages list)
      (do
        (when (= (len messages) 0)
          (return {"server" server
                   "messages" [(error-response None INVALID-REQUEST "empty JSON-RPC batch")]}))
        (setv current server)
        (setv outbound [])
        (for [message messages]
          (setv result (dispatch-message current message))
          (setv current (get result "server"))
          (.extend outbound (get result "messages")))
        {"server" current "messages" outbound})
      (dispatch-message server messages)))

(defn dispatch-json [server payload]
  "Parse and dispatch a JSON-RPC payload from bytes or text."
  (try
    (setv text (if (isinstance payload bytes) (.decode payload "utf-8") payload))
    (dispatch server (json.loads text))
    (except [exc Exception]
      {"server" server
       "messages" [(error-response None PARSE-ERROR "parse error" {"exception" (getattr (type exc) "__name__")})]})))
