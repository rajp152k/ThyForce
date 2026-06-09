"LSP feature handlers binding analysis onto the language server engine."

(import thyforce.lsp.engine.core :as engine)
(import thyforce.lsp.engine.protocol :as proto)
(import thyforce.lsp.engine.workspace :as ws)
(require thyforce.dispatch.registry [defregistry on-request on-notification on-command])

(import thyforce.lsp.analyzer.index :as index)
(import thyforce.lsp.analyzer.word :as word)
(import thyforce.lsp.analyzer.completion-context :as cc)
(import thyforce.lsp.analyzer.semantic :as semantic)
(import thyforce.lsp.analyzer.folding :as folding)
(import thyforce.lsp.analyzer.model :as model)

(setv REINDEX-COMMAND "hyground.reindexWorkspace")

;; LSP CompletionItemKind / SymbolKind numeric codes.
(setv _COMPLETION-KINDS
  {model.KIND-CORE-FORM 14 model.KIND-PYTHON-BUILTIN 3 model.KIND-LOCAL-FUNCTION 3
   model.KIND-LOCAL-MACRO 14 model.KIND-READER-MACRO 14 model.KIND-LOCAL-CLASS 7
   model.KIND-LOCAL-VARIABLE 6 model.KIND-PARAMETER 6 model.KIND-MODULE 9})
(setv _SYMBOL-KINDS
  {model.KIND-CORE-FORM 12 model.KIND-PYTHON-BUILTIN 12 model.KIND-LOCAL-FUNCTION 12
   model.KIND-LOCAL-MACRO 12 model.KIND-READER-MACRO 12 model.KIND-LOCAL-CLASS 5
   model.KIND-LOCAL-VARIABLE 13 model.KIND-PARAMETER 13 model.KIND-MODULE 2})

(defn _state [event] (get event "state"))
(defn _index [event] (get (_state event) "index"))
(defn _params [event] (get event "params"))

(defn _doc-uri [event] (get (get (_params event) "textDocument") "uri"))

(defn _doc-text [event uri]
  (setv doc (ws.get-document (_state event) uri))
  (if doc (get doc "text") ""))

(defn _pos [event]
  "Return [uri text line character] for a position request."
  (setv uri (_doc-uri event))
  (setv position (get (_params event) "position"))
  [uri (_doc-text event uri) (get position "line") (get position "character")])

(defn _completion-kind [kind] (.get _COMPLETION-KINDS kind 1))
(defn _symbol-kind [kind] (.get _SYMBOL-KINDS kind 19))

(defn _hover-markdown [symbol]
  (setv name (get symbol "name"))
  (setv signature (get symbol "signature"))
  (setv detail (get symbol "detail"))
  (setv kind (get symbol "kind"))
  (setv documentation (get symbol "documentation"))
  (setv heading (if signature f"### `{signature}`" f"### `{name}`"))
  (setv parts [heading f"_{(or detail kind)}_"])
  (when documentation
    (.append parts documentation))
  (.join "\n\n" parts))

(defn _diagnostic->lsp [d]
  (proto.diagnostic (get d "message")
    (proto.range (get d "line") (get d "character") (get d "end-line") (get d "end-character"))
    :severity proto.DIAGNOSTIC-SEVERITY-ERROR
    :source "hyground"
    :code (get d "code")))

(defn _diagnostics-notification [document]
  (proto.publish-diagnostics document.uri (lfor d document.diagnostics (_diagnostic->lsp d))))

(defn did-open [event]
  (setv td (get (_params event) "textDocument"))
  (setv next-state (ws.open-document (_state event) (_params event)))
  (setv document (.update-document (_index event) (get td "uri") (get td "text")))
  (engine.effect :state next-state :notifications [(_diagnostics-notification document)]))

(defn did-change [event]
  (setv uri (_doc-uri event))
  (setv next-state (ws.change-document (_state event) (_params event)))
  (setv text (get (ws.get-document next-state uri) "text"))
  (setv document (.update-document (_index event) uri text))
  (engine.effect :state next-state :notifications [(_diagnostics-notification document)]))

(defn did-close [event]
  (setv uri (_doc-uri event))
  (setv next-state (ws.close-document (_state event) (_params event)))
  (.remove-document (_index event) uri)
  (engine.effect :state next-state :notifications [(proto.publish-diagnostics uri [])]))

(defn _reindex-relevant? [uri]
  (setv path (get (.rsplit uri "/" 1) -1))
  (or (.endswith path #(".hy" ".py" ".pyi"))
      (in path #{"pyproject.toml" "uv.lock" "poetry.lock" "pdm.lock" "requirements.txt"})))

(defn _open-sources [event root]
  (setv idx (_index event))
  (setv docs (.get (_state event) "documents" {}))
  (dfor [uri doc] (.items docs)
        :if (= (.resolve (.root-for-uri idx uri)) (.resolve root))
        uri (get doc "text")))

(defn did-change-watched-files [event]
  (setv idx (_index event))
  (setv roots [])
  (for [change (get (_params event) "changes")]
    (when (_reindex-relevant? (get change "uri"))
      (setv r (.root-for-uri idx (get change "uri")))
      (when (not (in r roots))
        (.append roots r))))
  (setv notifications [])
  (for [root roots]
    (for [document (.reindex-root idx root (_open-sources event root))]
      (.append notifications (_diagnostics-notification document))))
  (engine.effect :notifications notifications))

(defn _symbols-for-completion [idx uri prefix context line character]
  (setv resolver (.resolver-for-root idx (.root-for-uri idx uri)))
  (setv kind (get context "kind"))
  (setv module (get context "module"))
  (cond
    (in kind #{"import-module" "require-module"}) (.module-candidates resolver prefix)
    (and (= kind "import-member") module) (.member-candidates resolver module prefix)
    (and (= kind "require-macro") module) (.macro-candidates resolver module prefix)
    (and (= kind "require-reader") module) (.reader-macro-candidates resolver module prefix)
    True (.symbols-for-completion idx uri prefix line character)))

(defn _completion-item [symbol replace-range]
  (setv name (get symbol "name"))
  (setv item {"label" name
              "kind" (_completion-kind (get symbol "kind"))
              "detail" (or (get symbol "detail") (get symbol "kind"))
              "textEdit" {"range" replace-range "newText" name}
              "filterText" name
              "sortText" name
              "data" {"kind" (get symbol "kind")}})
  (when (or (get symbol "documentation") (get symbol "signature"))
    (setv (get item "documentation") {"kind" "markdown" "value" (_hover-markdown symbol)}))
  item)

(defn completion [event]
  (setv [uri text line character] (_pos event))
  (setv prefix (word.word-prefix text line character))
  (setv replace-range (proto.range line (max (- character (len prefix)) 0) line character))
  (setv context (cc.completion-context text line character))
  (setv items (lfor symbol (_symbols-for-completion (_index event) uri prefix context line character)
                    (_completion-item symbol replace-range)))
  {"isIncomplete" False "items" items})

(defn hover [event]
  (setv [uri text line character] (_pos event))
  (setv name (word.word-at text line character))
  (when (not name)
    (return None))
  (setv symbol (.resolve (_index event) uri name line character))
  (when (is symbol None)
    (return None))
  {"contents" {"kind" "markdown" "value" (_hover-markdown symbol)}})

(defn definition [event]
  (setv [uri text line character] (_pos event))
  (setv name (word.word-at text line character))
  (when (not name)
    (return None))
  (setv symbol (.resolve (_index event) uri name line character))
  (when (or (is symbol None) (is (get symbol "source") None))
    (return None))
  [(get symbol "source")])

(defn semantic-tokens-full [event]
  (setv uri (_doc-uri event))
  (setv text (_doc-text event uri))
  (setv idx (_index event))
  (setv tokens (semantic.semantic-tokens text
                 (fn [name line character] (.resolve idx uri name line character))))
  {"data" (semantic.encode-semantic-tokens tokens)})

(defn folding-range [event]
  (setv uri (_doc-uri event))
  (setv text (_doc-text event uri))
  (lfor fold (folding.folding-ranges text)
        {"startLine" (get fold "start-line") "startCharacter" (get fold "start-character")
         "endLine" (get fold "end-line") "endCharacter" (get fold "end-character")}))

(defn document-symbol [event]
  (setv uri (_doc-uri event))
  (setv idx (_index event))
  (setv document (.get idx.documents uri))
  (when (is document None)
    (setv document (.update-document idx uri (_doc-text event uri))))
  (setv symbols [])
  (for [symbol (.values document.symbols)]
    (setv source (get symbol "source"))
    (when (or (is source None) (!= (get source "uri") uri))
      (continue))
    (setv rng (get source "range"))
    (.append symbols {"name" (get symbol "name")
                      "kind" (_symbol-kind (get symbol "kind"))
                      "range" rng
                      "selectionRange" rng
                      "detail" (or (get symbol "detail") (get symbol "kind"))}))
  symbols)

(defn workspace-symbol [event]
  (setv query (.lower (get (_params event) "query")))
  (setv idx (_index event))
  (setv out [])
  (setv seen (set))
  (for [document (.values idx.documents)]
    (for [symbol (.values document.symbols)]
      (setv source (get symbol "source"))
      (when (is source None)
        (continue))
      (when (and query (not (in query (.lower (get symbol "name")))))
        (continue))
      (setv start (get (get source "range") "start"))
      (setv key #((get symbol "name") (get source "uri") (get start "line") (get start "character")))
      (when (in key seen)
        (continue))
      (.add seen key)
      (.append out {"name" (get symbol "name")
                    "kind" (_symbol-kind (get symbol "kind"))
                    "location" source
                    "containerName" (or (get symbol "detail") (get symbol "kind"))})))
  (sorted out :key (fn [s] (get s "name"))))

(defn _renamable? [symbol]
  (in (get symbol "kind")
      #{model.KIND-LOCAL-FUNCTION model.KIND-LOCAL-MACRO model.KIND-LOCAL-CLASS model.KIND-LOCAL-VARIABLE}))

(defn _renamable-at-uri? [symbol uri]
  (and (_renamable? symbol)
       (is-not (get symbol "source") None)
       (= (get (get symbol "source") "uri") uri)))

(defn _reference-candidate-uris [idx request-uri symbol only-uri]
  (cond
    (is-not only-uri None) [only-uri]
    (and (is-not symbol None) (is-not (get symbol "source") None) (_renamable? symbol))
      (list (dict.fromkeys [request-uri (get (get symbol "source") "uri")]))
    True (list idx.documents)))

(defn _reference-locations [idx request-uri name [symbol None] [only-uri None] [include-declaration True]]
  (setv locations [])
  (for [doc-uri (_reference-candidate-uris idx request-uri symbol only-uri)]
    (setv indexed (.get idx.documents doc-uri))
    (when (is indexed None)
      (continue))
    (for [[line start end] (word.occurrences indexed.source name)]
      (.append locations {"uri" doc-uri "range" (proto.range line start line end)})))
  (cond
    (and include-declaration (is-not symbol None) (is-not (get symbol "source") None))
      (do
        (setv declaration (get symbol "source"))
        (when (not (in declaration locations))
          (.insert locations 0 declaration)))
    (and (not include-declaration) (is-not symbol None) (is-not (get symbol "source") None))
      (setv locations (lfor loc locations :if (!= loc (get symbol "source")) loc)))
  locations)

(defn references [event]
  (setv [uri text line character] (_pos event))
  (setv name (word.word-at text line character))
  (when (not name)
    (return []))
  (setv idx (_index event))
  (setv symbol (.resolve idx uri name line character))
  (setv ctx (.get (_params event) "context"))
  (setv include-declaration (if ctx (get ctx "includeDeclaration") True))
  (_reference-locations idx uri name symbol :include-declaration include-declaration))

(defn prepare-rename [event]
  (setv [uri text line character] (_pos event))
  (setv name (word.word-at text line character))
  (setv idx (_index event))
  (setv symbol (if name (.resolve idx uri name line character) None))
  (setv word-range (word.word-range-at text line character))
  (when (or (is symbol None) (is word-range None) (not (_renamable-at-uri? symbol uri)))
    (return None))
  (setv [start end] word-range)
  (proto.range line start line end))

(defn rename [event]
  (setv [uri text line character] (_pos event))
  (setv idx (_index event))
  (setv new-name (get (_params event) "newName"))
  (setv old-name (word.word-at text line character))
  (setv symbol (if old-name (.resolve idx uri old-name line character) None))
  (when (or (is symbol None) (not (_renamable-at-uri? symbol uri)) (not new-name))
    (return None))
  (setv only-uri (if (get symbol "source") (get (get symbol "source") "uri") uri))
  (setv changes {})
  (for [location (_reference-locations idx uri old-name symbol :only-uri only-uri :include-declaration True)]
    (setv loc-uri (get location "uri"))
    (.setdefault changes loc-uri [])
    (.append (get changes loc-uri) {"range" (get location "range") "newText" new-name}))
  {"changes" changes})

(defn signature-help [event]
  (setv [uri text line character] (_pos event))
  (setv call (word.enclosing-call text line character))
  (when (is call None)
    (return None))
  (setv [name active-parameter] call)
  (setv symbol (.resolve (_index event) uri name line character))
  (when (or (is symbol None) (not (get symbol "signature")))
    (return None))
  {"signatures" [{"label" (get symbol "signature")
                  "documentation" {"kind" "markdown" "value" (_hover-markdown symbol)}}]
   "activeSignature" 0
   "activeParameter" active-parameter})

(defn reindex-workspace [event]
  (setv idx (_index event))
  (setv args (get event "arguments"))
  (setv target-uri (if args (get args 0) None))
  (setv docs (.get (_state event) "documents" {}))
  (setv target-uri (or target-uri (next (iter docs) None)))
  (when (is target-uri None)
    (return {"ok" False "message" "No workspace or open Hy document to reindex."}))
  (setv root (.root-for-uri idx target-uri))
  (setv rebuilt (.reindex-root idx root (_open-sources event root)))
  (setv notifications (lfor d rebuilt (_diagnostics-notification d)))
  (.append notifications (proto.show-message f"HyGround reindexed {root} ({(len idx.documents)} documents)."))
  (engine.effect :result {"ok" True "root" (str root) "documents" (len idx.documents)}
                 :notifications notifications))

(defregistry REGISTRY
  (on-notification "textDocument/didOpen" did-open
    :capability {"textDocumentSync" (proto.text-document-sync)})
  (on-notification "textDocument/didChange" did-change)
  (on-notification "textDocument/didClose" did-close)
  (on-notification "workspace/didChangeWatchedFiles" did-change-watched-files)
  (on-request "textDocument/completion" completion
    :capability {"completionProvider" {"triggerCharacters" ["." " " "-" "_" ":" "[" "#"]}})
  (on-request "textDocument/hover" hover
    :capability {"hoverProvider" True})
  (on-request "textDocument/definition" definition
    :capability {"definitionProvider" True})
  (on-request "textDocument/semanticTokens/full" semantic-tokens-full
    :capability {"semanticTokensProvider"
                 {"legend" {"tokenTypes" semantic.SEMANTIC-TOKEN-TYPES
                            "tokenModifiers" semantic.SEMANTIC-TOKEN-MODIFIERS}
                  "full" True}})
  (on-request "textDocument/foldingRange" folding-range
    :capability {"foldingRangeProvider" True})
  (on-request "textDocument/documentSymbol" document-symbol
    :capability {"documentSymbolProvider" True})
  (on-request "workspace/symbol" workspace-symbol
    :capability {"workspaceSymbolProvider" True})
  (on-request "textDocument/references" references
    :capability {"referencesProvider" True})
  (on-request "textDocument/prepareRename" prepare-rename)
  (on-request "textDocument/rename" rename
    :capability {"renameProvider" {"prepareProvider" True}})
  (on-request "textDocument/signatureHelp" signature-help
    :capability {"signatureHelpProvider" {"triggerCharacters" [" " "("]}})
  (on-command REINDEX-COMMAND reindex-workspace))

(defn make-server [[name "hyground"] [version "0.1.0"]]
  "Assemble a runnable chyls server backed by a fresh WorkspaceIndex."
  (engine.make-server name version REGISTRY
    (engine.handlers-from-namespace (globals) REGISTRY)
    :state {"index" (index.WorkspaceIndex)}))
