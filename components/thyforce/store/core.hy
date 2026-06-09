"Append-only fact store: facts, projections, and backend-agnostic interface."

(import time)
(import thyforce.spec.core :as spec)
(import thyforce.store.sqlite :as sqlite-backend)
(import thyforce.store.memory :as memory-backend)

(setv BACKENDS {"sqlite" sqlite-backend "memory" memory-backend})
(setv DEFAULT-BACKEND "sqlite")

(defn non-empty-str? [value]
  (and (spec.str? value) (> (len value) 0)))

(setv fact-input?
  (spec.and-spec
    (spec.key-pred "type" (spec.named "non-empty-str?" non-empty-str?))
    (spec.key-pred "data" spec.map?)))


(defn open-store [[config None]]
  "Open a store from CONFIG map; `backend` key selects the adapter (default sqlite)."
  (setv cfg (or config {}))
  (setv name (.get cfg "backend" DEFAULT-BACKEND))
  (when (not (in name BACKENDS))
    (raise (ValueError (.format "unknown store backend: {!r}" name))))
  (setv backend (get BACKENDS name))
  {"engine/type" "store"
   "backend" name
   "handle" (backend.open cfg)})

(defn _backend [store]
  (get BACKENDS (get store "backend")))

(defn append-fact [store fact]
  "Validate, stamp (`time` if absent), and append FACT; return the stored fact."
  (setv normalized (dict fact))
  (when (not (in "data" normalized))
    (setv (get normalized "data") {}))
  (when (not (in "time" normalized))
    (setv (get normalized "time") (time.time)))
  (setv result (spec.validate fact-input? normalized))
  (when (not (get result "ok"))
    (raise (ValueError (.format "invalid fact: {}" (get result "problems")))))
  (setv backend (_backend store))
  (backend.append (get store "handle") normalized))

(defn read-facts [store [since None] [until None]]
  "Facts in `id` order. SINCE/UNTIL are inclusive `id` bounds (None = unbounded)."
  (setv backend (_backend store))
  (backend.read (get store "handle") since until))

(defn project [store projection initial [since None] [until None]]
  "Left-fold PROJECTION `(view fact -> view)` over the log, starting at INITIAL."
  (setv view initial)
  (for [fact (read-facts store since until)]
    (setv view (projection view fact)))
  view)

(defn close-store [store]
  "Release backend resources, if the backend holds any."
  (setv backend (_backend store))
  (when (hasattr backend "close")
    (backend.close (get store "handle"))))
