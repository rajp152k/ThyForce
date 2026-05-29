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

(defn load-config [[root None]]
  (setv root-path (workspace-root root))
  (setv config-path (/ root-path DEFAULT-CONFIG-NAME))
  (setv loader (type "ConfigLoader" #() {"path" (str config-path) "name" "thyforce_polhy_workspace_config"}))
  (setv code (hy.importer._hy_source_to_code (loader) (.read_bytes config-path) (str config-path) "thyforce_polhy_workspace_config"))
  (setv ns {"__name__" "thyforce_polhy_workspace_config"})
  (exec code ns)
  (get ns "CONFIG"))

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
