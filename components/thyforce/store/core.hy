"Append-only fact store: facts, projections, and a backend-agnostic interface.

Implements the persistence model of ADR-0001. A fact is an immutable record

    {\"id\" <ordinal> \"time\" <epoch-seconds> \"type\" <string> \"data\" <map>}

appended to an ordered log. `id` is assigned by the store and defines a total
order; projections fold the log into derived views. Backends are selected by
config data; `sqlite` (durable, single-writer) is the default and `memory`
exists for tests. Callers depend on this interface, never on a backend.
"

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

(defn make-fact [type data]
  "Construct an un-stored fact map; `id`/`time` are assigned on append."
  {"type" type "data" data})

(defn open-store [[config None]]
  "Open a store from CONFIG (a map). `backend` selects the adapter (default sqlite).

Returns a store map; pass it to `append-fact` / `read-facts` / `project`.
  "
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
