(import thyforce.polhy.workspace :as workspace)
(import thyforce.polhy.bricks :as bricks)
(import thyforce.polhy.deps :as deps)
(import thyforce.polhy.check :as check)
(import thyforce.polhy.sync :as sync)
(import thyforce.polhy.projects :as projects)
(import thyforce.polhy.config :as config)

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
