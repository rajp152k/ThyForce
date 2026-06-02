"Predicate-based specs with path-precise validation traces.

A spec is a callable predicate (value -> truthy/falsey); `(str? x)` returns a
bool and any spec can be called directly. Combinators additionally attach a
`_spec_meta` dict describing their structure, so `explain`/`validate` can walk
the spec tree and report exactly which path failed which predicate.

    (validate spec value) -> {\"ok\" bool \"value\" value \"problems\" [problem ...]}
    problem               -> {\"path\" [key|index ...] \"pred\" str \"value\" any \"message\" str}
"

(import collections.abc [Mapping])
(import hy)

;; ---------------------------------------------------------------------------
;; spec metadata
;; ---------------------------------------------------------------------------

(defn _with-meta [pred meta]
  (setv pred._spec_meta meta)
  pred)

(defn _meta [spec]
  (getattr spec "_spec_meta" None))

(defn named [name pred]
  "Wrap PRED with a human-readable NAME for traces (use on leaf predicates)."
  (defn wrapped [value] (pred value))
  (_with-meta wrapped {"kind" "pred" "name" name}))

;; ---------------------------------------------------------------------------
;; primitive predicates
;; ---------------------------------------------------------------------------

(defn str? [value] (isinstance value str))
(defn int? [value] (and (isinstance value int) (not (isinstance value bool))))
(defn float? [value] (and (isinstance value float) (not (isinstance value bool))))
(defn bool? [value] (isinstance value bool))
(defn nil? [value] (is value None))
(defn map? [value] (isinstance value Mapping))
(defn list? [value] (isinstance value list))

(for [[pred name] [[str? "str?"] [int? "int?"] [float? "float?"] [bool? "bool?"]
                   [nil? "nil?"] [map? "map?"] [list? "list?"]]]
  (_with-meta pred {"kind" "pred" "name" name}))

(defn valid? [pred value]
  (bool (pred value)))

;; ---------------------------------------------------------------------------
;; combinators
;; ---------------------------------------------------------------------------

(defn and-spec [#* preds]
  (_with-meta
    (fn [value] (all (gfor pred preds (pred value))))
    {"kind" "and" "parts" (list preds)}))

(defn or-spec [#* preds]
  (_with-meta
    (fn [value] (any (gfor pred preds (pred value))))
    {"kind" "or" "parts" (list preds)}))

(defn maybe [pred]
  (_with-meta
    (fn [value] (or (nil? value) (pred value)))
    {"kind" "maybe" "pred" pred}))

(defn list-of [pred]
  (_with-meta
    (fn [value] (and (list? value) (all (gfor item value (pred item)))))
    {"kind" "list-of" "elem" pred}))

(defn has-key? [key]
  (_with-meta
    (fn [value] (and (map? value) (in key value)))
    {"kind" "pred" "name" (.format "has-key?({})" key)}))

(defn key-pred [key pred]
  (_with-meta
    (fn [value] (and (map? value) (in key value) (pred (get value key))))
    {"kind" "key" "key" key "pred" pred}))

(defn genspec* [spec-form]
  (if (map? spec-form)
      (do
        (setv fields {})
        (for [[key sub] (.items spec-form)]
          (setv (get fields key) (genspec* sub)))
        (_with-meta
          (fn [value]
            (and (map? value)
                 (all (gfor [key sub] (.items fields)
                            (and (in key value) (valid? sub (get value key)))))))
          {"kind" "map" "fields" fields}))
      spec-form))

(defmacro genspec [spec-form]
  `(do
     (import thyforce.spec.core :as _thyforce_spec_core)
     (_thyforce_spec_core.genspec* ~spec-form)))

;; ---------------------------------------------------------------------------
;; explanation / validation
;; ---------------------------------------------------------------------------

(defn _pred-name [spec]
  (setv meta (_meta spec))
  (cond
    (and meta (.get meta "name")) (get meta "name")
    (hasattr spec "__name__") (hy.unmangle spec.__name__)
    True "predicate"))

(defn _or-name [meta]
  (.format "or({})" (.join ", " (lfor p (get meta "parts") (_pred-name p)))))

(defn _path-str [path]
  (setv out "")
  (for [elem path]
    (setv out (+ out (if (isinstance elem int) (.format "[{}]" elem) (.format ".{}" elem)))))
  (if (.startswith out ".") (cut out 1 None) out))

(defn _problem [path pred value [message None]]
  (setv where (_path-str path))
  {"path" (list path)
   "pred" pred
   "value" value
   "message" (or message
                 (if where (.format "{}: failed {}" where pred) (.format "failed {}" pred)))})

(defn _missing [path key]
  (setv full (+ path [key]))
  (_problem full "required" None (.format "{}: missing key" (_path-str full))))

(defn explain [spec value [path None]]
  "Return a list of problem maps describing why VALUE fails SPEC (empty if valid)."
  (setv path (or path []))
  (setv meta (_meta spec))
  (setv kind (if meta (get meta "kind") "pred"))
  (cond
    (= kind "and")
      (do (setv problems [])
          (for [part (get meta "parts")] (.extend problems (explain part value path)))
          problems)
    (= kind "or")
      (if (any (gfor part (get meta "parts") (valid? part value)))
          []
          [(_problem path (_or-name meta) value)])
    (= kind "maybe")
      (if (nil? value) [] (explain (get meta "pred") value path))
    (= kind "list-of")
      (if (not (list? value))
          [(_problem path "list?" value)]
          (do (setv problems [])
              (for [[i item] (enumerate value)]
                (.extend problems (explain (get meta "elem") item (+ path [i]))))
              problems))
    (= kind "key")
      (cond
        (not (map? value)) [(_problem path "map?" value)]
        (not (in (get meta "key") value)) [(_missing path (get meta "key"))]
        True (explain (get meta "pred") (get value (get meta "key")) (+ path [(get meta "key")])))
    (= kind "map")
      (if (not (map? value))
          [(_problem path "map?" value)]
          (do (setv problems [])
              (for [[key sub] (.items (get meta "fields"))]
                (if (in key value)
                    (.extend problems (explain sub (get value key) (+ path [key])))
                    (.append problems (_missing path key))))
              problems))
    True
      (if (valid? spec value) [] [(_problem path (_pred-name spec) value)])))

(defn validate [spec value]
  "Validate VALUE against SPEC; return {ok, value, problems} with path-precise traces."
  (setv problems (explain spec value))
  {"ok" (= (len problems) 0) "value" value "problems" problems})
