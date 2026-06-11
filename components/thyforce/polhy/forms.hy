"Walk Hy AST to extract import/require module references from source text."

(import hy)
(import hy.models [Expression Symbol List :as HyList Keyword])

(defn _symbol-name [model]
  (if (isinstance model Symbol) (str model) None))

(defn _module-name [model]
  "Module name from a Symbol (`os.path`) or a `(. a b)` dotted expression."
  (cond
    (isinstance model Symbol) (str model)
    (and (isinstance model Expression) model (= (_symbol-name (get model 0)) "."))
      (.join "." (gfor part (cut model 1 None) :if (isinstance part Symbol) (str part)))
    True None))

(defn _is-star [model]
  (and (isinstance model Symbol) (= (str model) "*")))

(defn _clause-modules [items]
  "Module names from import/require items, skipping trailing modifier forms."
  (setv mods [])
  (setv i 0)
  (setv n (len items))
  (while (< i n)
    (setv module (_module-name (get items i)))
    (if (is module None)
        (+= i 1)
        (do
          (.append mods module)
          (+= i 1)
          (while (< i n)
            (setv item (get items i))
            (cond
              (isinstance item HyList) (+= i 1)
              (_is-star item) (+= i 1)
              (isinstance item Keyword) (+= i 2)
              (isinstance item Symbol) (break)
              True (+= i 1))))))
  mods)

(defn _walk [form refs]
  (when (and (isinstance form Expression) form)
    (setv head (_symbol-name (get form 0)))
    (when (in head #{"import" "require"})
      (for [module (_clause-modules (list (cut form 1 None)))]
        (.append refs {"kind" head "module" module})))
    (for [child form]
      (_walk child refs)))
  (when (isinstance form HyList)
    (for [child form]
      (_walk child refs))))

(defn module-refs [source [filename "<deps>"]]
  "Return import/require module records for SOURCE; tolerant of read errors."
  (setv refs [])
  (try
    (setv forms (list (hy.read-many source :filename filename)))
    (except [Exception]
      (return refs)))
  (for [form forms]
    (_walk form refs))
  refs)
