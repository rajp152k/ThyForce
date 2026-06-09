"Stdin transport that feeds JSON events into the recorder dispatch server."

(import sys argparse json)
(import thyforce.events.recorder.core :as recorder)
(import thyforce.dispatch.core :as engine)
(import thyforce.store.core :as store)

(defn run [server lines [emit print]]
  "Dispatch each non-blank JSON line from LINES through SERVER; return final server."
  (setv current server)
  (for [line lines]
    (setv text (.strip line))
    (when text
      (setv result (engine.dispatch-json current text))
      (setv current (get result "server"))
      (for [message (get result "messages")]
        (emit (json.dumps message)))))
  current)

(defn main [[argv None]]
  (setv parser (argparse.ArgumentParser :prog "events"))
  (setv parser.description "Record stdin JSON events as facts via the dispatch engine")
  (.add-argument parser "--db" :default ":memory:" :help "sqlite path (default: in-memory)")
  (setv args (.parse-args parser argv))
  (setv s (store.open-store {"backend" "sqlite" "path" args.db}))
  (try
    (run (recorder.make-server s) sys.stdin)
    (finally (store.close-store s))))
