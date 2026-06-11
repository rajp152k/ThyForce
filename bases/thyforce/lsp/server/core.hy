"HyGround language-server entrypoint."

(import sys)
(import argparse)
(import thyforce.lsp.providers.core :as service)
(import thyforce.lsp.engine.stdio :as stdio)

(setv VERSION "0.1.0")

(defn serve [[input-stream None] [output-stream None]]
  "Serve a HyGround server over the given binary streams (defaults: stdio)."
  (stdio.serve (service.make-server "hyground" VERSION)
               (or input-stream sys.stdin.buffer)
               (or output-stream sys.stdout.buffer)))

(defn main [[argv None]]
  (setv parser (argparse.ArgumentParser :prog "hyground"))
  (setv parser.description "HyGround - a principled Hy language server")
  (.add-argument parser "--version" :action "store_true" :help "print version and exit")
  (setv args (.parse-args parser argv))
  (when args.version
    (print f"hyground {VERSION}")
    (return))
  (serve))
