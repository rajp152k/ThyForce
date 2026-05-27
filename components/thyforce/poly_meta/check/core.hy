(import thyforce.poly-meta.workspace.core :as workspace)

(defn run [[start None]]
  (setv info (workspace.info start))
  (setv errors [])
  (when (not (get info "namespace"))
    (.append errors "Missing namespace"))
  {"ok" (= (len errors) 0) "errors" errors "workspace" info})
