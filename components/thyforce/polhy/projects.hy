"Project machinery: data-first project definitions -> generated pyproject.toml.

A project is declared in `projects/<name>/project.cfg.hy` as a `PROJECT` map of
entry bricks + metadata. polhy computes the transitive brick *closure* (via the
form-based dependency report) and the *library* set (third-party deps the closure
actually imports, version-pinned from the root development project), then
generates a `pyproject.toml` with the right `force-include` mappings and
dependencies. Bases stay bases; a project *includes* bricks, it does not own code.
"

(import re tomllib)
(import pathlib [Path])
(import thyforce.polhy.config :as config_core)
(import thyforce.polhy.deps :as deps)
(import thyforce.polhy.workspace :as workspace)
(import thyforce.spec.core :as spec)

(setv PROJECT-FILE "project.cfg.hy")

(setv project?
  (spec.and-spec
    (spec.key-pred "name" spec.str?)
    (spec.key-pred "version" spec.str?)
    (spec.key-pred "bricks" (spec.list-of spec.str?))))

;; ---------------------------------------------------------------------------
;; discovery / loading
;; ---------------------------------------------------------------------------

(defn projects-dir [root config]
  (/ (Path root) (config_core.get-in config ["paths" "projects"] "projects")))

(defn list-projects [root config]
  "Project dirs under projects/ that carry a project.cfg.hy."
  (setv pdir (projects-dir root config))
  (setv out [])
  (when (.exists pdir)
    (for [child (sorted (.iterdir pdir))]
      (when (and (.is-dir child) (.exists (/ child PROJECT-FILE)))
        (.append out {"name" child.name "root" (str child)}))))
  out)

(defn load-project-def [project]
  (config_core.load-data (/ (Path (get project "root")) PROJECT-FILE) "PROJECT"))

;; ---------------------------------------------------------------------------
;; closure + libraries
;; ---------------------------------------------------------------------------

(defn closure [entry-bricks deps-report]
  "Transitive set of bricks reachable from ENTRY-BRICKS via brick dependencies."
  (setv seen (set))
  (setv stack (list entry-bricks))
  (while stack
    (setv brick (.pop stack))
    (when (not (in brick seen))
      (.add seen brick)
      (for [dep (get (.get deps-report brick {"bricks" []}) "bricks")]
        (when (not (in dep seen))
          (.append stack dep)))))
  seen)

(defn _dep-name [dep]
  (setv match (re.match r"[A-Za-z0-9._-]+" dep))
  (if match (.group match 0) dep))

(defn lib-pins [root]
  "Map third-party lib name -> full requirement string, from the root dev project."
  (setv pyproject (/ (Path root) "pyproject.toml"))
  (setv pins {})
  (when (.exists pyproject)
    (try
      (setv data (tomllib.loads (.read-text pyproject :encoding "utf-8")))
      (for [dep (config_core.get-in data ["project" "dependencies"] [])]
        (setv (get pins (_dep-name dep)) dep))
      (except [Exception] None)))
  pins)

(defn project-libs [closure-set deps-report pins]
  "Pinned requirement strings for the libs the closure imports (always incl. hy)."
  (setv libs (set ["hy"]))
  (for [brick closure-set]
    (.update libs (get (.get deps-report brick {"libs" []}) "libs")))
  (lfor lib (sorted libs) (.get pins lib lib)))

;; ---------------------------------------------------------------------------
;; force-include computation
;; ---------------------------------------------------------------------------

(defn _brick-kind-dir [info brick-name]
  (if (any (gfor b (get info "bases") (= (get b "name") brick-name))) "bases" "components"))

(defn _ancestor-init [root ns prefix]
  "[(../../<kind>/ns/prefix/__init__.py) (ns/prefix/__init__.py)] or None."
  (setv comp (.format "components/{}/{}/__init__.py" ns prefix))
  (setv base (.format "bases/{}/{}/__init__.py" ns prefix))
  (cond
    (.exists (/ (Path root) comp)) [(+ "../../" comp) (.format "{}/{}/__init__.py" ns prefix)]
    (.exists (/ (Path root) base)) [(+ "../../" base) (.format "{}/{}/__init__.py" ns prefix)]
    True None))

(defn force-includes [root info closure-set]
  "Ordered [src dest] force-include pairs (paths relative to the project dir)."
  (setv ns (get info "namespace"))
  (setv pairs [])
  (setv seen (set))
  (defn add [src dest]
    (when (not (in dest seen))
      (.add seen dest)
      (.append pairs [src dest])))
  (add (.format "../../components/{}/__init__.py" ns) (.format "{}/__init__.py" ns))
  (for [brick (sorted closure-set)]
    (setv parts (.split brick "/"))
    ;; ancestor package __init__.py for grouping domains (skip domain-as-brick)
    (for [i (range 1 (len parts))]
      (setv prefix (.join "/" (cut parts 0 i)))
      (when (not (in prefix closure-set))
        (setv ancestor (_ancestor-init root ns prefix))
        (when (is-not ancestor None)
          (add (get ancestor 0) (get ancestor 1)))))
    (setv kind (_brick-kind-dir info brick))
    (add (.format "../../{}/{}/{}" kind ns brick) (.format "{}/{}" ns brick)))
  pairs)

;; ---------------------------------------------------------------------------
;; pyproject.toml generation
;; ---------------------------------------------------------------------------

(defn _q [value] (+ "\"" value "\""))

(defn generate-pyproject [project-def root info deps-report pins]
  "Render the pyproject.toml text for a project definition."
  (setv closure-set (closure (get project-def "bricks") deps-report))
  (setv libs (project-libs closure-set deps-report pins))
  (setv includes (force-includes root info closure-set))
  (setv scripts (.get project-def "scripts" {}))
  (setv description (.get project-def "description" ""))
  (setv lines [])
  (.append lines "[project]")
  (.append lines (+ "name = " (_q (get project-def "name"))))
  (.append lines (+ "version = " (_q (get project-def "version"))))
  (when description
    (.append lines (+ "description = " (_q description))))
  (.append lines (+ "requires-python = " (_q (.get project-def "python" ">=3.14"))))
  (.append lines "dependencies = [")
  (for [lib libs]
    (.append lines (+ "    " (_q lib) ",")))
  (.append lines "]")
  (.append lines "")
  (when scripts
    (.append lines "[project.scripts]")
    (for [[script target] (.items scripts)]
      (.append lines (+ script " = " (_q target))))
    (.append lines ""))
  (.append lines "[build-system]")
  (.append lines (+ "requires = [" (_q "hatchling") "]"))
  (.append lines (+ "build-backend = " (_q "hatchling.build")))
  (.append lines "")
  (.append lines "[tool.hatch.build.targets.wheel.force-include]")
  (for [[src dest] includes]
    (.append lines (+ (_q src) " = " (_q dest))))
  (+ (.join "\n" lines) "\n"))

;; ---------------------------------------------------------------------------
;; sync + check + create
;; ---------------------------------------------------------------------------

(defn _context [root]
  (setv config (config_core.load-config root))
  {"config" config
   "info" (workspace.info root)
   "deps" (deps.dependency-report root)
   "pins" (lib-pins root)})

(defn sync-projects [root]
  "Regenerate every project's pyproject.toml from its project.cfg.hy."
  (setv ctx (_context root))
  (setv results [])
  (for [project (list-projects root (get ctx "config"))]
    (setv pdef (load-project-def project))
    (setv text (generate-pyproject pdef root (get ctx "info") (get ctx "deps") (get ctx "pins")))
    (setv pyproject (/ (Path (get project "root")) "pyproject.toml"))
    (setv changed (or (not (.exists pyproject)) (!= (.read-text pyproject :encoding "utf-8") text)))
    (when changed
      (.write-text pyproject text :encoding "utf-8"))
    (.append results {"name" (get project "name") "changed" changed}))
  {"ok" True "projects" results})

(defn check-projects [root]
  "Validate project defs and detect pyproject drift; return issue maps."
  (setv ctx (_context root))
  (setv issues [])
  (for [project (list-projects root (get ctx "config"))]
    (setv name (get project "name"))
    (try
      (setv pdef (load-project-def project))
      (except [exc Exception]
        (.append issues {"project" name "code" "load-error" "message" (str exc)})
        (continue)))
    (setv validity (spec.validate project? pdef))
    (when (not (get validity "ok"))
      (.append issues {"project" name "code" "invalid-def" "problems" (get validity "problems")}))
    (setv text (generate-pyproject pdef root (get ctx "info") (get ctx "deps") (get ctx "pins")))
    (setv pyproject (/ (Path (get project "root")) "pyproject.toml"))
    (when (or (not (.exists pyproject)) (!= (.read-text pyproject :encoding "utf-8") text))
      (.append issues {"project" name "code" "pyproject-drift" "message" "run `polhy sync`"})))
  issues)

(defn create-project [root name [bricks None] [scripts None] [version "0.1.0"] [description ""]]
  "Scaffold projects/<name>/project.cfg.hy and generate its pyproject.toml."
  (setv config (config_core.load-config root))
  (setv project-root (/ (projects-dir root config) name))
  (.mkdir project-root :parents True :exist-ok True)
  (setv cfg-path (/ project-root PROJECT-FILE))
  (when (.exists cfg-path)
    (raise (FileExistsError (str cfg-path))))
  (.write-text cfg-path (_render-project-cfg name version description (or bricks []) (or scripts {})) :encoding "utf-8")
  (sync-projects root)
  {"name" name "root" (str project-root)})

(defn _render-project-cfg [name version description bricks scripts]
  (setv lines [])
  (.append lines "(setv PROJECT")
  (.append lines (+ "  {\"name\" " (_q name)))
  (.append lines (+ "   \"version\" " (_q version)))
  (.append lines (+ "   \"description\" " (_q description)))
  (.append lines (+ "   \"bricks\" [" (.join " " (lfor b bricks (_q b))) "]"))
  (.append lines (+ "   \"scripts\" {" (.join " " (lfor [k v] (.items scripts) (+ (_q k) " " (_q v)))) "}})"))
  (+ (.join "\n" lines) "\n"))
