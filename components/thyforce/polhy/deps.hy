"Form-based dependency report resolving each import as brick, lib, or stdlib."

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
  "Classify MODULE as [brick name] / [lib top] / [stdlib top]; longest prefix wins."
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

(defn brick-graph [report]
  "Adjacency map brick -> sorted brick deps, restricted to bricks in REPORT."
  (setv nodes (set (.keys report)))
  (setv graph {})
  (for [[name info] (.items report)]
    (setv (get graph name) (sorted (lfor d (.get info "bricks" []) :if (in d nodes) d))))
  graph)

(defn strongly-connected-components [graph]
  "Tarjan's SCCs of GRAPH (adjacency map node -> list of successors)."
  (setv counter [0])
  (setv index {})
  (setv lowlink {})
  (setv stack [])
  (setv on-stack (set))
  (setv result [])
  (defn strongconnect [node]
    (setv (get index node) (get counter 0))
    (setv (get lowlink node) (get counter 0))
    (setv (get counter 0) (+ (get counter 0) 1))
    (.append stack node)
    (.add on-stack node)
    (for [succ (.get graph node [])]
      (cond
        (not (in succ index))
          (do
            (strongconnect succ)
            (setv (get lowlink node) (min (get lowlink node) (get lowlink succ))))
        (in succ on-stack)
          (setv (get lowlink node) (min (get lowlink node) (get index succ)))))
    (when (= (get lowlink node) (get index node))
      (setv component [])
      (while True
        (setv w (.pop stack))
        (.discard on-stack w)
        (.append component w)
        (when (= w node) (break)))
      (.append result component)))
  (for [node (sorted (.keys graph))]
    (when (not (in node index))
      (strongconnect node)))
  result)

(defn cycles [[report None] [start None]]
  "Brick dependency cycles: each a sorted list of bricks in a >1-node SCC."
  (when (is report None)
    (setv report (dependency-report start)))
  (setv out [])
  (for [scc (strongly-connected-components (brick-graph report))]
    (when (> (len scc) 1)
      (.append out (sorted scc))))
  (sorted out))

(defn dangling-refs [[start None]]
  "Intra-namespace imports that resolve to no known brick; returns [{brick, module} ...]."
  (setv data (workspace.info start))
  (setv namespace (get data "namespace"))
  (setv cfg (config_core.load-config (get data "root")))
  (setv adapter (config_core.adapter cfg))
  (setv bricks (+ (get data "bases") (get data "components")))
  (setv prefix (+ namespace "."))
  (setv out [])
  (for [b bricks]
    (setv flagged (set))
    (for [module (brick-modules b adapter)]
      (when (or (= module namespace) (.startswith module prefix))
        (setv [kind name] (classify module bricks namespace))
        (when (!= kind "brick")
          (.add flagged module))))
    (for [module (sorted flagged)]
      (.append out {"brick" (get b "name") "module" module})))
  out)
