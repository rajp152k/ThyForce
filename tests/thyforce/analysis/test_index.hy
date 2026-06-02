(import hy)
(import tempfile)
(import pathlib [Path])
(import thyforce.analysis.index :as index)
(import thyforce.analysis.uri :as uri)

;; Stdlib-source tests (resolving math.pyi/json source via typeshed) are omitted:
;; typeshed_client.get_stub_file shells out to `[sys.executable, "-c", ...]`, and
;; under the `hy` test launcher sys.executable is `hy`, so the subprocess fails.
;; Those paths work under the production Python entrypoint. See AGENTS/hy-isms.md.

(setv URI "file:///workspace/main.hy")

(defn assert= [actual expected]
  (assert (= actual expected) f"Expected {expected !r}, got {actual !r}"))
(defn assert-true [value]
  (assert value f"Expected truthy, got {value !r}"))
(defn assert-false [value]
  (assert (not value) f"Expected falsy, got {value !r}"))

(defn build [source]
  (setv idx (index.WorkspaceIndex))
  (.update-document idx URI source)
  idx)

(defn names [idx prefix]
  (set (gfor symbol (.symbols-for-completion idx URI prefix) (get symbol "name"))))

(defn start-of [symbol]
  (get (get (get symbol "source") "range") "start"))

(defn temp-root []
  (setv root (Path (tempfile.mkdtemp)))
  (.write-text (/ root "pyproject.toml") "[project]\nname = \"x\"\n")
  root)

;; ---------------------------------------------------------------------------

(defn test-core-form-completion-and-docs []
  (setv idx (build "(if True 1 2)\n"))
  (assert-true (in "lfor" (names idx "lf")))
  (assert-true (in "if" (names idx "if")))
  (assert-true (in "setv" (names idx "set")))
  (setv info (.resolve idx URI "lfor"))
  (assert-true (is-not info None))
  (assert-true (in "List comprehension" (get info "documentation")))
  (assert= (get info "signature") "(lfor clauses value)"))

(defn test-python-builtin-docs []
  (setv idx (build "(print \"hi\")\n"))
  (assert-true (in "print" (names idx "pr")))
  (setv info (.resolve idx URI "print"))
  (assert-true (is-not info None))
  (assert= (get info "kind") "python-builtin")
  (assert-true (in "Prints the values" (get info "documentation"))))

(defn test-local-reader-macro-definition []
  (setv idx (build "(defreader bang []\n  \"Bang docs\"\n  1)\n"))
  (assert-true (in "#bang" (names idx "#ba")))
  (setv info (.resolve idx URI "#bang"))
  (assert= (get info "kind") "reader-macro")
  (assert= (get info "signature") "(defreader bang [])")
  (assert= (get info "documentation") "Bang docs")
  (assert= (get (start-of info) "line") 0))

(defn test-local-definition-docs-and-range []
  (setv idx (build "(defn foo [x]\n  \"Foo docs\"\n  (+ x 1))\n(setv bar 2)\n"))
  (assert-true (in "foo" (names idx "fo")))
  (assert-true (in "bar" (names idx "ba")))
  (setv foo (.resolve idx URI "foo"))
  (assert= (get foo "signature") "(foo [x])")
  (assert= (get foo "documentation") "Foo docs")
  (assert= (get (start-of foo) "line") 0)
  (assert= (get (start-of foo) "character") 6))

(defn test-assignment-destructuring-and-setx []
  (setv idx (build "(setv [a b] pair)\n(setv (, c d) other)\n(setv {\"x\" e :y f} data)\n(setx g 1)\n(setv (. obj attr) 2)\n"))
  (for [name ["a" "b" "c" "d" "e" "f" "g"]]
    (setv symbol (.resolve idx URI name))
    (assert-true (is-not symbol None))
    (assert= (get symbol "kind") "local-variable"))
  (assert-false (in "attr" (. (get idx.documents URI) symbols)))
  (assert-true (in "g" (names idx "g"))))

(defn test-parameter-resolution-is-position-scoped []
  (setv source "(defn foo [print [y 1] #* rest]\n  (print y rest))\n(print \"outside\")\n")
  (setv idx (build source))
  (setv scoped-print (.resolve idx URI "print" 1 4))
  (assert= (get scoped-print "kind") "parameter")
  (assert= (get scoped-print "detail") "parameter of foo")
  (assert= (get (start-of scoped-print) "line") 0)
  (assert= (get (.resolve idx URI "y" 1 10) "kind") "parameter")
  (assert= (get (.resolve idx URI "rest" 1 17) "kind") "parameter")
  (assert= (get (.resolve idx URI "print" 2 2) "kind") "python-builtin")
  (setv comps (set (gfor s (.symbols-for-completion idx URI "y" 1 10) (get s "name"))))
  (assert-true (in "y" comps))
  (assert-false (in "y" (names idx "y"))))

(defn test-parse-diagnostic []
  (setv document (.update-document (index.WorkspaceIndex) URI "(if True 1"))
  (assert-true document.diagnostics)
  (setv d (get document.diagnostics 0))
  (assert= (get d "code") "hy-reader")
  (assert= (get d "line") 0))

(defn test-reader-recovery-indexes-forms-before-error []
  (setv idx (index.WorkspaceIndex))
  (setv document (.update-document idx URI "(defn before-error []\n  \"Before docs\"\n  1)\n(if True 1"))
  (assert-true document.diagnostics)
  (setv before (.resolve idx URI "before-error"))
  (assert-true (is-not before None))
  (assert= (get before "documentation") "Before docs")
  (assert-true (in "before-error" (names idx "before"))))

(defn test-compile-diagnostic []
  (setv document (.update-document (index.WorkspaceIndex) URI "(if True 1)\n"))
  (assert-true document.diagnostics)
  (setv d (get document.diagnostics 0))
  (assert= (get d "code") "hy-compiler")
  (assert-true (> (get d "end-character") (get d "character"))))

(defn test-require-records-alias-star-selected-and-readers []
  (setv root (temp-root))
  (.write-text (/ root "macros.hy")
    "(defmacro zap []\n  \"Zap docs\"\n  1)\n(defmacro zip []\n  \"Zip docs\"\n  1)\n(defreader bang []\n  \"Bang docs\"\n  1)\n")
  (setv u (uri.from-fs-path (str (/ root "main.hy"))))
  (setv idx (index.WorkspaceIndex))
  (.update-document idx u
    "(require macros :as M)\n(require macros [zap :as zap-alias])\n(require macros *)\n(require macros :readers [bang])\n")
  (assert= (get (.resolve idx u "M.zap") "documentation") "Zap docs")
  (assert= (get (.resolve idx u "zap-alias") "documentation") "Zap docs")
  (assert= (get (.resolve idx u "zip") "documentation") "Zip docs")
  (setv reader (.resolve idx u "#bang"))
  (assert= (get reader "kind") "reader-macro")
  (assert-true (in "reader macro" (get reader "detail"))))

(defn test-project-wide-hy-definition []
  (setv root (temp-root))
  (.write-text (/ root "lib.hy") "(defn helper []\n  \"Helper docs\"\n  1)\n")
  (setv u (uri.from-fs-path (str (/ root "main.hy"))))
  (setv idx (index.WorkspaceIndex))
  (.update-document idx u "(helper)\n")
  (setv helper (.resolve idx u "helper"))
  (assert-true (is-not helper None))
  (assert= (get helper "documentation") "Helper docs")
  (assert-true (.endswith (get (get helper "source") "uri") "lib.hy")))

(defn test-imported-hy-member-resolution-is-module-aware []
  (setv root (temp-root))
  (.write-text (/ root "alpha.hy") "(defn helper []\n  \"Alpha docs\"\n  1)\n")
  (.write-text (/ root "beta.hy")
    "(defn helper []\n  \"Beta docs\"\n  2)\n(raise (Exception \"do not import beta at indexing time\"))\n")
  (setv u (uri.from-fs-path (str (/ root "main.hy"))))
  (setv idx (index.WorkspaceIndex))
  (.update-document idx u "(import beta [helper])\n(helper)\n")
  (setv helper (.resolve idx u "helper"))
  (assert-true (is-not helper None))
  (assert= (get helper "documentation") "Beta docs")
  (assert-true (.endswith (get (get helper "source") "uri") "beta.hy")))

(defn test-hy-module-alias-dotted-resolution-and-completion []
  (setv root (temp-root))
  (.write-text (/ root "lib.hy") "(defn helper []\n  \"Alias docs\"\n  1)\n")
  (setv u (uri.from-fs-path (str (/ root "main.hy"))))
  (setv idx (index.WorkspaceIndex))
  (.update-document idx u "(import lib :as L)\n(L.helper)\n")
  (setv helper (.resolve idx u "L.helper"))
  (assert-true (is-not helper None))
  (assert= (get helper "name") "L.helper")
  (assert= (get helper "documentation") "Alias docs")
  (assert-true (in "L.helper" (set (gfor s (.symbols-for-completion idx u "L.he") (get s "name"))))))

;; ---------------------------------------------------------------------------

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
  (print f"{(len tests)} Hy index tests passed"))

(when (= __name__ "__main__")
  (run-tests))
