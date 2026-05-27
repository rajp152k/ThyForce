(import pathlib [Path])
(import thyforce.poly_meta_config.core :as config_core)

(defn project-data [root config name]
  {"name" name
   "root" (str (/ root (config_core.get-in config ["paths" "projects"] "projects") name))
   "namespace" (get config "namespace")})
