"Workspace integrity check: namespace presence + project definition / drift."

(import thyforce.polhy.config :as config_core)
(import thyforce.polhy.workspace :as workspace)
(import thyforce.polhy.projects :as projects)

(defn run [[start None]]
  (setv root (config_core.workspace-root start))
  (setv info (workspace.info root))
  (setv errors [])
  (when (not (get info "namespace"))
    (.append errors "Missing namespace"))
  (setv project-issues (projects.check-projects root))
  {"ok" (and (= (len errors) 0) (= (len project-issues) 0))
   "errors" errors
   "projects" project-issues
   "workspace" info})
