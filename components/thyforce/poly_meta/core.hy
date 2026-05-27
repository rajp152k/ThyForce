(import thyforce.poly-meta.workspace :as workspace)
(import thyforce.poly-meta.bricks :as bricks)
(import thyforce.poly-meta.deps :as deps)
(import thyforce.poly-meta.check :as check)
(import thyforce.poly-meta.sync :as sync)
(import thyforce.poly-meta.projects :as projects)
(import thyforce.poly-meta.config :as config)

(defn info [[start None]]
  (workspace.info start))

(defn dependency-report [[start None]]
  (deps.dependency-report start))

(defn check-workspace [[start None]]
  (check.run start))

(defn sync-workspace [[start None]]
  (sync.run start))

(defn workspace-root [[start None]]
  (config.workspace-root start))

(defn load-config [root]
  (config.load-config root))

(defn get-in [data path [default None]]
  (config.get-in data path default))

(defn create-brick [root cfg kind name [language None] [overwrite False]]
  (bricks.create-brick root cfg kind name language overwrite))
