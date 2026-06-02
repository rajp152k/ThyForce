"Python and Hy runtime resolution, scoped by workspace root.

Resolution temporarily prepends the project root and its local virtualenv
site-packages to sys.path while resolving, rather than mutating a process-global
search path permanently. The resolver is a stateful object: it owns caches and
search paths, which is a deliberate mutable-cache exception to the otherwise
data-first, immutable design.
"

(import ast)
(import importlib)
(import importlib.util)
(import inspect)
(import pkgutil)
(import sys)
(import contextlib)
(import pathlib [Path])
(import typeshed-client [get-stub-file])

(import thyforce.lsp.analyzer.model :as model)
(import thyforce.lsp.analyzer.uri :as uri)
(import thyforce.lsp.analyzer.config :as cfg)
(import thyforce.lsp.analyzer.python-static :as ps)

(setv _IGNORED-DIRS (set cfg.DEFAULT-EXCLUDE-DIRS))

(defn _python-qualified-name [name]
  (.join "." (gfor part (.split name ".") (if part (hy.mangle part) part))))

(defclass PythonResolver []
  "Resolve Python modules/objects for one workspace root."

  (defn __init__ [self root [config None]]
    (setv self.root root)
    (setv self.config (or config (cfg.config)))
    (setv self.search-paths (_search-paths root :include-root (get self.config "allow-workspace-imports")))
    (setv self.static-search-paths (_static-search-paths root))
    (setv self._module-cache {})
    (setv self._object-cache {})
    (setv self._static-module-cache {})
    (setv self._top-level-modules None))

  (defn [contextlib.contextmanager] import-context [self]
    (setv old-path (list sys.path))
    (setv prefixes (lfor path self.search-paths (str path)))
    (setv filtered (lfor p sys.path :if (not (in p prefixes)) p))
    (when (not (get self.config "allow-workspace-imports"))
      (setv root (str (.resolve self.root)))
      (setv filtered (lfor p filtered :if (not (in p #{"" root})) p)))
    (setv (cut sys.path) [#* prefixes #* filtered])
    (try
      (yield)
      (finally
        (setv (cut sys.path) old-path))))

  (defn import-module [self module-name]
    (setv python-module-name (_python-qualified-name module-name))
    (when (in python-module-name self._module-cache)
      (return (get self._module-cache python-module-name)))
    (try
      (importlib.invalidate-caches)
      (if (and (not (get self.config "allow-workspace-imports"))
               (self._is-workspace-module python-module-name))
          (setv module None)
          (with [(self.import-context)]
            (setv module (importlib.import-module python-module-name))))
      (except [Exception]
        (setv module None)))
    (setv (get self._module-cache python-module-name) module)
    module)

  (defn _is-workspace-module [self python-module-name]
    (when (self._has-workspace-module-path python-module-name)
      (return True))
    (setv top-level (get (.split python-module-name "." 1) 0))
    (when (and (!= top-level python-module-name) (self._has-workspace-module-path top-level))
      (return True))
    (try
      (with [(self.import-context)]
        (setv spec (importlib.util.find-spec python-module-name)))
      (except [#(ImportError AttributeError ValueError)]
        (return False)))
    (when (is spec None)
      (return False))
    (setv candidates [])
    (when (and spec.origin (not (in spec.origin #{"built-in" "frozen" "namespace"})))
      (.append candidates spec.origin))
    (when spec.submodule-search-locations
      (.extend candidates spec.submodule-search-locations))
    (setv root (.resolve self.root))
    (for [candidate candidates]
      (try
        (.relative-to (.resolve (Path candidate)) root)
        (return True)
        (except [#(OSError ValueError)]
          (continue))))
    False)

  (defn _has-workspace-module-path [self python-module-name]
    (setv module-path (.joinpath self.root #* (.split python-module-name ".")))
    (any (gfor candidate [(.with-suffix module-path ".py")
                          (.with-suffix module-path ".hy")
                          (/ module-path "__init__.py")
                          (/ module-path "__init__.hy")]
               (.exists candidate))))

  (defn resolve-qualified [self qualified-name]
    "Resolve module.attr.attr by importing the longest module prefix."
    (when (in qualified-name self._object-cache)
      (return (get self._object-cache qualified-name)))
    (setv parts (.split qualified-name "."))
    (setv result None)
    (for [split (range (len parts) 0 -1)]
      (setv module-name (.join "." (cut parts 0 split)))
      (setv module (self.import-module module-name))
      (when (is module None)
        (continue))
      (setv result module)
      (try
        (for [attr (cut parts split None)]
          (setv result (getattr result (hy.mangle attr))))
        (except [Exception]
          (setv result None)))
      (break))
    (setv (get self._object-cache qualified-name) result)
    result)

  (defn module-symbol [self visible-name module-name]
    (setv module (self.import-module module-name))
    (if (is-not module None)
        (symbol-from-object visible-name module :detail f"Python module {module-name}")
        (self.static-module-symbol visible-name module-name)))

  (defn object-symbol [self visible-name qualified-name]
    (setv obj (self.resolve-qualified qualified-name))
    (when (is-not obj None)
      (return (symbol-from-object visible-name obj :detail f"Python object {qualified-name}")))
    (setv [module-name _ member-name] (.rpartition qualified-name "."))
    (if (and module-name member-name)
        (self.static-member-symbol visible-name module-name member-name)
        None))

  (defn static-module [self module-name]
    (setv python-module-name (_python-qualified-name module-name))
    (when (not (in python-module-name self._static-module-cache))
      (setv (get self._static-module-cache python-module-name)
            (ps.load-static-python-module self.static-search-paths module-name)))
    (get self._static-module-cache python-module-name))

  (defn static-module-symbol [self visible-name module-name]
    (setv module (self.static-module module-name))
    (if (is module None) None (ps.module-symbol-from-static-module module visible-name)))

  (defn static-member-symbol [self visible-name module-name member-name]
    (self._static-member-symbol visible-name module-name member-name (set)))

  (defn _static-member-symbol [self visible-name module-name member-name seen]
    (setv key #(module-name member-name))
    (when (in key seen)
      (return None))
    (.add seen key)
    (setv module (self.static-module module-name))
    (when (is module None)
      (return None))
    (setv re-exports (or (get module "re-exports") {}))
    (setv re-export (or (.get re-exports member-name)
                        (.get re-exports (hy.unmangle (hy.mangle member-name)))))
    (when (is-not re-export None)
      (setv [target-module target-member] re-export)
      (setv target (self._static-member-symbol visible-name target-module target-member seen))
      (when (is-not target None)
        (return target)))
    (ps.member-symbol-from-static-module module visible-name member-name))

  (defn static-member-symbols [self module-name [prefix ""] [visible-base ""]]
    (setv module (self.static-module module-name))
    (when (is module None)
      (return []))
    (setv symbols [])
    (for [symbol (ps.member-symbols-from-static-module module prefix visible-base)]
      (setv original-name (get (.rsplit (get symbol "name") "." 1) -1))
      (setv resolved (self.static-member-symbol (get symbol "name") module-name original-name))
      (.append symbols (or resolved symbol)))
    (sorted symbols :key (fn [symbol] (get symbol "name"))))

  (defn static-qualified-symbol [self visible-name base-module member-path]
    "Resolve BASE-MODULE.member-path through static modules and members."
    (setv parts (lfor part (.split member-path ".") :if part part))
    (when (not parts)
      (return (self.static-module-symbol visible-name base-module)))
    (for [split (range (len parts) -1 -1)]
      (setv module-suffix (.join "." (cut parts 0 split)))
      (setv candidate-module (if module-suffix f"{base-module}.{module-suffix}" base-module))
      (setv member (.join "." (cut parts split None)))
      (if (not member)
          (do
            (setv module-symbol (self.static-module-symbol visible-name candidate-module))
            (when (is-not module-symbol None)
              (return module-symbol)))
          (do
            (setv symbol (self.static-member-symbol visible-name candidate-module member))
            (when (is-not symbol None)
              (return symbol)))))
    None)

  (defn module-candidates [self prefix]
    "Return importable modules visible from this workspace."
    (when (in "." prefix)
      (return (self._dotted-module-candidates prefix)))
    (setv candidates
      (dfor name (self.top-level-modules) :if (.startswith name prefix)
            name (model.symbol-info name model.KIND-MODULE
                   :detail "importable Python module"
                   :documentation f"Importable Python module `{(hy.mangle name)}`."
                   :module name)))
    (for [name (self.static-top-level-modules prefix)]
      (.setdefault candidates name
        (model.symbol-info name model.KIND-MODULE
          :detail "workspace Python module (static)"
          :documentation f"Workspace Python module `{(hy.mangle name)}`."
          :module name)))
    (sorted (.values candidates) :key (fn [symbol] (get symbol "name"))))

  (defn static-top-level-modules [self [prefix ""]]
    (setv seen (set))
    (for [root self.static-search-paths]
      (try
        (setv children (list (.iterdir root)))
        (except [OSError]
          (continue)))
      (for [child children]
        (setv name "")
        (cond
          (and (.is-file child) (in child.suffix #{".py" ".pyi"}) (!= child.stem "__init__"))
            (setv name (hy.unmangle child.stem))
          (and (.is-dir child) (any (gfor init #("__init__.py" "__init__.pyi") (.exists (/ child init)))))
            (setv name (hy.unmangle child.name)))
        (when (and name (not (.startswith name "_")) (.startswith name prefix))
          (.add seen name))))
    (sorted seen))

  (defn _dotted-module-candidates [self prefix]
    (setv [base-name _ attr-prefix] (.rpartition prefix "."))
    (setv base (self.resolve-qualified base-name))
    (when (is base None)
      (return []))
    (setv candidates {})
    (setv module-path (getattr base "__path__" None))
    (when (is-not module-path None)
      (with [(self.import-context)]
        (for [module (pkgutil.iter-modules module-path :prefix f"{(hy.mangle base-name)}.")]
          (setv name (hy.unmangle module.name))
          (when (.startswith name prefix)
            (setv (get candidates name)
                  (model.symbol-info name model.KIND-MODULE
                    :detail "importable Python module"
                    :documentation f"Importable Python module `{module.name}`."
                    :module name))))))
    (for [symbol (self.attr-symbols base-name base attr-prefix)]
      (when (= (get symbol "kind") model.KIND-MODULE)
        (.setdefault candidates (get symbol "name") symbol)))
    (sorted (.values candidates) :key (fn [symbol] (get symbol "name"))))

  (defn member-candidates [self module-name prefix]
    "Return importable members of MODULE-NAME labelled by member name."
    (setv module (self.import-module module-name))
    (when (is module None)
      (return (self.static-member-symbols module-name prefix)))
    (setv names (or (getattr module "__all__" None) (dir module)))
    (setv symbols [])
    (for [py-name names]
      (when (and (.startswith py-name "_") (not (.startswith prefix "_")))
        (continue))
      (setv hy-name (hy.unmangle py-name))
      (when (and (not (.startswith hy-name prefix)) (not (.startswith py-name prefix)))
        (continue))
      (try
        (setv obj (getattr module py-name))
        (except [Exception]
          (continue)))
      (.append symbols (symbol-from-object hy-name obj :detail f"member of {module-name}")))
    (sorted symbols :key (fn [symbol] (get symbol "name"))))

  (defn macro-candidates [self module-name [prefix ""] [dotted-prefix ""]]
    "Return regular macros exported by MODULE-NAME."
    (setv module (self.import-module module-name))
    (when (is module None)
      (return []))
    (setv symbols [])
    (for [[py-name obj] (_macro-entries module)]
      (setv hy-name (hy.unmangle py-name))
      (setv visible (if dotted-prefix f"{dotted-prefix}.{hy-name}" hy-name))
      (when (and (not (.startswith visible prefix)) (not (.startswith hy-name prefix)))
        (continue))
      (.append symbols (_symbol-from-macro visible obj f"required macro from {module-name}")))
    (sorted symbols :key (fn [symbol] (get symbol "name"))))

  (defn macro-symbol [self visible-name module-name macro-name]
    (setv module (self.import-module module-name))
    (when (is module None)
      (return None))
    (setv macros (getattr module "_hy_macros" {}))
    (setv obj (.get macros (hy.mangle macro-name)))
    (if (is obj None) None (_symbol-from-macro visible-name obj f"required macro from {module-name}")))

  (defn reader-macro-candidates [self module-name [prefix ""] [include-hash False]]
    "Return reader macros exported by MODULE-NAME."
    (setv module (self.import-module module-name))
    (when (is module None)
      (return []))
    (setv symbols [])
    (for [[name obj] (_reader-macro-entries module)]
      (setv visible (if include-hash f"#{name}" name))
      (when (and (not (.startswith visible prefix)) (not (.startswith name prefix)))
        (continue))
      (.append symbols (_symbol-from-macro visible obj f"reader macro from {module-name}" :reader True)))
    (sorted symbols :key (fn [symbol] (get symbol "name"))))

  (defn reader-macro-symbol [self visible-name module-name reader-name]
    (setv module (self.import-module module-name))
    (when (is module None)
      (return None))
    (setv readers (getattr module "_hy_reader_macros" {}))
    (setv obj (.get readers reader-name))
    (if (is obj None) None (_symbol-from-macro visible-name obj f"reader macro from {module-name}" :reader True)))

  (defn top-level-modules [self]
    (when (is self._top-level-modules None)
      (setv seen (set))
      (with [(self.import-context)]
        (for [module (pkgutil.iter-modules)]
          (when (not (.startswith module.name "_"))
            (.add seen (hy.unmangle module.name)))))
      (setv self._top-level-modules (sorted seen)))
    self._top-level-modules)

  (defn attr-symbols [self base-name base-obj [attr-prefix ""]]
    (setv symbols [])
    (for [py-name (dir base-obj)]
      (when (and (.startswith py-name "_") (not (.startswith attr-prefix "_")))
        (continue))
      (setv hy-name (hy.unmangle py-name))
      (when (and (not (.startswith hy-name attr-prefix)) (not (.startswith py-name attr-prefix)))
        (continue))
      (try
        (setv obj (getattr base-obj py-name))
        (except [Exception]
          (continue)))
      (setv visible f"{base-name}.{hy-name}")
      (.append symbols (symbol-from-object visible obj :detail f"attribute of {base-name}")))
    (sorted symbols :key (fn [s] (get s "name")))))

;; ---------------------------------------------------------------------------
;; symbol construction from runtime objects
;; ---------------------------------------------------------------------------

(defn symbol-from-object [name obj [detail "Python object"]]
  (model.symbol-info name (_kind-for-object obj)
    :detail detail
    :signature (_signature obj)
    :documentation (or (inspect.getdoc obj) "")
    :source (_source-for-object obj)
    :runtime-object obj
    :module (if (inspect.ismodule obj) (getattr obj "__name__" "") (getattr obj "__module__" ""))))

(defn _symbol-from-macro [name obj detail [reader False]]
  (model.symbol-info name (if reader model.KIND-READER-MACRO model.KIND-LOCAL-MACRO)
    :detail detail
    :signature (_signature obj)
    :documentation (or (inspect.getdoc obj) "")
    :source (_source-for-object obj)
    :runtime-object obj
    :module (getattr obj "__module__" "")))

(defn _macro-entries [module]
  (setv macros (getattr module "_hy_macros" {}))
  (when (not (isinstance macros dict))
    (return []))
  (setv exports (getattr module "_hy_export_macros" None))
  (setv names (if (is-not exports None) exports
                  (lfor name macros :if (not (.startswith name "_")) name)))
  (setv out [])
  (for [name names]
    (when (not (isinstance name str))
      (continue))
    (setv obj (or (.get macros (hy.mangle (hy.unmangle name))) (.get macros name)))
    (when (is-not obj None)
      (.append out #((hy.mangle (hy.unmangle name)) obj))))
  out)

(defn _reader-macro-entries [module]
  (setv readers (getattr module "_hy_reader_macros" {}))
  (when (not (isinstance readers dict))
    (return []))
  (sorted (lfor #(name obj) (.items readers)
                :if (and (isinstance name str) (not (.startswith name "_")))
                #(name obj))))

;; ---------------------------------------------------------------------------
;; workspace discovery
;; ---------------------------------------------------------------------------

(defn find-workspace-root [path]
  "Find a practical Python/Hy project root for PATH."
  (setv start (if (.is-dir path) path path.parent))
  (for [current [start #* start.parents]]
    (when (any (gfor marker ["pyproject.toml" "uv.lock" ".git"] (.exists (/ current marker))))
      (return current)))
  start)

(defn iter-hy-files [root [limit 500] [exclude-dirs None]]
  (setv ignored (set (if (is exclude-dirs None) _IGNORED-DIRS exclude-dirs)))
  (setv count 0)
  (setv out [])
  (for [path (.rglob root "*.hy")]
    (when (any (gfor part path.parts (in part ignored)))
      (continue))
    (.append out path)
    (+= count 1)
    (when (>= count limit)
      (break)))
  out)

(defn _search-paths [root [include-root True]]
  (setv paths (if include-root [root] []))
  (.extend paths (_venv-site-packages root))
  (_dedupe-paths paths))

(defn _static-search-paths [root]
  (_dedupe-paths [root #* (_venv-site-packages root)]))

(defn _venv-site-packages [root]
  (setv paths [])
  (for [venv-name [".venv" "venv"]]
    (setv venv (/ root venv-name))
    (for [lib-name ["lib" "lib64"]]
      (setv lib (/ venv lib-name))
      (when (.exists lib)
        (.extend paths (lfor path (.glob lib "python*/site-packages") :if (.exists path) path))))
    (setv windows-site (/ venv "Lib" "site-packages"))
    (when (.exists windows-site)
      (.append paths windows-site)))
  paths)

(defn _dedupe-paths [paths]
  (setv out [])
  (setv seen (set))
  (for [path paths]
    (setv resolved (.resolve path))
    (when (not (in resolved seen))
      (.add seen resolved)
      (.append out resolved)))
  out)

;; ---------------------------------------------------------------------------
;; runtime object introspection
;; ---------------------------------------------------------------------------

(defn _kind-for-object [obj]
  (cond
    (inspect.ismodule obj) model.KIND-MODULE
    (inspect.isclass obj) model.KIND-LOCAL-CLASS
    (or (inspect.isfunction obj) (inspect.ismethod obj) (inspect.isbuiltin obj)) model.KIND-LOCAL-FUNCTION
    True model.KIND-UNKNOWN))

(defn _signature [obj]
  (try
    (if (callable obj) (str (inspect.signature obj)) "")
    (except [#(TypeError ValueError)]
      "")))

(defn _source-for-object [obj]
  (setv direct (_direct-source-for-object obj))
  (when (is-not direct None)
    (return direct))
  (when (inspect.ismodule obj)
    (return (_source-for-module obj)))
  (setv module-name (getattr obj "__module__" None))
  (setv object-name (getattr obj "__name__" None))
  (when (isinstance module-name str)
    (when (isinstance object-name str)
      (setv stub (_source-for-stub-object module-name object-name))
      (when (is-not stub None)
        (return stub)))
    (setv module (.get sys.modules module-name))
    (when (is module None)
      (try
        (setv module (importlib.import-module module-name))
        (except [Exception]
          (setv module None))))
    (when (is-not module None)
      (return (_source-for-module module))))
  None)

(defn _direct-source-for-object [obj]
  (try
    (setv file-name (or (inspect.getsourcefile obj) (inspect.getfile obj)))
    (except [#(TypeError OSError)]
      (return None)))
  (when (not file-name)
    (return None))
  (setv path (Path file-name))
  (when (or (not (.exists path)) (not (in path.suffix #{".py" ".pyi" ".hy"})))
    (return None))
  (try
    (setv [_ line] (inspect.getsourcelines obj))
    (except [#(OSError TypeError)]
      (setv line 1)))
  (_range-for-path path line))

(defn _source-for-module [module]
  (for [candidate [(getattr module "__file__" None)
                   (getattr (getattr module "__spec__" None) "origin" None)]]
    (when (and candidate (not (in candidate #{"built-in" "frozen" "namespace"})))
      (setv path (Path candidate))
      (when (and (.exists path) (in path.suffix #{".py" ".pyi" ".hy"}))
        (return (_range-for-path path 1)))))
  (setv name (getattr module "__name__" None))
  (when (isinstance name str)
    (setv stub (_find-stub-for-module name))
    (when (is-not stub None)
      (return (_range-for-path stub 1))))
  None)

(defn _find-stub-for-module [module-name]
  (setv module-path (Path #* (.split module-name ".")))
  (for [base (map Path sys.path)]
    (for [candidate [(/ base (.with-suffix module-path ".pyi"))
                     (/ base module-path "__init__.pyi")]]
      (when (.exists candidate)
        (return candidate))))
  (try
    (setv bundled (get-stub-file module-name))
    (except [Exception]
      (setv bundled None)))
  (when (is-not bundled None)
    (return (Path bundled)))
  (try
    (setv spec (importlib.util.find-spec module-name))
    (except [#(ImportError ValueError)]
      (setv spec None)))
  (when (and spec spec.origin)
    (setv origin (Path spec.origin))
    (when (.exists (.with-suffix origin ".pyi"))
      (return (.with-suffix origin ".pyi"))))
  None)

(defn _source-for-stub-object [module-name object-name]
  (setv stub (_find-stub-for-module module-name))
  (when (is stub None)
    (return None))
  (setv line (_find-top-level-stub-name stub object-name))
  (if (is line None) (_range-for-path stub 1) (_range-for-path stub line)))

(defn _find-top-level-stub-name [path name]
  (try
    (setv tree (ast.parse (.read-text path :encoding "utf-8")))
    (except [#(OSError SyntaxError UnicodeDecodeError)]
      (return None)))
  (setv candidates #{name (hy.mangle name)})
  (for [node tree.body]
    (when (and (isinstance node #(ast.FunctionDef ast.AsyncFunctionDef ast.ClassDef)) (in node.name candidates))
      (return node.lineno))
    (when (isinstance node ast.Assign)
      (for [target node.targets]
        (when (and (isinstance target ast.Name) (in target.id candidates))
          (return node.lineno))))
    (when (and (isinstance node ast.AnnAssign) (isinstance node.target ast.Name) (in node.target.id candidates))
      (return node.lineno)))
  None)

(defn _range-for-path [path line]
  (setv uri-str (uri.from-fs-path (str (.resolve path))))
  (setv line0 (max (- line 1) 0))
  (model.source-range uri-str line0 0 line0 0))
