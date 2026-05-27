(import pathlib [Path])
(import thyforce.poly-meta.config :as config_core)
(import thyforce.poly-meta.bricks :as bricks)

(defn load-workspace [[start None]]
  (setv root (config_core.workspace-root start))
  {"root" root "config" (config_core.load-config root)})

(defn info [[start None]]
  (setv ws (load-workspace start))
  (setv root (get ws "root"))
  (setv cfg (get ws "config"))
  (setv bases-key (config_core.get-in cfg ["paths" "bases"] "bases"))
  (setv components-key (config_core.get-in cfg ["paths" "components"] "components"))
  {"root" (str root)
   "namespace" (get cfg "namespace")
   "bases" (bricks.list-bricks root cfg bases-key)
   "components" (bricks.list-bricks root cfg components-key)})
