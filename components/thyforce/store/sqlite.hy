"SQLite store backend: a single-table append-only fact log.

`id` is the AUTOINCREMENT primary key (a total order starting at 1); `data` is
stored as JSON text. File-backed databases run in WAL mode for durable,
concurrent reads under a single writer (ADR-0001). `:memory:` gives an
ephemeral per-connection store.
"

(import json sqlite3)

(setv SCHEMA
  "CREATE TABLE IF NOT EXISTS facts (
     id   INTEGER PRIMARY KEY AUTOINCREMENT,
     time REAL    NOT NULL,
     type TEXT    NOT NULL,
     data TEXT    NOT NULL)")

(defn open [config]
  (setv path (.get config "path" ":memory:"))
  (setv conn (sqlite3.connect path))
  (when (!= path ":memory:")
    (.execute conn "PRAGMA journal_mode=WAL"))
  (.execute conn SCHEMA)
  (.commit conn)
  conn)

(defn _row->fact [row]
  (setv [fid t typ data] row)
  {"id" fid "time" t "type" typ "data" (json.loads data)})

(defn append [conn fact]
  (setv t (get fact "time"))
  (setv typ (get fact "type"))
  (setv data (json.dumps (get fact "data")))
  (setv cur (.execute conn "INSERT INTO facts (time, type, data) VALUES (?, ?, ?)"
                      #(t typ data)))
  (.commit conn)
  {"id" cur.lastrowid "time" t "type" typ "data" (json.loads data)})

(defn read [conn since until]
  (setv clauses [])
  (setv params [])
  (when (is-not since None)
    (.append clauses "id >= ?")
    (.append params since))
  (when (is-not until None)
    (.append clauses "id <= ?")
    (.append params until))
  (setv where (if clauses (+ " WHERE " (.join " AND " clauses)) ""))
  (setv sql (+ "SELECT id, time, type, data FROM facts" where " ORDER BY id"))
  (lfor row (.fetchall (.execute conn sql (tuple params))) (_row->fact row)))

(defn close [conn]
  (.close conn))
