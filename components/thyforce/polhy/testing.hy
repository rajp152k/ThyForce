"Test discovery + aggregation runner.

Discovers `test_*<test-ext>` files under the configured test root and runs them
through the workspace's own virtualenv Python (NOT the `hy` launcher, so
`sys.executable` is a real Python and libraries that subprocess it — e.g.
typeshed stub lookup — work). Each test file follows the repo convention of a
`run-tests` function guarded by `(when (= __name__ \"__main__\") (run-tests))`;
the driver executes that entrypoint per file, captures pass/fail, and aggregates.
"

(import os subprocess json tempfile)
(import pathlib [Path])
(import thyforce.polhy.config :as config_core)

(defn discover [root config]
  "Return sorted test files (str paths) under the configured test root."
  (setv adapter (config_core.adapter config))
  (setv test-ext (.get adapter "test-ext" ".hy"))
  (setv test-root (/ (Path root) (config_core.get-in config ["paths" "test-root"] "tests")))
  (if (.exists test-root)
      (sorted (lfor p (.rglob test-root (+ "test_*" test-ext)) (str p)))
      []))

(defn venv-python [root]
  "Path to the workspace virtualenv's Python interpreter, or None."
  (for [rel [[".venv" "bin" "python"] [".venv" "Scripts" "python.exe"]]]
    (setv candidate (/ (Path root) #* rel))
    (when (.exists candidate)
      (return (str candidate))))
  None)

(defn _pythonpath [root config existing]
  (setv comps (str (/ (Path root) (config_core.get-in config ["paths" "components"] "components"))))
  (setv bases (str (/ (Path root) (config_core.get-in config ["paths" "bases"] "bases"))))
  (setv parts [bases comps])
  (when existing
    (.append parts existing))
  (.join os.pathsep parts))

(defn _driver-source []
  "Python driver: run each argv test file under __main__ and report JSON."
  (.join "\n"
    ["import sys, json, io, contextlib, runpy"
     "import hy  # install the Hy import hook"
     "results = []"
     "for path in sys.argv[1:]:"
     "    buf = io.StringIO()"
     "    ok, err = True, None"
     "    try:"
     "        with contextlib.redirect_stdout(buf):"
     "            runpy.run_path(path, run_name='__main__')"
     "    except BaseException as exc:"
     "        ok, err = False, repr(exc)"
     "    lines = [ln for ln in buf.getvalue().splitlines() if ln.strip()]"
     "    results.append({'file': path, 'ok': ok, 'error': err,"
     "                    'summary': lines[-1] if lines else ''})"
     "print(json.dumps(results))"
     "sys.exit(0 if all(r['ok'] for r in results) else 1)"]))

(defn _write-driver []
  (setv handle (tempfile.NamedTemporaryFile :suffix ".py" :delete False :mode "w"))
  (.write handle (_driver-source))
  (.close handle)
  handle.name)

(defn _parse-results [stdout]
  (try
    (json.loads stdout)
    (except [Exception]
      [])))

(defn run [[start None] [test-files None] [python None]]
  "Discover (or take) test files and run them through the workspace venv Python.

Returns {ok, passed, failed, total, results}. Each result is
{file, ok, error, summary}.
  "
  (setv root (config_core.workspace-root start))
  (setv config (config_core.load-config root))
  (setv files (if (is test-files None) (discover root config) test-files))
  (setv interpreter (or python (venv-python root)))
  (when (is interpreter None)
    (return {"ok" False "passed" 0 "failed" 0 "total" (len files) "results" []
             "error" "no workspace virtualenv found (run `uv sync` first)"}))
  (when (not files)
    (return {"ok" True "passed" 0 "failed" 0 "total" 0 "results" []}))
  (setv env (dict os.environ))
  (setv (get env "PYTHONPATH") (_pythonpath root config (.get env "PYTHONPATH")))
  (setv driver (_write-driver))
  (try
    (setv proc (subprocess.run [interpreter driver #* files]
                               :cwd (str root) :env env
                               :capture-output True :text True))
    (finally
      (os.unlink driver)))
  (setv results (_parse-results proc.stdout))
  (setv passed (sum (gfor r results (if (get r "ok") 1 0))))
  (setv failed (sum (gfor r results (if (get r "ok") 0 1))))
  {"ok" (= proc.returncode 0)
   "passed" passed
   "failed" failed
   "total" (len files)
   "results" results})
