"Data model and Hy macros for dispatch registries.

The public constructors return ordinary Python dictionaries. Macros are only a
compact authoring layer over the same dictionaries; they do not hide runtime
registration side effects.
"

(defn _handler-name [handler]
  "Return a stable registry name for a handler reference."
  (if (callable handler)
      (getattr handler "__name__")
      (str handler)))

(defn _non-empty-string [value field]
  (setv text (str value))
  (when (= (.strip text) "")
    (raise (ValueError (.format "{} must not be empty" field))))
  text)

(defn _without-none [mapping]
  (setv out {})
  (for [[key value] (.items mapping)]
    (when (is-not value None)
      (setv (get out key) value)))
  out)

(defn make-feature [method handler [kind "request"] [options None] [capability None] [doc None] [metadata None]]
  "Build a normalized request/notification feature spec."
  (when (not (in kind ["request" "notification"]))
    (raise (ValueError (.format "feature kind must be 'request' or 'notification', got {!r}" kind))))
  (when (and (is-not capability None) (not (isinstance capability dict)))
    (raise (TypeError "capability must be a mapping when provided")))
  (_without-none
    {"kind" kind
     "method" (_non-empty-string method "method")
     "handler" (_handler-name handler)
     "options" options
     "capability" capability
     "doc" doc
     "metadata" metadata}))

(defn request [method handler [options None] [capability None] [doc None] [metadata None]]
  "Describe a request handler as data."
  (make-feature method handler "request" options capability doc metadata))

(defn notification [method handler [options None] [capability None] [doc None] [metadata None]]
  "Describe a notification handler as data."
  (make-feature method handler "notification" options capability doc metadata))

(defn command [name handler [doc None] [metadata None]]
  "Describe a command handler as data."
  (_without-none
    {"kind" "command"
     "command" (_non-empty-string name "command")
     "handler" (_handler-name handler)
     "doc" doc
     "metadata" metadata}))

(defn registry [#* specs]
  "Return an immutable registry tuple from zero or more specs.

Use `combine-registries` when composing existing registries; `registry` keeps the
call site explicit and simply freezes the supplied specs.
  "
  (tuple specs))

(defn combine-registries [#* registries]
  "Compose any number of registry tuples into one registry tuple."
  (setv out [])
  (for [items registries]
    (for [spec items]
      (.append out spec)))
  (tuple out))

(defn handler-names [registry]
  "Return unique handler names referenced by a registry, preserving order."
  (setv seen (set))
  (setv out [])
  (for [spec registry]
    (when (and (isinstance spec dict) (in "handler" spec))
      (setv name (get spec "handler"))
      (when (and (not (callable name)) (not (in name seen)))
        (.add seen name)
        (.append out name))))
  out)

(defn _issue [code message [spec None]]
  (setv out {"code" code "message" message})
  (when (is-not spec None)
    (setv (get out "spec") spec))
  out)

(defn _validate-spec-shape [spec]
  (setv issues [])
  (when (not (isinstance spec dict))
    (return [(_issue "invalid-spec" "registry entries must be dictionaries" spec)]))
  (setv kind (.get spec "kind"))
  (cond
    (in kind ["request" "notification"])
      (do
        (when (not (and (in "method" spec) (isinstance (get spec "method") str) (!= (.strip (get spec "method")) "")))
          (.append issues (_issue "invalid-method" "feature specs require a non-empty string method" spec)))
        (when (not (in "handler" spec))
          (.append issues (_issue "missing-handler" "feature specs require a handler" spec)))
        (when (and (in "capability" spec) (not (isinstance (get spec "capability") dict)))
          (.append issues (_issue "invalid-capability" "capability must be a mapping" spec))))
    (= kind "command")
      (do
        (when (not (and (in "command" spec) (isinstance (get spec "command") str) (!= (.strip (get spec "command")) "")))
          (.append issues (_issue "invalid-command" "command specs require a non-empty string command" spec)))
        (when (not (in "handler" spec))
          (.append issues (_issue "missing-handler" "command specs require a handler" spec))))
    True
      (.append issues (_issue "invalid-kind" (.format "unknown spec kind: {!r}" kind) spec)))
  issues)

(defn validate-registry [registry [handlers None] [require-handlers False]]
  "Return validation issue maps for a registry.

Validation is pure: it does not mutate the registry and does not import handler
modules. Set `require-handlers` with a handler mapping to catch missing runtime
functions before serving.
  "
  (setv issues [])
  (setv features {})
  (setv commands {})
  (for [spec registry]
    (.extend issues (_validate-spec-shape spec))
    (when (not (isinstance spec dict))
      (continue))
    (setv kind (.get spec "kind"))
    (when (in kind ["request" "notification"])
      (setv method (.get spec "method"))
      (when (and (isinstance method str) (!= (.strip method) ""))
        (when (in method features)
          (.append issues (_issue "duplicate-method" (.format "duplicate feature method: {}" method) spec)))
        (setv (get features method) spec)))
    (when (= kind "command")
      (setv name (.get spec "command"))
      (when (and (isinstance name str) (!= (.strip name) ""))
        (when (in name commands)
          (.append issues (_issue "duplicate-command" (.format "duplicate command: {}" name) spec)))
        (setv (get commands name) spec)))
    (when (and require-handlers (in "handler" spec))
      (setv handler-map (or handlers {}))
      (setv handler (get spec "handler"))
      (when (and (not (callable handler)) (not (in handler handler-map)))
        (.append issues (_issue "missing-handler" (.format "handler is not installed: {}" handler) spec)))))
  issues)

(defn assert-valid-registry [registry [handlers None] [require-handlers False]]
  "Raise ValueError if registry validation finds any issue; return registry otherwise."
  (setv issues (validate-registry registry handlers require-handlers))
  (when issues
    (raise (ValueError (.join "; " (lfor issue issues (get issue "message"))))))
  registry)

(defmacro defregistry [name #* specs]
  "Define a registry value from inline feature specs."
  `(do
     (import thyforce.dispatch.registry)
     (setv ~name (thyforce.dispatch.registry.registry ~@specs))))

(defmacro on-request [method handler #* args]
  "Macro sugar for a request spec; stores the handler symbol as data."
  `(do
     (import thyforce.dispatch.registry)
     (thyforce.dispatch.registry.request ~method ~(str handler) ~@args)))

(defmacro on-notification [method handler #* args]
  "Macro sugar for a notification spec; stores the handler symbol as data."
  `(do
     (import thyforce.dispatch.registry)
     (thyforce.dispatch.registry.notification ~method ~(str handler) ~@args)))

(defmacro on-command [name handler #* args]
  "Macro sugar for a command spec; stores the handler symbol as data."
  `(do
     (import thyforce.dispatch.registry)
     (thyforce.dispatch.registry.command ~name ~(str handler) ~@args)))
