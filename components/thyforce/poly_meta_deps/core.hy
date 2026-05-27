(import re)
(import pathlib [Path])
(import thyforce.poly_meta_config.core :as config_core)
(import thyforce.poly_meta_workspace.core :as workspace)

(defn source-files [path adapter]
  (setv ext (.get adapter "source-ext" ".hy"))
  (list (.rglob (Path path) f"*{ext}")))

(defn hy-imports [text]
  (setv pattern "\\((?:import|require)\\s+([^\\)\\[]+)")
  (list (map (fn [m] (.strip (.group m 1))) (re.finditer pattern text))))

(defn imports-for-brick [brick config]
  (setv adapter (config_core.adapter config))
  (setv result [])
  (for [file (source-files (get brick "path") adapter)]
    (setv text (.read_text file :encoding "utf-8" :errors "ignore"))
    (for [imp (hy-imports text)] (.append result imp)))
  result)

(defn dependency-report [[start None]]
  (setv data (workspace.info start))
  (setv config (config_core.load-config (get data "root")))
  (setv bricks (+ (get data "bases") (get data "components")))
  (dict (map (fn [b] [(get b "name") (imports-for-brick b config)]) bricks)))
