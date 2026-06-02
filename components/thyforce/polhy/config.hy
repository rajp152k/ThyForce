(import os hy.importer)
(import pathlib [Path])

(setv DEFAULT-CONFIG-NAME "workspace.cfg.hy")

(defn workspace-root [[start None] [config-name DEFAULT-CONFIG-NAME]]
  (setv current (.resolve (Path (or start (os.getcwd)))))
  (when (.exists (/ current config-name))
    (return current))
  (for [candidate (list current.parents)]
    (when (.exists (/ candidate config-name))
      (return candidate)))
  (raise (FileNotFoundError f"Cannot find {config-name}")))

(defn load-data [path var-name]
  "Evaluate a .cfg.hy file and return its named top-level variable."
  (setv path (Path path))
  (setv loader (type "ConfigLoader" #() {"path" (str path) "name" "thyforce_polhy_cfg"}))
  (setv code (hy.importer._hy_source_to_code (loader) (.read_bytes path) (str path) "thyforce_polhy_cfg"))
  (setv ns {"__name__" "thyforce_polhy_cfg"})
  (exec code ns)
  (get ns var-name))

(defn load-config [[root None]]
  (setv root-path (workspace-root root))
  (load-data (/ root-path DEFAULT-CONFIG-NAME) "CONFIG"))

(defn get-in [data path [default None]]
  (setv current data)
  (for [key path]
    (if (and (isinstance current dict) (in key current))
        (setv current (get current key))
        (return default)))
  current)

(defn adapter [config [language None]]
  (setv lang (or language (get-in config ["language" "default"])))
  (get-in config ["language" "adapters" lang] {}))
