(import hy)
(import types [SimpleNamespace])
(import thyforce.analysis.model :as model)

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
