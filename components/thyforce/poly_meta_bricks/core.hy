(import os re)
(import pathlib [Path])
(import thyforce.poly_meta_config.core :as config_core)

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
  (setv tests (config_core.get-in config ["paths" "tests"] "test"))
  (setv pattern (config_core.get-in config ["layout" "test-path"]))
  (/ root (format-template pattern {"kind" kind "namespace" ns "name" name "tests" tests})))

(defn template [config language key]
  (config_core.get-in config ["templates" language key] ""))

(defn create-brick [root config kind name [language None] [overwrite False]]
  (setv lang (or language (config_core.get-in config ["language" "default"])))
  (setv adapter (config_core.adapter config lang))
  (setv data {"namespace" (get config "namespace") "name" name "kind" kind})
  (setv target (brick-path root config kind name))
  (setv test-target (test-path root config kind name))
  (setv module-file (get adapter "module-file" "core.hy"))
  (setv interface-file (get adapter "interface-file" "__init__.py"))
  (setv test-file (get adapter "test-file" "test_core.hy"))
  (write-file (/ target module-file)
              (template config lang (if (= kind (config_core.get-in config ["paths" "bases"] "bases")) "base-core" "component-core"))
              overwrite)
  (write-file (/ target interface-file) (format-template (template config lang "interface") data) overwrite)
  (write-file (/ test-target test-file) (format-template (template config lang "test") data) overwrite)
  {"brick" name "kind" kind "path" (str target)})

(defn list-bricks [root config kind]
  (setv ns (get config "namespace"))
  (setv base (/ root kind ns))
  (if (.exists base)
      (list (map (fn [p] {"name" p.name "kind" kind "path" (str p)})
                 (filter (fn [p] (and (.is_dir p) (not-in p.name ["__pycache__" ".venv"]))) (.iterdir base))))
      []))
