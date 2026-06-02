"Semantic token support for Hy source.

Scanning is lexical and independent of workspace state. `resolve-symbol` is a
callable accepting (token line character) and returning a symbol-info map or
None, which lets callers plug in position-aware scoped resolution. A semantic
token is a map {\"line\" \"start\" \"length\" \"token-type\"}.
"

(import thyforce.lsp.analyzer.model :as model)
(import thyforce.lsp.analyzer.word [WORD-RE])

(setv SEMANTIC-TOKEN-TYPES
  ["namespace" "class" "function" "macro" "variable" "keyword" "string" "number" "operator" "comment"])
(setv SEMANTIC-TOKEN-MODIFIERS [])
(setv _TOKEN-INDEX (dfor [index name] (enumerate SEMANTIC-TOKEN-TYPES) name index))
(setv _OPERATOR-CHARS (set "+-*/%=<>!&|^~@"))

(defn semantic-token [line start length token-type]
  {"line" line "start" start "length" length "token-type" token-type})

(defn semantic-tokens [source resolve-symbol]
  "Return best-effort semantic tokens for SOURCE, sorted by position."
  (setv tokens [])
  (for [[line-no line] (enumerate (.splitlines source))]
    (setv [code comment-start] (_split-comment line))
    (.extend tokens (_line-tokens code line-no resolve-symbol))
    (when (is-not comment-start None)
      (.append tokens (semantic-token line-no comment-start (- (len line) comment-start) "comment"))))
  (sorted tokens :key (fn [t] #((get t "line") (get t "start")))))

(defn encode-semantic-tokens [tokens]
  "Encode tokens in LSP's relative five-integer representation."
  (setv data [])
  (setv previous-line 0)
  (setv previous-start 0)
  (for [token tokens]
    (setv delta-line (- (get token "line") previous-line))
    (setv delta-start (if delta-line (get token "start") (- (get token "start") previous-start)))
    (.extend data [delta-line delta-start (get token "length")
                   (get _TOKEN-INDEX (get token "token-type")) 0])
    (setv previous-line (get token "line"))
    (setv previous-start (get token "start")))
  data)

(defn _line-tokens [line line-no resolve-symbol]
  (setv tokens [])
  (setv spans-to-skip [])
  (for [[start end] (_string-spans line)]
    (.append spans-to-skip #(start end))
    (.append tokens (semantic-token line-no start (- end start) "string")))
  (for [match (.finditer WORD-RE line)]
    (setv [start end] (.span match))
    (when (any (gfor [skip-start skip-end] spans-to-skip (<= skip-start start (- skip-end 1))))
      (continue))
    (setv text (.group match 0))
    (setv token-type (_classify-token text (resolve-symbol text line-no start)))
    (when (is-not token-type None)
      (.append tokens (semantic-token line-no start (- end start) token-type))))
  tokens)

(defn _classify-token [text symbol]
  (cond
    (is-not symbol None) (_token-type-for-symbol symbol)
    (.startswith text ":") "keyword"
    (_is-number text) "number"
    (and (any (gfor ch text (in ch _OPERATOR-CHARS)))
         (not (any (gfor ch text (.isalnum ch)))))
      "operator"
    True None))

(defn _token-type-for-symbol [symbol]
  (.get
    {model.KIND-CORE-FORM "keyword"
     model.KIND-PYTHON-BUILTIN "function"
     model.KIND-LOCAL-FUNCTION "function"
     model.KIND-LOCAL-MACRO "macro"
     model.KIND-READER-MACRO "macro"
     model.KIND-LOCAL-CLASS "class"
     model.KIND-LOCAL-VARIABLE "variable"
     model.KIND-PARAMETER "variable"
     model.KIND-MODULE "namespace"}
    (get symbol "kind") "variable"))

(defn _split-comment [line]
  (setv in-string False)
  (setv escape False)
  (for [[index ch] (enumerate line)]
    (cond
      in-string
        (cond
          escape (setv escape False)
          (= ch "\\") (setv escape True)
          (= ch "\"") (setv in-string False))
      (= ch "\"") (setv in-string True)
      (= ch ";") (return #((cut line 0 index) index))))
  #(line None))

(defn _string-spans [line]
  (setv spans [])
  (setv in-string False)
  (setv escape False)
  (setv start 0)
  (for [[index ch] (enumerate line)]
    (cond
      in-string
        (cond
          escape (setv escape False)
          (= ch "\\") (setv escape True)
          (= ch "\"") (do (.append spans #(start (+ index 1))) (setv in-string False)))
      (= ch "\"") (do (setv start index) (setv in-string True))))
  (when in-string
    (.append spans #(start (len line))))
  spans)

(defn _is-number [text]
  (try
    (float (.replace text "_" ""))
    (except [ValueError] (return False)))
  (any (gfor ch text (.isdigit ch))))
