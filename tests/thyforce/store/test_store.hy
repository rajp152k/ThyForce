"Tests for the thyforce/store component (ADR-0001 persistence model).

Behavioural coverage across both backends: id ordering, range reads, projection
folding + determinism, fact isolation, input validation, and sqlite durability
across a reopen. Run standalone: `hy tests/thyforce/store/test_store.hy`.
"

(import tempfile)
(import pathlib [Path])
(import hy)
(import thyforce.store.core :as store)

(defn assert= [actual expected]
  (assert (= actual expected) f"expected {expected !r}, got {actual !r}"))

(defn backend-configs []
  "Both backends, exercised by the same behavioural assertions."
  [{"backend" "memory"} {"backend" "sqlite" "path" ":memory:"}])

(defn test-append-assigns-sequential-ids []
  (for [cfg (backend-configs)]
    (setv s (store.open-store cfg))
    (try
      (setv f1 (store.append-fact s {"type" "note" "data" {"text" "a"}}))
      (setv f2 (store.append-fact s {"type" "note" "data" {"text" "b"}}))
      (assert= (get f1 "id") 1)
      (assert= (get f2 "id") 2)
      (assert= (get f1 "type") "note")
      (assert= (get (get f1 "data") "text") "a")
      (finally (store.close-store s)))))

(defn test-data-defaults-to-empty-map []
  (for [cfg (backend-configs)]
    (setv s (store.open-store cfg))
    (try
      (setv f (store.append-fact s {"type" "ping"}))
      (assert= (get f "data") {})
      (finally (store.close-store s)))))

(defn test-read-ordering-and-range []
  (for [cfg (backend-configs)]
    (setv s (store.open-store cfg))
    (try
      (for [i (range 5)]
        (store.append-fact s {"type" "n" "data" {"i" i}}))
      (assert= (lfor f (store.read-facts s) (get f "id")) [1 2 3 4 5])
      (assert= (lfor f (store.read-facts s :since 2 :until 4) (get f "id")) [2 3 4])
      (assert= (lfor f (store.read-facts s :since 4) (get f "id")) [4 5])
      (assert= (lfor f (store.read-facts s :until 2) (get f "id")) [1 2])
      (finally (store.close-store s)))))

(defn test-project-folds-and-is-deterministic []
  (defn count-by-type [view fact]
    (setv typ (get fact "type"))
    (setv out (dict view))
    (setv (get out typ) (+ (.get out typ 0) 1))
    out)
  (for [cfg (backend-configs)]
    (setv s (store.open-store cfg))
    (try
      (for [t ["a" "b" "a" "a"]]
        (store.append-fact s {"type" t "data" {}}))
      (setv v1 (store.project s count-by-type {}))
      (setv v2 (store.project s count-by-type {}))
      (assert= v1 {"a" 3 "b" 1})
      ;; replay is deterministic: same log -> same view
      (assert= v1 v2)
      (finally (store.close-store s)))))

(defn test-stored-facts-are-isolated []
  (for [cfg (backend-configs)]
    (setv s (store.open-store cfg))
    (try
      (setv src {"type" "n" "data" {"x" 1}})
      (store.append-fact s src)
      ;; mutating the source after append must not change the store
      (setv (get (get src "data") "x") 999)
      (setv f (get (store.read-facts s) 0))
      (assert= (get (get f "data") "x") 1)
      ;; mutating a read result must not change the store
      (setv (get (get f "data") "x") 777)
      (assert= (get (get (get (store.read-facts s) 0) "data") "x") 1)
      (finally (store.close-store s)))))

(defn test-unknown-backend-raises []
  (try
    (store.open-store {"backend" "redis"})
    (raise (AssertionError "expected ValueError for unknown backend"))
    (except [e ValueError] None)))

(defn test-invalid-fact-raises []
  (setv s (store.open-store {"backend" "memory"}))
  (defn expect-rejects [fact]
    (try
      (store.append-fact s fact)
      (raise (AssertionError f"expected ValueError for {fact !r}"))
      (except [e ValueError] None)))
  (try
    (expect-rejects {"data" {}})       ; missing type
    (expect-rejects {"type" 5})        ; non-string type
    (expect-rejects {"type" ""})       ; empty type
    (finally (store.close-store s))))

(defn test-sqlite-durability-across-reopen []
  (setv td (tempfile.TemporaryDirectory))
  (try
    (setv path (str (/ (Path td.name) "facts.db")))
    (setv s1 (store.open-store {"backend" "sqlite" "path" path}))
    (store.append-fact s1 {"type" "note" "data" {"k" 1}})
    (store.append-fact s1 {"type" "note" "data" {"k" 2}})
    (store.close-store s1)
    (setv s2 (store.open-store {"backend" "sqlite" "path" path}))
    (try
      (setv facts (store.read-facts s2))
      (assert= (len facts) 2)
      (assert= (lfor f facts (get f "id")) [1 2])
      (assert= (lfor f facts (get (get f "data") "k")) [1 2])
      (finally (store.close-store s2)))
    (finally (.cleanup td))))

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
