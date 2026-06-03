"Tests for the thyforce/dispatch spine, in isolation from any protocol.

Proves the dispatch core works with no LSP dependency: registry indexing, feature
dispatch, effects + immutable state threading, batches, and crucially that
lifecycle is *data* (`builtins`) — the spine hardcodes no `initialize`/`shutdown`.
Run: `hy tests/thyforce/dispatch/test_core.hy`.
"

(import hy)
(import thyforce.dispatch.core :as engine)
(import thyforce.dispatch.registry :as reg)
(import thyforce.dispatch.jsonrpc :as jsonrpc)
(require thyforce.dispatch.registry [defregistry on-request on-notification on-command])

(defn assert= [actual expected]
  (assert (= actual expected) f"expected {expected !r}, got {actual !r}"))

(defn with-builtins [server builtins]
  (setv out (dict server))
  (setv (get out "builtins") builtins)
  out)

(defn test-registry-macros-emit-data []
  (defregistry REG
    (on-request "a/req" "h-req")
    (on-notification "a/note" "h-note")
    (on-command "a.cmd" "h-cmd"))
  (assert= (get (get REG 0) "kind") "request")
  (assert= (get (get REG 0) "method") "a/req")
  (assert= (get (get REG 1) "kind") "notification")
  (assert= (get (get REG -1) "command") "a.cmd")
  (assert= (reg.handler-names REG) ["h-req" "h-note" "h-cmd"]))

(defn test-make-server-indexes-features-commands-capabilities []
  (defn h [event] None)
  (setv srv (engine.make-server "s" "1.0"
              (reg.registry (reg.request "x" "h" :capability {"xProvider" True})
                            (reg.command "c.do" "h"))
              {"h" h}))
  (assert= (set (get srv "features")) #{"x"})
  (assert= (set (get srv "commands")) #{"c.do"})
  (assert= (get srv "capabilities")
           {"xProvider" True "executeCommandProvider" {"commands" ["c.do"]}})
  ;; a freshly built spine server carries no builtins
  (assert= (get srv "builtins") {}))

(defn test-feature-dispatch-and-notification-silence []
  (defn hi [event] {"msg" "hi"})
  (setv srv (engine.make-server "s" "1.0"
              (reg.registry (reg.request "say" "hi") (reg.notification "noop" "hi")) {"hi" hi}))
  (setv req (engine.dispatch-message srv {"id" 1 "method" "say" "params" {}}))
  (assert= (get req "messages") [{"jsonrpc" "2.0" "id" 1 "result" {"msg" "hi"}}])
  ;; a notification (no id) produces no response
  (setv note (engine.dispatch-message srv {"method" "noop"}))
  (assert= (get note "messages") []))

(defn test-effect-threads-state-and-emits-notifications []
  (defn remember [event]
    (engine.effect :result {"ok" True}
                   :state {"last" (get event "params")}
                   :notifications [(jsonrpc.notification "echo" (get event "params"))]))
  (setv srv (engine.make-server "s" "1.0" (reg.registry (reg.request "remember" "remember")) {"remember" remember}))
  (setv r (engine.dispatch-message srv {"id" 2 "method" "remember" "params" {"n" 1}}))
  (assert= (get (get r "server") "state") {"last" {"n" 1}})
  (assert= (get r "messages")
           [{"jsonrpc" "2.0" "id" 2 "result" {"ok" True}}
            (jsonrpc.notification "echo" {"n" 1})]))

(defn test-lifecycle-is-data-not-hardcoded []
  (defn start-session [server message has-id]
    (setv next (engine.update-state server {"started" True}))
    {"server" next
     "messages" (if has-id [(jsonrpc.response (.get message "id" None) {"ok" True})] [])})
  (setv srv (engine.make-server "spine" "1.0" (reg.registry) {}))
  ;; the bare spine knows no lifecycle: a session method is method-not-found
  (setv miss (engine.dispatch-message srv {"id" 1 "method" "session/start"}))
  (assert= (get (get (get (get miss "messages") 0) "error") "code") -32601)
  ;; inject the same method as a data builtin -> it dispatches and threads state
  (setv srv (with-builtins srv {"session/start" start-session}))
  (setv hit (engine.dispatch-message srv {"id" 1 "method" "session/start"}))
  (assert= (get (get (get hit "messages") 0) "result") {"ok" True})
  (assert= (get (get hit "server") "state") {"started" True}))

(defn test-command-routing-is-generic []
  ;; dispatch-command is wired under an arbitrary method name, not workspace/executeCommand
  (defn ping [event] {"args" (get event "arguments")})
  (setv srv (engine.make-server "s" "1.0" (reg.registry (reg.command "do.ping" "ping")) {"ping" ping}))
  (setv srv (with-builtins srv {"run" engine.dispatch-command}))
  (setv r (engine.dispatch-message srv {"id" 3 "method" "run"
                                        "params" {"command" "do.ping" "arguments" ["x"]}}))
  (assert= (get (get (get r "messages") 0) "result") {"args" ["x"]}))

(defn test-batch-threads-state-and-unknown-method-errors []
  (defn remember [event] (engine.effect :result {"ok" True} :state {"last" (get event "params")}))
  (setv srv (engine.make-server "s" "1.0" (reg.registry (reg.request "remember" "remember")) {"remember" remember}))
  (setv r (engine.dispatch srv [{"id" 1 "method" "remember" "params" {"n" 1}}
                                {"id" 2 "method" "remember" "params" {"n" 2}}]))
  (assert= (get (get r "server") "state") {"last" {"n" 2}})
  (assert= (lfor m (get r "messages") :if (in "id" m) (get m "id")) [1 2])
  (setv miss (engine.dispatch-message srv {"id" 9 "method" "ghost"}))
  (assert= (get (get (get (get miss "messages") 0) "error") "code") -32601))

(defn test-dispatch-json-and-strict-handlers []
  (defn hi [event] {"msg" "hi"})
  (setv srv (engine.make-server "s" "1.0" (reg.registry (reg.request "say" "hi")) {"hi" hi}))
  (setv ok (engine.dispatch-json srv b"{\"id\":1,\"method\":\"say\"}"))
  (assert= (get (get (get ok "messages") 0) "result") {"msg" "hi"})
  (setv bad (engine.dispatch-json srv b"{not json"))
  (assert= (get (get (get bad "messages") 0) "error") {"code" -32700 "message" "parse error"
                                                       "data" {"exception" "JSONDecodeError"}})
  (try
    (engine.make-server "s" "1.0" (reg.registry (reg.request "x" "missing")) {})
    (raise (AssertionError "expected ValueError for missing handler"))
    (except [e ValueError] None)))

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
