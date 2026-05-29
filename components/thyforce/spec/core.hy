(import collections.abc [Mapping])

(defn str? [value]
  (isinstance value str))

(defn int? [value]
  (and (isinstance value int) (not (isinstance value bool))))

(defn float? [value]
  (and (isinstance value float) (not (isinstance value bool))))

(defn bool? [value]
  (isinstance value bool))

(defn nil? [value]
  (is value None))

(defn map? [value]
  (isinstance value Mapping))

(defn list? [value]
  (isinstance value list))

(defn valid? [pred value]
  (bool (pred value)))

(defn validate [pred value]
  (setv ok (valid? pred value))
  {"ok" ok
   "value" value
   "errors" (if ok [] [{"code" "failed-spec" "message" "value failed spec"}])})

(defn and-spec [#* preds]
  (fn [value]
    (all (map (fn [pred] (pred value)) preds))))

(defn or-spec [#* preds]
  (fn [value]
    (any (map (fn [pred] (pred value)) preds))))

(defn maybe [pred]
  (or-spec nil? pred))

(defn list-of [pred]
  (fn [value]
    (and (list? value)
         (all (map pred value)))))

(defn has-key? [key]
  (fn [value]
    (and (map? value) (in key value))))

(defn key-pred [key pred]
  (fn [value]
    (and (map? value)
         (in key value)
         (pred (get value key)))))

(defn genspec* [spec-form]
  (if (map? spec-form)
      (do
        (setv field-preds
              (list (map (fn [item]
                           (setv key (get item 0))
                           (setv pred (genspec* (get item 1)))
                           (key-pred key pred))
                         (.items spec-form))))
        (fn [value]
          (and (map? value)
               (all (map (fn [pred] (pred value)) field-preds)))))
      spec-form))

(defmacro genspec [spec-form]
  `(do
     (import thyforce.spec.core :as _thyforce_spec_core)
     (_thyforce_spec_core.genspec* ~spec-form)))
