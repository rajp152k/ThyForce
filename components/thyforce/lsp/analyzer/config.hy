"Workspace configuration for the language analysis.

Configuration is a plain data map:

    {\"index-limit\" int \"exclude-dirs\" [str ...] \"allow-workspace-imports\" bool}

End users configure the server through a [tool.hyground] table in their project's
pyproject.toml. That TOML table is treated purely as an external compatibility
surface; the internal representation is this Hy map. Unknown keys are ignored and
invalid values fall back to safe defaults so server startup never fails on config.
"

(import tomllib)
(import pathlib [Path])
(import thyforce.spec.core :as spec)

(setv DEFAULT-INDEX-LIMIT 500)
(setv DEFAULT-EXCLUDE-DIRS
  [".git" ".hg" ".svn" ".venv" "venv" "__pycache__" ".mypy_cache" ".pytest_cache"])

(defn config [[index-limit DEFAULT-INDEX-LIMIT] [exclude-dirs None] [allow-workspace-imports True]]
  "Build a configuration map with defaults."
  {"index-limit" index-limit
   "exclude-dirs" (if (is exclude-dirs None) (list DEFAULT-EXCLUDE-DIRS) exclude-dirs)
   "allow-workspace-imports" allow-workspace-imports})

(setv config?
  (spec.and-spec
    (spec.key-pred "index-limit" spec.int?)
    (spec.key-pred "exclude-dirs" (spec.list-of spec.str?))
    (spec.key-pred "allow-workspace-imports" spec.bool?)))

(defn _get [table kebab snake]
  (if (in kebab table) (get table kebab) (.get table snake)))

(defn _positive-int [value default]
  (if (and (isinstance value int) (not (isinstance value bool)) (> value 0)) value default))

(defn _exclude-dirs [value]
  (setv extras [])
  (when (isinstance value list)
    (for [item value]
      (when (and (isinstance item str) item)
        (.append extras item))))
  (list (dict.fromkeys [#* DEFAULT-EXCLUDE-DIRS #* extras])))

(defn _bool [value default]
  (if (isinstance value bool) value default))

(defn load-config [root]
  "Load [tool.hyground] config from ROOT/pyproject.toml, falling back to defaults."
  (setv pyproject (/ (Path root) "pyproject.toml"))
  (when (not (.exists pyproject))
    (return (config)))
  (try
    (setv data (tomllib.loads (.read-text pyproject :encoding "utf-8")))
    (except [#(OSError tomllib.TOMLDecodeError)]
      (return (config))))
  (setv table (.get (.get data "tool" {}) "hyground" {}))
  (when (not (isinstance table dict))
    (return (config)))
  (config
    :index-limit (_positive-int (_get table "index-limit" "index_limit") DEFAULT-INDEX-LIMIT)
    :exclude-dirs (_exclude-dirs (_get table "exclude-dirs" "exclude_dirs"))
    :allow-workspace-imports (_bool (_get table "allow-workspace-imports" "allow_workspace_imports") True)))
