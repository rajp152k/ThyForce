(import os json tempfile contextlib io)
(import pathlib [Path])
(import hy)
(import thyforce.polhy.bricks :as bricks)
(import thyforce.polhy.check :as check)
(import thyforce.polhy.cli.core :as cli)
(import thyforce.polhy.config :as config)
(import thyforce.polhy.deps :as deps)
(import thyforce.polhy.projects :as projects)
(import thyforce.polhy.sync :as sync)
(import thyforce.polhy.workspace :as workspace)

(setv workspace_config #[[
(setv CONFIG
  {"tool" "polhy-test"
   "namespace" "acme"
   "paths" {"bases" "bases" "components" "components" "projects" "projects" "test-root" "tests"}
   "layout" {"theme" "loose"
             "brick-path" "{kind}/{namespace}/{name}"
             "test-path" "{test-root}/{kind}/{namespace}/{name}"}
   "language" {"default" "hy"
               "adapters" {"hy" {"source-ext" ".hy"
                                    "test-ext" ".hy"
                                    "interface-file" "__init__.py"
                                    "module-file" "core.hy"
                                    "test-file" "test_core.hy"}}}
   "templates"
     {"hy"
       {"component-core" ";; component {name}\n(import os)\n"
        "base-core" ";; base {name}\n(require hyrule [->])\n"
        "interface" "import hy\nfrom {namespace}.{import-name} import core\n\n__all__ = [\"core\"]\n"
        "test" "import hy\nfrom {namespace}.{import-name} import core\n\n\ndef test_sample():\n    assert core is not None\n"}}})
]])

(defn make-workspace [[config-text workspace_config]]
  (setv td (tempfile.TemporaryDirectory))
  (setv root (Path td.name))
  (.write_text (/ root "workspace.cfg.hy") config-text :encoding "utf-8")
  [td root])

(defn assert= [actual expected]
  (assert (= actual expected) f"Expected {expected!r}, got {actual!r}"))

(defn assert-in [item coll]
  (assert (in item coll) f"Expected {item!r} in {coll!r}"))

(defn test-workspace-root-finds-nearest-cfg-hy []
  (setv [td root] (make-workspace))
  (try
    (setv nested (/ root "components" "acme" "demo"))
    (.mkdir nested :parents True)
    (assert= (config.workspace-root nested) root)
    (finally (.cleanup td))))

(defn test-workspace-root-prefers-current-directory-config []
  (setv [td root] (make-workspace))
  (try
    (setv child (/ root "child"))
    (.mkdir child)
    (.write_text (/ child "workspace.cfg.hy") (.replace workspace_config "\"acme\"" "\"childns\"") :encoding "utf-8")
    (assert= (config.workspace-root child) child)
    (assert= (get (config.load-config child) "namespace") "childns")
    (finally (.cleanup td))))

(defn test-load-config-get-in-adapter []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (assert= (get cfg "namespace") "acme")
    (assert= (config.get-in cfg ["language" "default"]) "hy")
    (assert= (config.get-in cfg ["missing"] "fallback") "fallback")
    (assert= (get (config.adapter cfg) "module-file") "core.hy")
    (finally (.cleanup td))))

(defn test-create-nested-component []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (setv result (bricks.create-brick root cfg "components" "polhy/config"))
    (setv brick-dir (/ root "components" "acme" "polhy" "config"))
    (assert= (get result "brick") "polhy/config")
    (assert= (Path (get result "path")) brick-dir)
    (assert= (.read_text (/ brick-dir "core.hy") :encoding "utf-8") ";; component polhy/config\n(import os)\n")
    (assert-in "from acme.polhy.config import core" (.read_text (/ brick-dir "__init__.py") :encoding "utf-8"))
    (assert (.exists (/ root "tests" "components" "acme" "polhy" "config" "test_core.hy")))
    (finally (.cleanup td))))

(defn test-create-nested-base []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (bricks.create-brick root cfg "bases" "polhy/cli")
    (assert= (.read_text (/ root "bases" "acme" "polhy" "cli" "core.hy") :encoding "utf-8") ";; base polhy/cli\n(require hyrule [->])\n")
    (finally (.cleanup td))))

(defn test-create-brick-overwrite []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (bricks.create-brick root cfg "components" "demo")
    (try
      (bricks.create-brick root cfg "components" "demo")
      (raise (AssertionError "Expected FileExistsError"))
      (except [e FileExistsError] None))
    (assert= (get (bricks.create-brick root cfg "components" "demo" :overwrite True) "brick") "demo")
    (finally (.cleanup td))))

(defn test-list-bricks-and-workspace-info []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (bricks.create-brick root cfg "components" "polhy/config")
    (bricks.create-brick root cfg "components" "plain")
    (bricks.create-brick root cfg "bases" "polhy/cli")
    (assert= (sorted (list (map (fn [b] (get b "name")) (bricks.list-bricks root cfg "components")))) ["plain" "polhy/config"])
    (setv info (workspace.info root))
    (assert= (get info "namespace") "acme")
    (assert= (list (map (fn [b] (get b "name")) (get info "bases"))) ["polhy/cli"])
    (finally (.cleanup td))))

(defn test-deps-check-sync-project-and-cli []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (bricks.create-brick root cfg "components" "polhy/config")
    (assert= (deps.hy-imports "(import os json)\n(require hyrule [->])\n") ["os json" "hyrule"])
    (assert= (get (deps.dependency-report root) "polhy/config") ["os"])
    (assert (get (check.run root) "ok"))
    (assert (get (sync.run root) "ok"))
    (assert= (Path (get (projects.project-data root cfg "service") "root")) (/ root "projects" "service"))
    (setv old-cwd (os.getcwd))
    (try
      (os.chdir root)
      (setv out (io.StringIO))
      (with [ctx (contextlib.redirect_stdout out)]
        (cli.main ["info"]))
      (assert= (get (json.loads (.getvalue out)) "namespace") "acme")
      (finally (os.chdir old-cwd)))
    (finally (.cleanup td))))

(defn run-tests []
  (setv tests (sorted (list (gfor item (globals) :if (.startswith item "test_") item))))
  (setv failures [])
  (for [name tests]
    (try
      ((get (globals) name))
      (print f"ok {name}")
      (except [e Exception]
        (.append failures [name e])
        (print f"FAIL {name}: {e!r}"))))
  (when failures
    (raise (AssertionError f"{(len failures)} test(s) failed")))
  (print f"{(len tests)} Hy tests passed"))

(when (= __name__ "__main__")
  (run-tests))
