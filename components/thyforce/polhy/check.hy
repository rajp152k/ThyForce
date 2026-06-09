"Aggregate workspace integrity: structure, deps, and project checks."

(import thyforce.polhy.config :as config_core)
(import thyforce.polhy.workspace :as workspace)
(import thyforce.polhy.bricks :as bricks)
(import thyforce.polhy.deps :as deps)
(import thyforce.polhy.projects :as projects)

(defn run [[start None]]
  (setv root (config_core.workspace-root start))
  (setv cfg (config_core.load-config root))
  (setv info (workspace.info root))
  (setv errors [])
  (when (not (get info "namespace"))
    (.append errors "Missing namespace"))
  (setv brick-issues (bricks.brick-structure-issues root cfg))
  (setv report (deps.dependency-report root))
  (setv dep-issues [])
  (for [d (deps.dangling-refs root)]
    (.append dep-issues {"code" "missing-brick-dep" "brick" (get d "brick") "module" (get d "module")}))
  (for [cyc (deps.cycles :report report)]
    (.append dep-issues {"code" "dependency-cycle" "bricks" cyc}))
  (setv project-issues (projects.check-projects root))
  {"ok" (and (= (len errors) 0) (= (len brick-issues) 0)
             (= (len dep-issues) 0) (= (len project-issues) 0))
   "errors" errors
   "bricks" brick-issues
   "deps" dep-issues
   "projects" project-issues
   "workspace" info})
