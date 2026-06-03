"Event recorder: a non-LSP dispatch instance that records events as facts.

Builds an lsp-engine server (registry + handlers) whose handlers append facts to
a `thyforce/store` instance carried in server state. This is the engine's second
consumer: it uses only the generic feature-registry dispatch path (no LSP
lifecycle), demonstrating that the dispatch core generalises beyond language
servers. State is threaded immutably by the engine; the store write is the
handler's side effect.
"

(import thyforce.dispatch.core :as engine)
(import thyforce.dispatch.registry :as feature)
(import thyforce.store.core :as store)

(setv VERSION "0.1.0")

(setv REGISTRY
  (feature.registry
    (feature.notification "fact/record" "record-fact")
    (feature.request "fact/count" "count-facts")))

(defn record-fact [event]
  "Append the event params as a fact; thread an incremented count in state."
  (setv state (get event "state"))
  (setv params (get event "params"))
  (setv fact (store.append-fact (get state "store")
                                {"type" (.get params "type" "event")
                                 "data" (.get params "data" {})}))
  (setv next-state (dict state))
  (setv (get next-state "count") (+ (.get state "count" 0) 1))
  (engine.effect :result fact :state next-state))

(defn count-facts [event]
  "Return the number of facts recorded so far (read from threaded state)."
  {"count" (.get (get event "state") "count" 0)})

(defn handlers []
  {"record-fact" record-fact "count-facts" count-facts})

(defn make-server [store-instance]
  "Build a dispatch server that records inbound events into STORE-INSTANCE."
  (engine.make-server "events" VERSION REGISTRY (handlers)
                      :state {"store" store-instance "count" 0}))
