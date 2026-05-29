(import argparse json)
(import thyforce.polhy.core :as engine)

(defn print-json [data]
  (print (json.dumps data :indent 2 :default str)))

(defn create-parser []
  (setv parser (argparse.ArgumentParser :prog "polhy"))
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
    (= command "info") (print-json (engine.info))
    (= command "deps") (print-json (engine.dependency-report))
    (= command "check") (print-json (engine.check-workspace))
    (= command "sync") (print-json (engine.sync-workspace))
    (= command "create")
      (do
        (setv root (engine.workspace-root))
        (setv cfg (engine.load-config root))
        (setv kind (if (= args.kind "base")
                       (engine.get-in cfg ["paths" "bases"] "bases")
                       (engine.get-in cfg ["paths" "components"] "components")))
        (print-json (engine.create-brick root cfg kind args.name)))))
