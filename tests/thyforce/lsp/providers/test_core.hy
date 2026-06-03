(import hy)
(import thyforce.lsp.providers.core :as service)
(import thyforce.lsp.engine.core :as engine)

(setv URI "file:///workspace/main.hy")

(defn assert= [actual expected]
  (assert (= actual expected) f"Expected {expected !r}, got {actual !r}"))
(defn assert-true [value]
  (assert value f"Expected truthy, got {value !r}"))
(defn assert-false [value]
  (assert (not value) f"Expected falsy, got {value !r}"))

(defn step [srv msg]
  (setv r (engine.dispatch-message srv msg))
  #((get r "server") (get r "messages")))

(defn didopen-msg [uri src]
  {"jsonrpc" "2.0" "method" "textDocument/didOpen"
   "params" {"textDocument" {"uri" uri "text" src "languageId" "hy" "version" 1}}})

(defn open-doc [uri src]
  "Return a server with URI opened to SRC."
  (get (step (service.make-server) (didopen-msg uri src)) 0))

(defn req [srv id method params]
  (setv [_ msgs] (step srv {"jsonrpc" "2.0" "id" id "method" method "params" params}))
  (get (get msgs 0) "result"))

(defn pos [uri line character]
  {"textDocument" {"uri" uri} "position" {"line" line "character" character}})

(setv GREET "(defn greet [name]\n  \"Say hi.\"\n  (greet name))\n")

;; ---------------------------------------------------------------------------

(defn test-initialize-advertises-capabilities []
  (setv [_ msgs] (step (service.make-server) {"jsonrpc" "2.0" "id" 1 "method" "initialize" "params" {}}))
  (setv caps (get (get (get msgs 0) "result") "capabilities"))
  (for [provider ["completionProvider" "hoverProvider" "definitionProvider"
                  "semanticTokensProvider" "foldingRangeProvider" "documentSymbolProvider"
                  "workspaceSymbolProvider" "referencesProvider" "renameProvider"
                  "signatureHelpProvider" "textDocumentSync" "executeCommandProvider"]]
    (assert-true (in provider caps)))
  (assert= (get (get caps "renameProvider") "prepareProvider") True)
  (assert-true (in "hyground.reindexWorkspace" (get (get caps "executeCommandProvider") "commands"))))

(defn test-did-open-publishes-diagnostics []
  (setv [_ msgs] (step (service.make-server) (didopen-msg URI "(defn broken [\n")))
  (setv diag (get msgs 0))
  (assert= (get diag "method") "textDocument/publishDiagnostics")
  (assert= (get (get diag "params") "uri") URI)
  (assert-true (> (len (get (get diag "params") "diagnostics")) 0)))

(defn test-did-open-clean-source-has-no-diagnostics []
  (setv [_ msgs] (step (service.make-server) (didopen-msg URI GREET)))
  (assert= (get (get (get msgs 0) "params") "diagnostics") []))

(defn test-hover-returns-markdown []
  (setv srv (open-doc URI GREET))
  (setv result (req srv 2 "textDocument/hover" (pos URI 2 4)))
  (setv value (get (get result "contents") "value"))
  (assert-true (in "(greet [name])" value))
  (assert-true (in "Say hi." value)))

(defn test-definition-points-at-declaration []
  (setv srv (open-doc URI GREET))
  (setv result (req srv 3 "textDocument/definition" (pos URI 2 4)))
  (assert= (len result) 1)
  (setv loc (get result 0))
  (assert= (get loc "uri") URI)
  (assert= (get (get (get loc "range") "start") "line") 0)
  (assert= (get (get (get loc "range") "start") "character") 6))

(defn test-completion-includes-local-symbol []
  (setv srv (open-doc URI GREET))
  (setv result (req srv 4 "textDocument/completion" (pos URI 2 6)))
  (assert-false (get result "isIncomplete"))
  (setv labels (set (gfor item (get result "items") (get item "label"))))
  (assert-true (in "greet" labels)))

(defn test-document-symbol-lists-definitions []
  (setv srv (open-doc URI GREET))
  (setv result (req srv 5 "textDocument/documentSymbol" {"textDocument" {"uri" URI}}))
  (setv names (set (gfor s result (get s "name"))))
  (assert-true (in "greet" names))
  (setv greet (next (gfor s result :if (= (get s "name") "greet") s)))
  (assert= (get greet "kind") 12))

(defn test-folding-range []
  (setv srv (open-doc URI "(defn foo [x]\n  (if x\n    1\n    2))\n"))
  (setv result (req srv 6 "textDocument/foldingRange" {"textDocument" {"uri" URI}}))
  (assert-true (> (len result) 0))
  (assert-true (in {"startLine" 0 "startCharacter" 0 "endLine" 3 "endCharacter" 7} result)))

(defn test-semantic-tokens-full []
  (setv srv (open-doc URI GREET))
  (setv result (req srv 7 "textDocument/semanticTokens/full" {"textDocument" {"uri" URI}}))
  (setv data (get result "data"))
  (assert-true (> (len data) 0))
  (assert= (% (len data) 5) 0))

(defn test-references-and-rename-local []
  (setv srv (open-doc URI GREET))
  (setv refs (req srv 8 "textDocument/references"
               {#** (pos URI 0 6) "context" {"includeDeclaration" True}}))
  ;; declaration plus the recursive call
  (assert-true (>= (len refs) 2))
  (setv edit (req srv 9 "textDocument/rename" {#** (pos URI 0 6) "newName" "salute"}))
  (setv changes (get edit "changes"))
  (assert-true (in URI changes))
  (assert-true (>= (len (get changes URI)) 2))
  (assert= (get (get (get changes URI) 0) "newText") "salute"))

(defn test-prepare-rename-on-local []
  (setv srv (open-doc URI GREET))
  (setv result (req srv 10 "textDocument/prepareRename" (pos URI 0 6)))
  (assert-true (is-not result None))
  (assert= (get (get result "start") "character") 6)
  (assert= (get (get result "end") "character") 11))

(defn test-signature-help []
  (setv srv (open-doc URI GREET))
  (setv result (req srv 11 "textDocument/signatureHelp" (pos URI 2 9)))
  (assert-true (is-not result None))
  (assert= (get (get (get result "signatures") 0) "label") "(greet [name])"))

(defn test-did-change-updates-index []
  (setv srv (open-doc URI "(defn old-name [] 1)\n"))
  (setv [srv _] (step srv {"jsonrpc" "2.0" "method" "textDocument/didChange"
                           "params" {"textDocument" {"uri" URI "version" 2}
                                     "contentChanges" [{"text" "(defn new-name [] 1)\n"}]}}))
  (assert-true (is-not (req srv 12 "textDocument/hover" (pos URI 0 6)) None))
  (setv result (req srv 13 "textDocument/documentSymbol" {"textDocument" {"uri" URI}}))
  (setv names (set (gfor s result (get s "name"))))
  (assert-true (in "new-name" names))
  (assert-false (in "old-name" names)))

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
        (print f"FAIL {name}: {e !r}"))))
  (when failures
    (raise (AssertionError f"{(len failures)} test(s) failed")))
  (print f"{(len tests)} Hy service tests passed"))

(when (= __name__ "__main__")
  (run-tests))
