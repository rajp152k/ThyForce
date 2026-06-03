"In-memory store backend: an ordered list of facts. For tests and ephemera.

Facts are deep-copied on the way in and out so stored facts are isolated from
caller mutation, matching the serialize/deserialize isolation of the sqlite
backend.
"

(import copy)

(defn open [config]
  {"facts" [] "next-id" 1})

(defn append [handle fact]
  (setv fid (get handle "next-id"))
  (setv stored (copy.deepcopy fact))
  (setv (get stored "id") fid)
  (.append (get handle "facts") stored)
  (setv (get handle "next-id") (+ fid 1))
  (copy.deepcopy stored))

(defn read [handle since until]
  (lfor fact (get handle "facts")
        :if (and (or (is since None) (>= (get fact "id") since))
                 (or (is until None) (<= (get fact "id") until)))
        (copy.deepcopy fact)))
