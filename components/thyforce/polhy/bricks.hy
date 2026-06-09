(import os re)
(import pathlib [Path])
(import thyforce.polhy.config :as config_core)

(defn format-template [template data]
  (.format template #** data))

(defn ensure-dir [path]
  (.mkdir path :parents True :exist-ok True)
  path)

(defn write-file [path content [overwrite False]]
  (ensure-dir path.parent)
  (when (and (.exists path) (not overwrite))
    (raise (FileExistsError (str path))))
  (.write_text path content :encoding "utf-8")
  path)

(defn brick-path [root config kind name]
  (setv ns (get config "namespace"))
  (setv pattern (config_core.get-in config ["layout" "brick-path"]))
  (/ root (format-template pattern {"kind" kind "namespace" ns "name" name})))

(defn test-path [root config kind name]
  (setv ns (get config "namespace"))
  (setv test-root (config_core.get-in config ["paths" "test-root"] "tests"))
  (setv pattern (config_core.get-in config ["layout" "test-path"]))
  (/ root (format-template pattern {"kind" kind "namespace" ns "name" name "test-root" test-root})))

(defn template [config language key]
  (config_core.get-in config ["templates" language key] ""))

(setv DEFAULT-NAMESPACE-SHIM "from pkgutil import extend_path\n__path__ = extend_path(__path__, __name__)\n")

(defn namespace-shim-text [config [language None]]
  "Text for a namespace-spanning package __init__.py (config template or default)."
  (setv lang (or language (config_core.get-in config ["language" "default"])))
  (setv text (template config lang "namespace-shim"))
  (if text text DEFAULT-NAMESPACE-SHIM))

(defn ancestor-package-dirs [root config kind name]
  "Dirs above a brick that must carry a namespace-spanning __init__.py."
  (setv ns (get config "namespace"))
  (setv kind-root (/ (Path root) kind ns))
  (setv parts (.split name "/"))
  (setv dirs [kind-root])
  (for [i (range 1 (len parts))]
    (.append dirs (/ kind-root (.join "/" (cut parts 0 i)))))
  dirs)

(defn ensure-namespace-shims [root config kind name [language None]]
  "Write namespace shim into each ancestor package dir lacking __init__.py."
  (setv text (namespace-shim-text config language))
  (setv created [])
  (for [dir (ancestor-package-dirs root config kind name)]
    (setv init (/ dir "__init__.py"))
    (when (not (.exists init))
      (ensure-dir dir)
      (.write_text init text :encoding "utf-8")
      (.append created (str init))))
  created)

(defn create-brick [root config kind name [language None] [overwrite False]]
  (setv lang (or language (config_core.get-in config ["language" "default"])))
  (setv adapter (config_core.adapter config lang))
  (setv data {"namespace" (get config "namespace") "name" name "import-name" (.replace name "/" ".") "kind" kind})
  (setv target (brick-path root config kind name))
  (setv test-target (test-path root config kind name))
  (setv module-file (.get adapter "module-file" "core.hy"))
  (setv interface-file (.get adapter "interface-file" "__init__.py"))
  (setv test-file (.get adapter "test-file" "test_core.hy"))
  (write-file (/ target module-file)
              (format-template (template config lang (if (= kind (config_core.get-in config ["paths" "bases"] "bases")) "base-core" "component-core")) data)
              overwrite)
  (write-file (/ target interface-file) (format-template (template config lang "interface") data) overwrite)
  (write-file (/ test-target test-file) (format-template (template config lang "test") data) overwrite)
  (setv shims (ensure-namespace-shims root config kind name lang))
  {"brick" name "kind" kind "path" (str target) "shims" shims})

(defn list-bricks [root config kind]
  (setv ns (get config "namespace"))
  (setv base (/ root kind ns))
  (setv adapter (config_core.adapter config))
  (setv module-file (.get adapter "module-file" "core.hy"))
  (if (.exists base)
      (list (map (fn [p]
                   (setv brick-dir p.parent)
                   (setv rel (.as_posix (.relative_to brick-dir base)))
                   {"name" rel "kind" kind "path" (str brick-dir)})
                 (.rglob base module-file)))
      []))

(defn brick-structure-issues [root config]
  "Issues for bricks missing their interface file or an ancestor namespace shim."
  (setv adapter (config_core.adapter config))
  (setv interface-file (.get adapter "interface-file" "__init__.py"))
  (setv components-key (config_core.get-in config ["paths" "components"] "components"))
  (setv bases-key (config_core.get-in config ["paths" "bases"] "bases"))
  (setv issues [])
  (for [kind [components-key bases-key]]
    (for [brick (list-bricks root config kind)]
      (setv bdir (Path (get brick "path")))
      (setv name (get brick "name"))
      (when (not (.exists (/ bdir interface-file)))
        (.append issues {"brick" name "kind" kind "code" "missing-interface"
                         "message" (.format "missing {}" interface-file)}))
      (for [dir (ancestor-package-dirs root config kind name)]
        (when (not (.exists (/ dir "__init__.py")))
          (.append issues {"brick" name "kind" kind "code" "missing-namespace-shim"
                           "message" (.format "missing {}/__init__.py" (.as_posix (.relative_to dir (Path root))))})))))
  issues)
