"Tests for the events dispatch instance (events/recorder + events/console).

This is the engine's second consumer. Coverage: a notification handler's store
side effect, immutable state threading across dispatches, a request reading
threaded state, the console transport threading + persisting a line stream, and
unknown-event rejection. Run: `hy tests/thyforce/events/test_events.hy`.
"

(import json)
(import hy)
(import thyforce.events.recorder.core :as recorder)
(import thyforce.events.console.core :as console)
(import thyforce.lsp.engine.core :as engine)
(import thyforce.store.core :as store)

(defn assert= [actual expected]
  (assert (= actual expected) f"expected {expected !r}, got {actual !r}"))

(defn fresh []
  (setv s (store.open-store {"backend" "memory"}))
  [s (recorder.make-server s)])

(defn test-record-fact-persists-and-threads-count []
  (setv [s server] (fresh))
  (try
    (setv result (engine.dispatch server {"method" "fact/record"
                                           "params" {"type" "note" "data" {"text" "hi"}}}))
    (setv server (get result "server"))
    ;; a notification produces no response messages
    (assert= (get result "messages") [])
    ;; the handler's side effect persisted exactly one fact
    (setv facts (store.read-facts s))
    (assert= (len facts) 1)
    (assert= (get (get facts 0) "type") "note")
    (assert= (get (get (get facts 0) "data") "text") "hi")
    ;; the effect threaded an incremented count into server state
    (assert= (.get (get server "state") "count") 1)
    (finally (store.close-store s))))

(defn test-count-request-reads-threaded-state []
  (setv [s server] (fresh))
  (try
    (for [_ (range 3)]
      (setv server (get (engine.dispatch server {"method" "fact/record"
                                                 "params" {"type" "e" "data" {}}}) "server")))
    (setv messages (get (engine.dispatch server {"method" "fact/count" "id" 7}) "messages"))
    (assert= (len messages) 1)
    (assert= (get (get messages 0) "id") 7)
    (assert= (get (get (get messages 0) "result") "count") 3)
    (finally (store.close-store s))))

(defn test-console-run-threads-and-persists []
  (setv s (store.open-store {"backend" "memory"}))
  (setv server (recorder.make-server s))
  (setv out [])
  (setv lines [(json.dumps {"method" "fact/record" "params" {"type" "a" "data" {"n" 1}}})
               ""
               (json.dumps {"method" "fact/record" "params" {"type" "b" "data" {"n" 2}}})
               (json.dumps {"method" "fact/count" "id" 1})])
  (try
    (console.run server lines out.append)
    ;; both records persisted, in line order; blank line skipped
    (assert= (lfor f (store.read-facts s) (get f "type")) ["a" "b"])
    ;; only the request produced an emitted response
    (assert= (len out) 1)
    (assert= (get (get (json.loads (get out 0)) "result") "count") 2)
    (finally (store.close-store s))))

(defn test-unknown-event-returns-error []
  (setv [s server] (fresh))
  (try
    (setv msg (get (get (engine.dispatch server {"method" "fact/nope" "id" 1}) "messages") 0))
    (assert (in "error" msg))
    (finally (store.close-store s))))

(defn run-tests []
  (setv tests (sorted (list (gfor item (globals) :if (.startswith item "test_") item))))
  (setv failures [])
  (for [name tests]
    (try
      ((get (globals) name))
      (print f"ok {name}")
      (except [e Exception]
        (.append failures [name e])
        (print f"FAIL {name}: {e !r}"))))
  (when failures
    (raise (AssertionError f"{(len failures)} test(s) failed")))
  (print f"{(len tests)} Hy tests passed"))

(when (= __name__ "__main__")
  (run-tests))
