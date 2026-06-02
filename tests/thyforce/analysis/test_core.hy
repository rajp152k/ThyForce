(import hy)
(import types [SimpleNamespace])
(import thyforce.analysis.model :as model)
(import thyforce.analysis.word :as word)
(import thyforce.analysis.folding :as folding)
(import thyforce.analysis.completion-context :as cc)
(import thyforce.analysis.semantic :as semantic)
(import thyforce.analysis.core-docs :as core-docs)

(defn assert= [actual expected]
  (assert (= actual expected) f"Expected {expected!r}, got {actual!r}"))

(defn assert-true [value]
  (assert value f"Expected truthy, got {value!r}"))

(defn assert-false [value]
  (assert (not value) f"Expected falsy, got {value!r}"))

;; ---------------------------------------------------------------------------
;; kinds
;; ---------------------------------------------------------------------------

(defn test-kind-predicate []
  (assert-true (model.kind? model.KIND-LOCAL-FUNCTION))
  (assert-true (model.kind? "reader-macro"))
  (assert-false (model.kind? "not-a-kind"))
  (assert-false (model.kind? 3)))

;; ---------------------------------------------------------------------------
;; source ranges
;; ---------------------------------------------------------------------------

(defn test-source-range-shape []
  (setv sr (model.source-range "file:///a.hy" 1 2 3 4))
  (assert= sr {"uri" "file:///a.hy"
               "range" {"start" {"line" 1 "character" 2}
                        "end" {"line" 3 "character" 4}}})
  (assert-true (model.source-range? sr)))

(defn test-from-hy-model-converts-one-based-positions []
  ;; 1-based start (3,5) -> 0-based (2,4); end column kept as exclusive.
  (setv m (SimpleNamespace :start_line 3 :start_column 5 :end_line 3 :end_column 9))
  (assert= (model.from-hy-model "file:///a.hy" m)
           {"uri" "file:///a.hy"
            "range" {"start" {"line" 2 "character" 4}
                     "end" {"line" 2 "character" 9}}}))

(defn test-from-hy-model-clamps-and-defaults []
  ;; missing end_line falls back to start_line; positions never go negative.
  (setv m (SimpleNamespace :start_line 1 :start_column 1))
  (assert= (model.from-hy-model "file:///a.hy" m)
           {"uri" "file:///a.hy"
            "range" {"start" {"line" 0 "character" 0}
                     "end" {"line" 0 "character" 1}}}))

(defn test-from-hy-model-on-real-form []
  (setv form (get (list (hy.read-many "(defn foo [x] x)")) 0))
  (setv sr (model.from-hy-model "file:///a.hy" form))
  (assert-true (model.source-range? sr))
  (assert= (get (get (get sr "range") "start") "line") 0))

(defn test-source-range-predicate-rejects-bad-shapes []
  (assert-false (model.source-range? {"uri" "x"}))
  (assert-false (model.source-range? {"uri" 1 "range" {"start" {"line" 0 "character" 0}
                                                       "end" {"line" 0 "character" 1}}}))
  (assert-false (model.source-range? "nope")))

;; ---------------------------------------------------------------------------
;; symbols
;; ---------------------------------------------------------------------------

(defn test-symbol-info-defaults []
  (setv sym (model.symbol-info "foo" model.KIND-LOCAL-FUNCTION))
  (assert= (get sym "name") "foo")
  (assert= (get sym "kind") "local-function")
  (assert= (get sym "detail") "")
  (assert= (get sym "source") None)
  (assert= (get sym "runtime-object") None)
  (assert-true (model.symbol-info? sym)))

(defn test-symbol-info-with-source []
  (setv sym (model.symbol-info "foo" model.KIND-LOCAL-MACRO
              :detail "local defmacro"
              :signature "(defmacro foo [x])"
              :source (model.source-range "file:///a.hy" 0 6 0 9)
              :module "demo"))
  (assert-true (model.symbol-info? sym))
  (assert-true (model.source-range? (get sym "source"))))

(defn test-symbol-info-predicate-rejects-bad-kind []
  (assert-false (model.symbol-info? (model.symbol-info "foo" "bogus-kind")))
  (assert-false (model.symbol-info? {"name" "foo"})))

(defn test-hover-text-name-only []
  (assert= (model.hover-text (model.symbol-info "foo" model.KIND-UNKNOWN)) "foo"))

(defn test-hover-text-with-signature-detail-doc []
  (setv sym (model.symbol-info "foo" model.KIND-LOCAL-FUNCTION
              :signature "(foo [x])"
              :detail "local defn"
              :documentation "Does a thing."))
  (assert= (model.hover-text sym) "foo (foo [x])\n[local defn]\n\nDoes a thing."))

;; ---------------------------------------------------------------------------
;; word
;; ---------------------------------------------------------------------------

(defn test-word-prefix-and-word-at []
  (setv source "(lfor x (range 3) x)\n")
  (assert= (word.word-prefix source 0 3) "lf")
  (assert= (word.word-at source 0 2) "lfor")
  (assert= (word.word-range-at source 0 2) #(1 5)))

(defn test-reader-macro-word []
  (setv source "#bang value\n")
  (assert= (word.word-prefix source 0 3) "#ba")
  (assert= (word.word-at source 0 2) "#bang")
  (assert= (word.word-range-at source 0 2) #(0 5)))

(defn test-occurrences []
  (assert= (word.occurrences "(foo)\n(foo bar)\n" "foo") [#(0 1 4) #(1 1 4)])
  (assert= (word.occurrences "(foo)" "") []))

(defn test-enclosing-call []
  (setv source "(foo 1 (+ 2 3) \n")
  (assert= (word.enclosing-call source 0 (len source)) #("foo" 2))
  (assert= (word.enclosing-call "no call here" 0 5) None))

;; ---------------------------------------------------------------------------
;; folding
;; ---------------------------------------------------------------------------

(defn test-folding-ranges-for-multiline-forms []
  (setv ranges (folding.folding-ranges "(defn foo [x]\n  (if x\n    [1\n     2]\n    0))\n"))
  (assert-true (in (folding.fold-range 0 0 4 7) ranges))
  (assert-true (in (folding.fold-range 1 2 4 6) ranges))
  (assert-true (in (folding.fold-range 2 4 3 7) ranges)))

(defn test-folding-ignores-strings-and-comments []
  (setv ranges (folding.folding-ranges "(print \"(\") ; [\n(defn foo []\n  1)\n"))
  (assert= ranges [(folding.fold-range 1 0 2 4)]))

(defn test-folding-tolerates-incomplete-buffers []
  (assert= (folding.folding-ranges "(defn foo []\n  (print 1)\n") []))

;; ---------------------------------------------------------------------------
;; completion-context
;; ---------------------------------------------------------------------------

(defn test-import-module-context []
  (setv source "(import pathli)\n")
  (assert= (cc.completion-context source 0 (len "(import pathli")) (cc.ctx "import-module")))

(defn test-import-member-context []
  (setv source "(import os.path [ex])\n")
  (assert= (cc.completion-context source 0 (+ (.index source "ex") 2))
           (cc.ctx "import-member" "os.path")))

(defn test-require-macro-and-reader-contexts []
  (setv source "(require macros :macros [za] :readers [ba])\n")
  (assert= (cc.completion-context source 0 (+ (.index source "za") 2))
           (cc.ctx "require-macro" "macros"))
  (assert= (cc.completion-context source 0 (+ (.index source "ba") 2))
           (cc.ctx "require-reader" "macros")))

;; ---------------------------------------------------------------------------
;; semantic
;; ---------------------------------------------------------------------------

(defn token-text [source token]
  (setv line (get (.splitlines source) (get token "line")))
  (cut line (get token "start") (+ (get token "start") (get token "length"))))

(defn stub-resolver [symbols]
  (fn [name line character] (.get symbols name None)))

(defn test-semantic-token-encoding-is-relative []
  (setv data (semantic.encode-semantic-tokens
               (semantic.semantic-tokens "1\n  2\n" (fn [n l c] None))))
  (assert= data [0 0 1 7 0 1 2 1 7 0]))

(defn test-semantic-tokens-classify-hy-source []
  (setv source "(defn foo [x]\n  \"Docs\"\n  (+ x 1)) ; comment\n#bang\n")
  (setv resolve (stub-resolver
                  {"defn" (model.symbol-info "defn" model.KIND-CORE-FORM)
                   "foo" (model.symbol-info "foo" model.KIND-LOCAL-FUNCTION)
                   "#bang" (model.symbol-info "#bang" model.KIND-READER-MACRO)}))
  (setv tokens (semantic.semantic-tokens source resolve))
  (setv by-text (set (gfor token tokens #((token-text source token) (get token "token-type")))))
  (assert-true (in #("defn" "keyword") by-text))
  (assert-true (in #("foo" "function") by-text))
  (assert-true (in #("\"Docs\"" "string") by-text))
  (assert-true (in #("+" "operator") by-text))
  (assert-true (in #("1" "number") by-text))
  (assert-true (in #("; comment" "comment") by-text))
  (assert-true (in #("#bang" "macro") by-text)))

;; ---------------------------------------------------------------------------
;; core-docs
;; ---------------------------------------------------------------------------

(defn test-core-docs-table []
  (assert-true (in "defn" core-docs.CORE-DOCS))
  (assert= (get (get core-docs.CORE-DOCS "if") "signature") "(if test true-value false-value)")
  (assert-true (.startswith (get (get core-docs.CORE-DOCS "do") "documentation") "Evaluate BODY")))

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
  (print f"{(len tests)} Hy analysis tests passed"))

(when (= __name__ "__main__")
  (run-tests))
