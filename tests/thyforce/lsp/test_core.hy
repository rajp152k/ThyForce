(import io)
(import hy)
(import thyforce.lsp.spec :as spec)
(import thyforce.lsp.server :as server)
(import thyforce.lsp.jsonrpc :as jsonrpc)
(import thyforce.lsp.stdio :as stdio)
(import thyforce.lsp.workspace :as ws)
(import thyforce.lsp.protocol :as proto)
(require thyforce.lsp.spec [defregistry on-request on-notification on-command])

;; ---------------------------------------------------------------------------
;; fixture registry (mirrors the engine's example server surface)
;; ---------------------------------------------------------------------------

(defn hover [event] {"contents" "hi"})
(defn did-open [event] None)
(defn ping [event] {"args" (.get event "arguments" [])})

(defregistry REGISTRY
  (on-request "textDocument/hover" hover
    :capability {"hoverProvider" True})
  (on-request "textDocument/completion" hover
    :capability {"completionProvider" (proto.completion-options :trigger-characters ["."])})
  (on-notification "textDocument/didOpen" did-open)
  (on-command "example.ping" ping))

(defn fixture-server []
  (server.make-server "fixture" "1.0.0" REGISTRY
    (server.handlers-from-namespace (globals) REGISTRY)))

;; ---------------------------------------------------------------------------
;; helpers
;; ---------------------------------------------------------------------------

(defn assert= [actual expected]
  (assert (= actual expected) f"Expected {expected!r}, got {actual!r}"))

(defn assert-raises [exc-type substring thunk]
  (try
    (thunk)
    (raise (AssertionError f"Expected {exc-type!r} to be raised"))
    (except [e exc-type]
      (assert (in substring (str e)) f"Expected {substring!r} in error {(str e)!r}"))))

(defn codes [issues]
  (set (lfor issue issues (get issue "code"))))

;; ---------------------------------------------------------------------------
;; spec
;; ---------------------------------------------------------------------------

(defn test-constructor-specs-are-plain-data []
  (assert= (spec.request "textDocument/hover" "hover" :capability {"hoverProvider" True})
           {"kind" "request"
            "method" "textDocument/hover"
            "handler" "hover"
            "capability" {"hoverProvider" True}}))

(defn test-macros-emit-registry-data []
  (assert= (get (get REGISTRY 0) "method") "textDocument/hover")
  (assert= (get (get REGISTRY 0) "handler") "hover")
  (assert= (get (get REGISTRY 2) "kind") "notification")
  (assert= (get (get REGISTRY -1) "command") "example.ping"))

(defn test-combine-registries-preserves-order []
  (setv one (spec.registry (spec.request "a" "handler-a")))
  (setv two (spec.registry (spec.command "cmd" "handler-b")))
  (assert= (spec.combine-registries one two) #((get one 0) (get two 0))))

(defn test-handler-names-unique-and-ordered []
  (setv reg (spec.registry (spec.request "a" "shared")
                           (spec.notification "b" "shared")
                           (spec.command "cmd" "other")))
  (assert= (spec.handler-names reg) ["shared" "other"]))

(defn test-invalid-feature-kind-rejected []
  (assert-raises ValueError "feature kind"
    (fn [] (spec.make-feature "x" "handler" :kind "event"))))

(defn test-validate-reports-duplicates-and-missing-handlers []
  (setv reg (spec.registry (spec.request "x" "a") (spec.request "x" "b")))
  (setv issues (spec.validate-registry reg :handlers {"a" (fn [e] None)} :require-handlers True))
  (assert= (codes issues) #{"duplicate-method" "missing-handler"}))

(defn test-assert-valid-registry-raises []
  (assert-raises ValueError "handler is not installed"
    (fn [] (spec.assert-valid-registry (spec.registry (spec.command "cmd" "missing"))
                                       :handlers {} :require-handlers True))))

(defn test-validate-handles-malformed-specs []
  (setv issues (spec.validate-registry
                 (spec.registry {"kind" "request" "method" [] "handler" "h"}
                                {"kind" "command" "command" None})))
  (assert= (codes issues) #{"invalid-method" "invalid-command" "missing-handler"}))

;; ---------------------------------------------------------------------------
;; server
;; ---------------------------------------------------------------------------

(defn test-make-server-composes-capabilities-and-commands []
  (setv srv (fixture-server))
  (assert= (get srv "capabilities")
           {"hoverProvider" True
            "completionProvider" {"resolveProvider" False "triggerCharacters" ["."]}
            "executeCommandProvider" {"commands" ["example.ping"]}})
  (assert= (set (get srv "features"))
           #{"textDocument/hover" "textDocument/completion" "textDocument/didOpen"}))

(defn test-initialize-is-builtin-and-records-lifecycle []
  (setv result (server.dispatch-message (fixture-server)
                 {"jsonrpc" "2.0" "id" 1 "method" "initialize" "params" {"rootUri" "file:///tmp"}}))
  (assert= (get (get (get (get result "server") "state") "lifecycle") "initializeParams")
           {"rootUri" "file:///tmp"})
  (setv message (get (get result "messages") 0))
  (assert= (get message "id") 1)
  (assert= (get (get message "result") "serverInfo") {"name" "fixture" "version" "1.0.0"}))

(defn test-initialized-shutdown-exit-update-lifecycle []
  (setv srv (fixture-server))
  (setv srv (get (server.dispatch-message srv {"jsonrpc" "2.0" "id" 1 "method" "initialize"}) "server"))
  (setv srv (get (server.dispatch-message srv {"jsonrpc" "2.0" "method" "initialized"}) "server"))
  (setv srv (get (server.dispatch-message srv {"jsonrpc" "2.0" "id" 2 "method" "shutdown"}) "server"))
  (setv result (server.dispatch-message srv {"jsonrpc" "2.0" "method" "exit"}))
  (setv lifecycle (get (get (get result "server") "state") "lifecycle"))
  (assert= (get lifecycle "initialized") True)
  (assert= (get lifecycle "shutdown") True)
  (assert= (get lifecycle "exiting") True))

(defn test-feature-dispatch-returns-handler-result []
  (setv result (server.dispatch-message (fixture-server)
                 {"jsonrpc" "2.0" "id" 2 "method" "textDocument/hover" "params" {}}))
  (assert= (get result "messages") [{"jsonrpc" "2.0" "id" 2 "result" {"contents" "hi"}}]))

(defn test-effect-replaces-state-and-emits-notifications []
  (defn remember [event]
    (setv state (dict (get event "state")))
    (setv (get state "last") (get event "params"))
    (server.effect :result {"remembered" True}
                   :state state
                   :notifications [(jsonrpc.notification "example/remembered" {"state" state})]))
  (setv srv (server.make-server "effects" "1.0.0"
              (spec.registry (spec.request "example/remember" "remember"))
              {"remember" remember}))
  (setv result (server.dispatch-message srv
                 {"jsonrpc" "2.0" "id" 3 "method" "example/remember" "params" {"uri" "file:///a.hy"}}))
  (assert= (get (get result "server") "state") {"last" {"uri" "file:///a.hy"}})
  (assert= (get result "messages")
           [{"jsonrpc" "2.0" "id" 3 "result" {"remembered" True}}
            (jsonrpc.notification "example/remembered" {"state" {"last" {"uri" "file:///a.hy"}}})]))

(defn test-command-dispatch-uses-execute-command-params []
  (setv result (server.dispatch-message (fixture-server)
                 {"jsonrpc" "2.0" "id" 4 "method" "workspace/executeCommand"
                  "params" {"command" "example.ping" "arguments" ["a" "b"]}}))
  (assert= (get result "messages") [{"jsonrpc" "2.0" "id" 4 "result" {"args" ["a" "b"]}}]))

(defn test-unknown-request-method-not-found-notification-silent []
  (setv srv (fixture-server))
  (setv req (server.dispatch-message srv {"jsonrpc" "2.0" "id" 9 "method" "missing"}))
  (setv notif (server.dispatch-message srv {"jsonrpc" "2.0" "method" "missing"}))
  (assert= (get (get (get (get req "messages") 0) "error") "code") -32601)
  (assert= (get notif "messages") []))

(defn test-dispatch-threads-state-through-batches []
  (defn remember [event] (server.effect :state {"last" (get event "params")} :result {"ok" True}))
  (setv srv (server.make-server "batch" "1.0.0"
              (spec.registry (spec.request "remember" "remember")) {"remember" remember}))
  (setv result (server.dispatch srv
                 [{"jsonrpc" "2.0" "id" 1 "method" "remember" "params" {"n" 1}}
                  {"jsonrpc" "2.0" "id" 2 "method" "remember" "params" {"n" 2}}]))
  (assert= (get (get result "server") "state") {"last" {"n" 2}})
  (assert= (lfor m (get result "messages") :if (in "id" m) (get m "id")) [1 2]))

(defn test-empty-batch-is-invalid-request []
  (setv result (server.dispatch (fixture-server) []))
  (assert= (get (get (get (get result "messages") 0) "error") "code") -32600))

(defn test-dispatch-json-parses-payload-and-reports-parse-errors []
  (setv srv (fixture-server))
  (setv ok (server.dispatch-json srv b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"))
  (setv bad (server.dispatch-json srv b"{not json"))
  (assert= (get (get (get (get (get ok "messages") 0) "result") "serverInfo") "name") "fixture")
  (assert= (get (get (get (get bad "messages") 0) "error") "code") -32700))

(defn test-make-server-rejects-missing-handlers-by-default []
  (assert-raises ValueError "handler is not installed"
    (fn [] (server.make-server "missing" "1.0.0" (spec.registry (spec.request "x" "missing")) {}))))

(defn test-missing-handler-deferred-to-dispatch []
  (setv srv (server.make-server "missing" "1.0.0"
              (spec.registry (spec.request "x" "missing")) {} :strict-handlers False))
  (setv result (server.dispatch-message srv {"jsonrpc" "2.0" "id" 1 "method" "x"}))
  (assert= (get (get (get (get result "messages") 0) "error") "code") -32603))

(defn test-merge-maps-is-recursive []
  (assert= (server.merge-maps {"a" {"b" 1}} {"a" {"c" 2}}) {"a" {"b" 1 "c" 2}}))

;; ---------------------------------------------------------------------------
;; workspace
;; ---------------------------------------------------------------------------

(defn test-document-helpers-are-copy-on-write []
  (setv original {})
  (setv state (ws.with-document original (ws.document "file:///a.txt" "hello" "text" 1)))
  (assert= original {})
  (assert= (get (ws.get-document state "file:///a.txt") "text") "hello"))

(defn test-open-change-close-from-lsp-params []
  (setv state (ws.open-document {}
                {"textDocument" {"uri" "file:///a.txt" "languageId" "plaintext"
                                 "version" 1 "text" "hello\nworld"}}))
  (setv state (ws.change-document state
                {"textDocument" {"uri" "file:///a.txt" "version" 2}
                 "contentChanges" [{"range" {"start" {"line" 1 "character" 0}
                                             "end" {"line" 1 "character" 5}}
                                    "text" "there"}]}))
  (assert= (ws.get-document state "file:///a.txt")
           {"uri" "file:///a.txt" "languageId" "plaintext" "version" 2 "text" "hello\nthere"})
  (setv state (ws.close-document state {"textDocument" {"uri" "file:///a.txt"}}))
  (assert= (ws.get-document state "file:///a.txt") None))

(defn test-full-document-change-replaces-all-text []
  (assert= (ws.apply-text-changes "old" [{"text" "new"}]) "new"))

(defn test-position-offset-round-trip-ascii []
  (setv text "ab\ncd\nef")
  (setv position {"line" 1 "character" 1})
  (setv offset (ws.position-to-offset text position))
  (assert= offset 4)
  (assert= (ws.offset-to-position text offset) position))

(defn test-position-encoding-utf16-utf8-utf32 []
  (setv text "a😀b")
  (assert= (ws.encoded-length text ws.POSITION-ENCODING-UTF16) 4)
  (assert= (ws.encoded-length text ws.POSITION-ENCODING-UTF8) 6)
  (assert= (ws.encoded-length text ws.POSITION-ENCODING-UTF32) 3)
  (assert= (ws.position-to-offset text {"line" 0 "character" 3} ws.POSITION-ENCODING-UTF16) 2)
  (assert= (ws.position-to-offset text {"line" 0 "character" 5} ws.POSITION-ENCODING-UTF8) 2)
  (assert= (ws.position-to-offset text {"line" 0 "character" 2} ws.POSITION-ENCODING-UTF32) 2)
  (assert= (ws.offset-to-position text 2 ws.POSITION-ENCODING-UTF16) {"line" 0 "character" 3})
  (assert= (ws.offset-to-position text 2 ws.POSITION-ENCODING-UTF8) {"line" 0 "character" 5})
  (assert= (ws.offset-to-position text 2 ws.POSITION-ENCODING-UTF32) {"line" 0 "character" 2}))

(defn test-apply-text-change-uses-negotiated-encoding []
  (assert= (ws.apply-text-change "a😀b"
             {"range" {"start" {"line" 0 "character" 1} "end" {"line" 0 "character" 3}} "text" "!"}
             ws.POSITION-ENCODING-UTF16)
           "a!b"))

(defn test-apply-text-change-clamps-out-of-range []
  (assert= (ws.apply-text-change "abc"
             {"range" {"start" {"line" 9 "character" 0} "end" {"line" 9 "character" 3}} "text" "!"})
           "abc!"))

(defn test-change-unknown-document-is-error []
  (assert-raises KeyError "document is not open"
    (fn [] (ws.change-document {} {"textDocument" {"uri" "file:///missing"}
                                   "contentChanges" [{"text" "x"}]}))))

;; ---------------------------------------------------------------------------
;; protocol
;; ---------------------------------------------------------------------------

(defn test-position-and-range-helpers []
  (assert= (proto.position 1 2) {"line" 1 "character" 2})
  (assert= (proto.range 1 2 3 4) {"start" {"line" 1 "character" 2} "end" {"line" 3 "character" 4}}))

(defn test-capability-helpers-are-plain-data []
  (assert= (proto.position-encoding-capability proto.POSITION-ENCODING-UTF8) {"positionEncoding" "utf-8"})
  (assert= (proto.text-document-sync) {"openClose" True "change" proto.TEXT-DOCUMENT-SYNC-INCREMENTAL})
  (assert= (proto.completion-options :trigger-characters ["."]) {"resolveProvider" False "triggerCharacters" ["."]}))

(defn test-diagnostic-and-publish-diagnostics []
  (setv item (proto.diagnostic "watch this" (proto.range 0 0 0 4) :severity proto.DIAGNOSTIC-SEVERITY-WARNING))
  (assert= (proto.publish-diagnostics "file:///a" [item] :version 3)
           {"jsonrpc" "2.0" "method" "textDocument/publishDiagnostics"
            "params" {"uri" "file:///a" "version" 3 "diagnostics" [item]}}))

;; ---------------------------------------------------------------------------
;; stdio
;; ---------------------------------------------------------------------------

(defn test-encode-decode-frame-round-trips-utf8 []
  (setv message {"jsonrpc" "2.0" "id" 1 "result" {"letter" "λ"}})
  (assert= (stdio.decode-frame (stdio.encode-message message)) message))

(defn test-read-write-message-round-trip []
  (setv stream (io.BytesIO))
  (setv message {"jsonrpc" "2.0" "method" "initialized" "params" {}})
  (stdio.write-message stream message)
  (.seek stream 0)
  (assert= (stdio.read-message stream) message))

(defn test-decode-frame-rejects-missing-separator []
  (assert-raises ValueError "separator"
    (fn [] (stdio.decode-frame b"Content-Length: 2\r\n{}"))))

(defn test-serve-reads-framed-messages-and-writes-responses []
  (defn pong [event] {"pong" (get event "params")})
  (setv srv (server.make-server "stdio" "1.0.0" (spec.registry (spec.request "ping" "pong")) {"pong" pong}))
  (setv input-stream (io.BytesIO
                       (+ (stdio.encode-message {"jsonrpc" "2.0" "id" 1 "method" "initialize"})
                          (stdio.encode-message {"jsonrpc" "2.0" "id" 2 "method" "ping" "params" {"x" 1}}))))
  (setv output-stream (io.BytesIO))
  (setv final-server (stdio.serve srv input-stream output-stream))
  (.seek output-stream 0)
  (setv messages [])
  (while True
    (setv m (stdio.read-message output-stream))
    (when (is m None) (break))
    (.append messages m))
  (assert= (get (get (get messages 0) "result") "serverInfo") {"name" "stdio" "version" "1.0.0"})
  (assert= (get messages 1) {"jsonrpc" "2.0" "id" 2 "result" {"pong" {"x" 1}}})
  (assert= (get (get (get final-server "state") "lifecycle") "shutdown") False))

;; ---------------------------------------------------------------------------
;; runner
;; ---------------------------------------------------------------------------

(defn run-tests []
  (setv tests (sorted (list (gfor item (globals) :if (.startswith item "test_") item))))
  (setv failures [])
  (for [name tests]
    (try
      ((get (globals) name))
      (print f"ok {name}")
      (except [e Exception]
        (.append failures [name e])
        (print f"FAIL {name}: {e!r}"))))
  (when failures
    (raise (AssertionError f"{(len failures)} test(s) failed")))
  (print f"{(len tests)} Hy lsp tests passed"))

(when (= __name__ "__main__")
  (run-tests))
