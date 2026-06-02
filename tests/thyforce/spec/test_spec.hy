(import hy)
(require thyforce.spec.core [genspec])
(import thyforce.spec.core :as spec)

(defn assert= [actual expected]
  (assert (= actual expected) f"Expected {expected !r}, got {actual !r}"))

(defn assert-truthy [value]
  (assert value f"Expected truthy value, got {value !r}"))

(defn assert-falsy [value]
  (assert (not value) f"Expected falsy value, got {value !r}"))

(defn test_primitive_predicates []
  (assert-truthy (spec.str? "thyforce"))
  (assert-falsy (spec.str? 42))
  (assert-truthy (spec.int? 42))
  (assert-falsy (spec.int? True))
  (assert-truthy (spec.bool? False))
  (assert-truthy (spec.nil? None))
  (assert-truthy (spec.map? {"a" 1}))
  (assert-truthy (spec.list? [1 2 3])))

(defn test_combinators []
  (setv non-empty-str? (spec.and-spec spec.str? (fn [x] (> (len x) 0))))
  (setv scalar? (spec.or-spec spec.str? spec.int? spec.bool?))
  (setv maybe-str? (spec.maybe spec.str?))
  (setv string-list? (spec.list-of spec.str?))
  (assert-truthy (non-empty-str? "abc"))
  (assert-falsy (non-empty-str? ""))
  (assert-truthy (scalar? 1))
  (assert-truthy (scalar? "x"))
  (assert-falsy (scalar? []))
  (assert-truthy (maybe-str? None))
  (assert-truthy (maybe-str? "x"))
  (assert-falsy (maybe-str? 1))
  (assert-truthy (string-list? ["a" "b"]))
  (assert-falsy (string-list? ["a" 1])))

(defn test_key_predicate []
  (setv has-name? (spec.key-pred "name" spec.str?))
  (assert-truthy (has-name? {"name" "polhy"}))
  (assert-falsy (has-name? {"name" 1}))
  (assert-falsy (has-name? {"other" "polhy"})))

(defn test_validate_returns_data []
  (assert= (spec.validate spec.str? "ok") {"ok" True "value" "ok" "errors" []})
  (setv result (spec.validate spec.str? 1))
  (assert= (get result "ok") False)
  (assert= (get result "value") 1)
  (assert= (get (get result "errors") 0) {"code" "failed-spec" "message" "value failed spec"}))

(defn test_genspec_builds_nested_map_predicate []
  (setv workspace?
    (genspec {"namespace" spec.str?
              "paths" {"bases" spec.str?
                       "components" spec.str?
                       "test-root" spec.str?}
              "retries" spec.int?}))
  (assert-truthy
    (workspace? {"namespace" "thyforce"
                 "paths" {"bases" "bases"
                          "components" "components"
                          "test-root" "tests"}
                 "retries" 3}))
  (assert-falsy
    (workspace? {"namespace" "thyforce"
                 "paths" {"bases" "bases"
                          "components" "components"}
                 "retries" 3}))
  (assert-falsy
    (workspace? {"namespace" "thyforce"
                 "paths" {"bases" "bases"
                          "components" "components"
                          "test-root" "tests"}
                 "retries" True})))

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
  (print f"{(len tests)} Hy spec tests passed"))

(when (= __name__ "__main__")
  (run-tests))
