(import os json tempfile contextlib io)
(import pathlib [Path])
(import hy)
(import thyforce.polhy.bricks :as bricks)
(import thyforce.polhy.check :as check)
(import thyforce.polhy.cli.core :as cli)
(import thyforce.polhy.config :as config)
(import thyforce.polhy.deps :as deps)
(import thyforce.polhy.forms :as forms)
(import thyforce.polhy.testing :as testing)
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
             "test-path" "{test-root}/{namespace}/{name}"}
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
  (assert (= actual expected) f"Expected {expected !r}, got {actual !r}"))

(defn assert-in [item coll]
  (assert (in item coll) f"Expected {item !r} in {coll !r}"))

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
    (assert (.exists (/ root "tests" "acme" "polhy" "config" "test_core.hy")))
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
    (bricks.create-brick root cfg "components" "demo")
    (.write_text (/ root "components" "acme" "demo" "core.hy")
                 "(import acme.polhy.config.core)\n(import hy)\n(import os)\n" :encoding "utf-8")
    (assert= (forms.module-refs "(import os json)\n(require hyrule [->])\n")
             [{"kind" "import" "module" "os"} {"kind" "import" "module" "json"} {"kind" "require" "module" "hyrule"}])
    (setv report (deps.dependency-report root))
    (assert= (get report "polhy/config") {"bricks" [] "libs" []})
    (assert= (get report "demo") {"bricks" ["polhy/config"] "libs" ["hy"]})
    (assert (get (check.run root) "ok"))
    (assert (get (sync.run root) "ok"))
    (setv old-cwd (os.getcwd))
    (try
      (os.chdir root)
      (setv out (io.StringIO))
      (with [ctx (contextlib.redirect_stdout out)]
        (cli.main ["info"]))
      (assert= (get (json.loads (.getvalue out)) "namespace") "acme")
      (finally (os.chdir old-cwd)))
    (finally (.cleanup td))))

(defn test-forms-module-refs-handles-clause-modifiers []
  ;; :as alias must NOT be read as a module; members/star/dotted/selectors skipped
  (assert= (forms.module-refs "(import a :as b)") [{"kind" "import" "module" "a"}])
  (assert= (forms.module-refs "(import a.b.c [x :as y] z)")
           [{"kind" "import" "module" "a.b.c"} {"kind" "import" "module" "z"}])
  (assert= (forms.module-refs "(require m :macros [mac] :readers [r])")
           [{"kind" "require" "module" "m"}])
  (assert= (forms.module-refs "(import pkg *)") [{"kind" "import" "module" "pkg"}])
  ;; nested inside other forms is still found
  (assert= (forms.module-refs "(eval-and-compile (import deep))")
           [{"kind" "import" "module" "deep"}])
  ;; malformed source is tolerated
  (assert= (forms.module-refs "(import ") []))

(defn test-testing-discovers-and-aggregates []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (setv tdir (/ root "tests" "acme" "demo"))
    (.mkdir tdir :parents True)
    (.write_text (/ tdir "test_pass.hy")
                 "(defn run-tests [] (print \"1 passed\"))\n(when (= __name__ \"__main__\") (run-tests))\n"
                 :encoding "utf-8")
    (.write_text (/ tdir "test_fail.hy")
                 "(defn run-tests [] (raise (AssertionError \"boom\")))\n(when (= __name__ \"__main__\") (run-tests))\n"
                 :encoding "utf-8")
    (assert= (len (testing.discover root cfg)) 2)
    ;; execute via the repo's real venv Python (has hy); discovery is from the temp root
    (setv python (testing.venv-python (config.workspace-root (Path (os.getcwd)))))
    (setv result (testing.run :start root :python python))
    (assert= (get result "ok") False)
    (assert= (get result "passed") 1)
    (assert= (get result "failed") 1)
    (assert= (get result "total") 2)
    (finally (.cleanup td))))

(defn test-project-machinery-closure-generate-and-drift []
  (setv [td root] (make-workspace))
  (try
    (setv cfg (config.load-config root))
    (bricks.create-brick root cfg "components" "core/util")
    (bricks.create-brick root cfg "bases" "app/cli")
    (.write_text (/ root "bases" "acme" "app" "cli" "core.hy")
                 "(import acme.core.util.core)\n(import hy)\n" :encoding "utf-8")
    (setv result (projects.create-project root "bundle"
                   :bricks ["app/cli"] :scripts {"bundle" "acme.app.cli.runner:main"}))
    (assert (.exists (/ root "projects" "bundle" "project.cfg.hy")))
    (setv pp (/ root "projects" "bundle" "pyproject.toml"))
    (assert (.exists pp))
    ;; transitive closure follows the brick dependency
    (assert= (projects.closure ["app/cli"] (deps.dependency-report root)) #{"app/cli" "core/util"})
    ;; generated pyproject ships both bricks, the lib, and the script
    (setv text (.read_text pp :encoding "utf-8"))
    (assert-in "\"../../bases/acme/app/cli\" = \"acme/app/cli\"" text)
    (assert-in "\"../../components/acme/core/util\" = \"acme/core/util\"" text)
    (assert-in "\"hy\"" text)
    (assert-in "bundle = \"acme.app.cli.runner:main\"" text)
    ;; create runs sync, so there is no drift
    (assert (get (check.run root) "ok"))
    ;; editing the generated pyproject is detected as drift
    (.write_text pp (+ text "# drift\n") :encoding "utf-8")
    (setv checked (check.run root))
    (assert (not (get checked "ok")))
    (assert-in "pyproject-drift" (lfor issue (get checked "projects") (get issue "code")))
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
        (print f"FAIL {name}: {e !r}"))))
  (when failures
    (raise (AssertionError f"{(len failures)} test(s) failed")))
  (print f"{(len tests)} Hy tests passed"))

(when (= __name__ "__main__")
  (run-tests))
