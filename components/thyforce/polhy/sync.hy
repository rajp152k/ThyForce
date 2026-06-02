"Regenerate each project's pyproject.toml from its project.cfg.hy."

(import thyforce.polhy.config :as config_core)
(import thyforce.polhy.projects :as projects)

(defn run [[start None]]
  (projects.sync-projects (config_core.workspace-root start)))
