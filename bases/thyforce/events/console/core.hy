"Console event driver: feed events on stdin, dispatch them, record facts.

A thin transport adapter over the `events/recorder` dispatch instance. Each
non-blank stdin line is one JSON message `{\"method\" \"params\" [\"id\"]}`; the
driver threads server state across lines (reusing the engine's JSON dispatch) and
prints any response messages. No LSP lifecycle is involved.
"

(import sys argparse json)
(import thyforce.events.recorder.core :as recorder)
(import thyforce.lsp.engine.core :as engine)
(import thyforce.store.core :as store)

(defn run [server lines [emit print]]
  "Dispatch each non-blank line of LINES as a JSON message; return final server.

EMIT receives each outbound response message as a JSON string (default: print).
  "
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
