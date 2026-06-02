(import hy)
(import io)
(import thyforce.service.cli.core :as cli)
(import thyforce.lsp.stdio :as stdio)

(defn assert= [actual expected]
  (assert (= actual expected) f"Expected {expected !r}, got {actual !r}"))
(defn assert-true [value]
  (assert value f"Expected truthy, got {value !r}"))

(defn frame [msg] (stdio.encode-message msg))

(defn decode-all [data]
  (setv stream (io.BytesIO data))
  (setv out [])
  (while True
    (setv m (stdio.read-message stream))
    (when (is m None) (break))
    (.append out m))
  out)

(defn by-id [messages id]
  (next (gfor m messages :if (= (.get m "id") id) m) None))

(defn by-method [messages method]
  (list (gfor m messages :if (= (.get m "method") method) m)))

(defn test-stdio-session-end-to-end []
  (setv uri "file:///workspace/main.hy")
  (setv src "(defn greet [name]\n  \"Say hi.\"\n  (greet name))\n")
  (setv input-stream
    (io.BytesIO
      (+ (frame {"jsonrpc" "2.0" "id" 1 "method" "initialize" "params" {}})
         (frame {"jsonrpc" "2.0" "method" "initialized"})
         (frame {"jsonrpc" "2.0" "method" "textDocument/didOpen"
                 "params" {"textDocument" {"uri" uri "text" src "languageId" "hy" "version" 1}}})
         (frame {"jsonrpc" "2.0" "id" 2 "method" "textDocument/hover"
                 "params" {"textDocument" {"uri" uri} "position" {"line" 2 "character" 4}}})
         (frame {"jsonrpc" "2.0" "id" 3 "method" "textDocument/definition"
                 "params" {"textDocument" {"uri" uri} "position" {"line" 2 "character" 4}}})
         (frame {"jsonrpc" "2.0" "id" 4 "method" "shutdown"})
         (frame {"jsonrpc" "2.0" "method" "exit"}))))
  (setv output-stream (io.BytesIO))
  (setv final-server (cli.serve input-stream output-stream))
  (setv messages (decode-all (.getvalue output-stream)))

  ;; initialize
  (setv init (by-id messages 1))
  (assert-true (is-not init None))
  (assert= (get (get (get init "result") "serverInfo") "name") "hyground")
  (assert-true (in "hoverProvider" (get (get init "result") "capabilities")))

  ;; diagnostics published on didOpen
  (setv diags (by-method messages "textDocument/publishDiagnostics"))
  (assert-true (> (len diags) 0))
  (assert= (get (get (get diags 0) "params") "uri") uri)

  ;; hover
  (setv hov (by-id messages 2))
  (assert-true (in "(greet [name])" (get (get (get hov "result") "contents") "value")))

  ;; definition
  (setv defn-resp (by-id messages 3))
  (assert= (get (get (get defn-resp "result") 0) "uri") uri)

  ;; shutdown acknowledged, lifecycle recorded
  (setv sd (by-id messages 4))
  (assert-true (is-not sd None))
  (assert= (get (get (get final-server "state") "lifecycle") "exiting") True))

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
  (print f"{(len tests)} Hy cli e2e tests passed"))

(when (= __name__ "__main__")
  (run-tests))
