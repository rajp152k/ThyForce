(import argparse json)
(import thyforce.poly_meta_config.core :as config_core)
(import thyforce.poly_meta_workspace.core :as workspace)
(import thyforce.poly_meta_bricks.core :as bricks)
(import thyforce.poly_meta_deps.core :as deps)
(import thyforce.poly_meta_check.core :as check)
(import thyforce.poly_meta_sync.core :as sync)

(defn print-json [data]
  (print (json.dumps data :indent 2 :default str)))

(defn create-parser []
  (setv parser (argparse.ArgumentParser :prog "poly-meta"))
  (setv sub (.add_subparsers parser :dest "command" :required True))
  (.add_parser sub "info")
  (.add_parser sub "deps")
  (.add_parser sub "check")
  (.add_parser sub "sync")
  (setv create (.add_parser sub "create"))
  (setv create-sub (.add_subparsers create :dest "kind" :required True))
  (for [kind ["component" "base"]]
    (setv p (.add_parser create-sub kind))
    (.add_argument p "name"))
  parser)

(defn main [[argv None]]
  (setv args (.parse_args (create-parser) argv))
  (setv command args.command)
  (cond
    (= command "info") (print-json (workspace.info))
    (= command "deps") (print-json (deps.dependency-report))
    (= command "check") (print-json (check.run))
    (= command "sync") (print-json (sync.run))
    (= command "create")
      (do
        (setv root (config_core.workspace-root))
        (setv cfg (config_core.load-config root))
        (setv kind (if (= args.kind "base")
                       (config_core.get-in cfg ["paths" "bases"] "bases")
                       (config_core.get-in cfg ["paths" "components"] "components")))
        (print-json (bricks.create-brick root cfg kind args.name)))))
