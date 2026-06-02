"Form-based dependency report.

For each brick, parses its source with `forms.module-refs` and classifies every
referenced module as a brick dependency (resolves to another brick's import
name), a third-party library, or stdlib (dropped). Output:

    {brick-name -> {\"bricks\" [dep-brick ...] \"libs\" [third-party ...]}}
"

(import sys)
(import pathlib [Path])
(import thyforce.polhy.config :as config_core)
(import thyforce.polhy.workspace :as workspace)
(import thyforce.polhy.forms :as forms)

(defn source-files [path adapter]
  (setv ext (.get adapter "source-ext" ".hy"))
  (list (.rglob (Path path) f"*{ext}")))

(defn brick-modules [brick adapter]
  "All import/require module names referenced by a brick's source files."
  (setv mods [])
  (for [file (source-files (get brick "path") adapter)]
    (setv text (.read-text file :encoding "utf-8" :errors "ignore"))
    (for [ref (forms.module-refs text)]
      (.append mods (get ref "module"))))
  mods)

(defn brick-import-name [namespace brick-name]
  "The dotted import prefix a brick's modules live under (slashes -> dots)."
  (+ namespace "." (.replace brick-name "/" ".")))

(defn classify [module bricks namespace]
  "Classify MODULE as [\"brick\" name] / [\"lib\" top] / [\"stdlib\" top].

Internal bricks win by longest matching import-name prefix, so nested bricks
(`polhy/cli` vs `polhy`) resolve to the most specific one.
  "
  (setv best-name None)
  (setv best-len -1)
  (for [b bricks]
    (setv iname (brick-import-name namespace (get b "name")))
    (when (and (or (= module iname) (.startswith module (+ iname ".")))
               (> (len iname) best-len))
      (setv best-name (get b "name"))
      (setv best-len (len iname))))
  (when (is-not best-name None)
    (return ["brick" best-name]))
  (setv top (get (.split module ".") 0))
  (if (in (.replace top "-" "_") sys.stdlib-module-names)
      ["stdlib" top]
      ["lib" top]))

(defn dependency-report [[start None]]
  "Return {brick-name -> {bricks, libs}} via form-based parsing + classification."
  (setv data (workspace.info start))
  (setv namespace (get data "namespace"))
  (setv cfg (config_core.load-config (get data "root")))
  (setv adapter (config_core.adapter cfg))
  (setv bricks (+ (get data "bases") (get data "components")))
  (setv report {})
  (for [b bricks]
    (setv brick-deps (set))
    (setv libs (set))
    (for [module (brick-modules b adapter)]
      (setv [kind name] (classify module bricks namespace))
      (cond
        (and (= kind "brick") (!= name (get b "name"))) (.add brick-deps name)
        (= kind "lib") (.add libs name)))
    (setv (get report (get b "name"))
          {"bricks" (sorted brick-deps) "libs" (sorted libs)}))
  report)
