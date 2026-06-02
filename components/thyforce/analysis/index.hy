"Workspace and document indexes.

`DocumentIndex` reads one Hy document into definitions, scoped parameter symbols,
import/require bindings, and parse/compile diagnostics. `WorkspaceIndex` is a
server-owned (non-global) index over many documents plus per-root Python
resolvers, and answers completion / resolution queries. All public symbol output
is plain symbol-info maps (see model.hy); the internal parse intermediates below
are lightweight classes kept close to the source for fidelity.
"

(import builtins)
(import inspect)
(import contextlib [nullcontext])
(import pathlib [Path])

(import hy)
(import hy.compiler [hy-compile])
(import hy.models [Dict :as HyDict Expression Keyword List :as HyList String Symbol])

(import thyforce.analysis.model :as model)
(import thyforce.analysis.core-docs [CORE-DOCS])
(import thyforce.analysis.uri :as uris)
(import thyforce.analysis.config [load-config])
(import thyforce.analysis.resolver
        [PythonResolver find-workspace-root iter-hy-files symbol-from-object])

;; ---------------------------------------------------------------------------
;; diagnostics
;; ---------------------------------------------------------------------------

(defn parse-diagnostic [message [line 0] [character 0] [end-line 0] [end-character 1] [code "thyforce"]]
  "Build a parse/compile diagnostic map (zero-based, end-exclusive)."
  {"message" message "line" line "character" character
   "end-line" end-line "end-character" end-character "code" code})

;; ---------------------------------------------------------------------------
;; internal parse intermediates
;; ---------------------------------------------------------------------------

(defclass ScopedSymbol []
  (defn __init__ [self symbol scope]
    (setv self.symbol symbol self.scope scope))
  (defn contains [self line character]
    (setv r (get self.scope "range"))
    (setv start (get r "start"))
    (setv end (get r "end"))
    (and (<= #((get start "line") (get start "character")) #(line character))
         (<= #(line character) #((get end "line") (get end "character"))))))

(defclass HyImportBinding []
  (defn __init__ [self visible module [member ""] [star False] [source None]]
    (setv self.visible visible self.module module self.member member
          self.star star self.source source)))

(defclass ImportMember []
  (defn __init__ [self original visible model]
    (setv self.original original self.visible visible self.model model)))

(defclass ImportSpec []
  (defn __init__ [self module model [alias ""] [alias-model None] [members #()] [star False]]
    (setv self.module module self.model model self.alias alias
          self.alias-model alias-model self.members members self.star star)))

(defclass RequireSpec []
  (defn __init__ [self module [alias ""] [prefix-all False] [members #()]
                  [star False] [readers #()] [reader-star False]]
    (setv self.module module self.alias alias self.prefix-all prefix-all
          self.members members self.star star self.readers readers
          self.reader-star reader-star)))

;; ---------------------------------------------------------------------------
;; document index
;; ---------------------------------------------------------------------------

(defclass DocumentIndex []
  (defn __init__ [self uri source [module ""]]
    (setv self.uri uri self.source source self.module module
          self.symbols {} self.scoped-symbols [] self.imports [] self.diagnostics []))

  (defn [classmethod] build [cls uri source [resolver None] [compile-forms True] [module ""]]
    (setv index (cls uri source :module module))
    (setv forms (index._read-forms source))
    (for [form forms]
      (index._walk-form form resolver))
    (when compile-forms
      (index._record-compile-diagnostics forms source resolver))
    index)

  (defn _read-forms [self source]
    (setv forms [])
    (try
      (for [form (hy.read-many source :filename self.uri)]
        (.append forms form))
      (except [exc Exception]
        (.append self.diagnostics (_diagnostic-from-exception exc source "hy-reader"))))
    forms)

  (defn _record-compile-diagnostics [self forms source resolver]
    (setv context (if (is-not resolver None) (resolver.import-context) (nullcontext)))
    (with [context]
      (for [form forms]
        (try
          (hy-compile form "__main__" :filename self.uri :source source)
          (except [exc Exception]
            (setv diagnostic (_diagnostic-from-exception exc source "hy-compiler"))
            (when (not (any (gfor d self.diagnostics
                                  (and (= (get d "message") (get diagnostic "message"))
                                       (= (get d "line") (get diagnostic "line"))
                                       (= (get d "character") (get diagnostic "character"))
                                       (= (get d "code") (get diagnostic "code"))))))
              (.append self.diagnostics diagnostic)))))))

  (defn _walk-form [self form resolver]
    (cond
      (and (isinstance form Expression) form)
        (do
          (self._record-definition form resolver)
          (for [child form]
            (self._walk-form child resolver)))
      (isinstance form HyList)
        (for [child form]
          (self._walk-form child resolver))))

  (defn _record-definition [self form resolver]
    (setv head (_symbol-name (get form 0)))
    (cond
      (in head #{"defn" "defmacro" "defreader"}) (self._record-callable form head)
      (= head "defclass") (self._record-class form)
      (in head #{"setv" "setx"}) (self._record-assignment form head)
      (and (= head "import") (is-not resolver None)) (self._record-import form resolver)
      (and (= head "require") (is-not resolver None)) (self._record-require form resolver)))

  (defn _record-callable [self form head]
    (when (or (< (len form) 3) (not (isinstance (get form 1) Symbol)))
      (return))
    (setv raw-name (str (get form 1)))
    (setv name (if (= head "defreader") f"#{raw-name}" raw-name))
    (setv params (_format-model (get form 2)))
    (setv body (list (cut form 3 None)))
    (setv doc (_leading-docstring body))
    (setv kind (_callable-symbol-kind head))
    (setv (get self.symbols name)
          (model.symbol-info name kind
            :detail f"local {head}"
            :signature (_callable-signature head raw-name name params)
            :documentation doc
            :source (model.from-hy-model self.uri (get form 1))
            :module self.module))
    (self._record-parameters raw-name (get form 2) form))

  (defn _record-parameters [self callable-name params scope-model]
    (setv scope (model.from-hy-model self.uri scope-model))
    (for [[name mdl] (_parameter-models params)]
      (.append self.scoped-symbols
        (ScopedSymbol
          (model.symbol-info name model.KIND-PARAMETER
            :detail f"parameter of {callable-name}"
            :documentation f"Parameter `{name}` of `{callable-name}`."
            :source (model.from-hy-model self.uri mdl)
            :module self.module)
          scope))))

  (defn _record-class [self form]
    (when (or (< (len form) 2) (not (isinstance (get form 1) Symbol)))
      (return))
    (setv name (str (get form 1)))
    (setv bases (if (> (len form) 2) (_format-model (get form 2)) "[]"))
    (setv body (if (> (len form) 3) (list (cut form 3 None)) []))
    (setv doc (_leading-docstring body))
    (setv (get self.symbols name)
          (model.symbol-info name model.KIND-LOCAL-CLASS
            :detail "local defclass"
            :signature f"(defclass {name} {bases})"
            :documentation doc
            :source (model.from-hy-model self.uri (get form 1))
            :module self.module)))

  (defn _record-assignment [self form head]
    (for [target (cut form 1 None 2)]
      (for [[name mdl] (_assignment-target-models target)]
        (setv (get self.symbols name)
              (model.symbol-info name model.KIND-LOCAL-VARIABLE
                :detail f"local {head}"
                :documentation f"Local value bound with {head}."
                :source (model.from-hy-model self.uri mdl)
                :module self.module)))))

  (defn _record-import [self form resolver]
    (for [spec (_parse-import-specs (list (cut form 1 None)))]
      (self._record-hy-import-binding spec)
      (cond
        spec.star (self._record-star-import spec.module resolver)
        spec.members
          (for [member spec.members]
            (self._add-symbol (resolver.object-symbol member.visible f"{spec.module}.{member.original}")))
        spec.alias
          (self._add-symbol (resolver.module-symbol spec.alias spec.module))
        True
          (do
            (setv visible (if (in "." spec.module) (get (.split spec.module ".") 0) spec.module))
            (self._add-symbol (resolver.module-symbol visible visible))
            (self._add-symbol (resolver.module-symbol spec.module spec.module))))))

  (defn _record-hy-import-binding [self spec]
    (cond
      spec.star
        (.append self.imports (HyImportBinding "" spec.module :star True
                                :source (model.from-hy-model self.uri spec.model)))
      spec.members
        (for [member spec.members]
          (.append self.imports (HyImportBinding member.visible spec.module
                                  :member member.original
                                  :source (model.from-hy-model self.uri member.model))))
      spec.alias
        (.append self.imports (HyImportBinding spec.alias spec.module
                                :source (model.from-hy-model self.uri (or spec.alias-model spec.model))))
      True
        (do
          (setv top-level (get (.split spec.module ".") 0))
          (.append self.imports (HyImportBinding top-level top-level
                                  :source (model.from-hy-model self.uri spec.model)))
          (when (!= spec.module top-level)
            (.append self.imports (HyImportBinding spec.module spec.module
                                    :source (model.from-hy-model self.uri spec.model)))))))

  (defn _record-star-import [self module-name resolver]
    (setv module (resolver.import-module module-name))
    (when (is module None)
      (return))
    (for [py-name (or (getattr module "__all__" None) (dir module))]
      (when (.startswith py-name "_")
        (continue))
      (setv hy-name (hy.unmangle py-name))
      (try
        (self._add-symbol (symbol-from-object hy-name (getattr module py-name)
                            :detail f"imported from {module-name}"))
        (except [Exception]
          (continue)))))

  (defn _record-require [self form resolver]
    (for [spec (_parse-require-specs (list (cut form 1 None)))]
      (when spec.prefix-all
        (setv prefix (or spec.alias spec.module))
        (for [symbol (resolver.macro-candidates spec.module :dotted-prefix prefix)]
          (self._add-symbol symbol)))
      (when spec.star
        (for [symbol (resolver.macro-candidates spec.module)]
          (self._add-symbol symbol)))
      (for [member spec.members]
        (setv symbol (resolver.macro-symbol member.visible spec.module member.original))
        (self._add-symbol (or symbol (self._provisional-required-macro spec.module member))))
      (when spec.reader-star
        (for [symbol (resolver.reader-macro-candidates spec.module :include-hash True)]
          (self._add-symbol symbol)))
      (for [reader spec.readers]
        (setv visible f"#{reader.original}")
        (setv symbol (resolver.reader-macro-symbol visible spec.module reader.original))
        (self._add-symbol (or symbol (self._provisional-required-macro spec.module reader :reader True))))))

  (defn _provisional-required-macro [self module-name member [reader False]]
    (setv visible (if reader f"#{member.original}" member.visible))
    (setv kind (if reader model.KIND-READER-MACRO model.KIND-LOCAL-MACRO))
    (setv noun (if reader "Reader macro" "Macro"))
    (setv what (if reader "reader macro" "macro"))
    (model.symbol-info visible kind
      :detail f"required {what} from {module-name}"
      :documentation f"{noun} required from `{module-name}`."
      :source (model.from-hy-model self.uri member.model)
      :module module-name))

  (defn _add-symbol [self symbol]
    (when (is-not symbol None)
      (setv (get self.symbols (get symbol "name")) symbol))))

;; ---------------------------------------------------------------------------
;; workspace index
;; ---------------------------------------------------------------------------

(defclass WorkspaceIndex []
  "Explicit server-owned index; no process-global symbol table."

  (defn __init__ [self]
    (setv self.documents {})
    (setv self.core-symbols (_load-core-symbols))
    (setv self.builtin-symbols (_load-builtin-symbols))
    (setv self.resolvers {})
    (setv self.configs {})
    (setv self.indexed-roots (set)))

  (defn update-document [self uri source]
    (setv root (self.root-for-uri uri))
    (setv resolver (self.resolver-for-root root))
    (setv document (DocumentIndex.build uri source resolver :module (self.module-for-uri uri root)))
    (setv (get self.documents uri) document)
    (self.ensure-project-index root)
    document)

  (defn remove-document [self uri]
    (.pop self.documents uri None))

  (defn root-for-uri [self uri]
    (try
      (setv path (Path (uris.to-fs-path uri)))
      (except [Exception]
        (return (Path.cwd))))
    (find-workspace-root path))

  (defn resolver-for-root [self root]
    (setv root (.resolve root))
    (when (not (in root self.resolvers))
      (setv (get self.resolvers root) (PythonResolver root (self.config-for-root root))))
    (get self.resolvers root))

  (defn config-for-root [self root]
    (setv root (.resolve root))
    (when (not (in root self.configs))
      (setv (get self.configs root) (load-config root)))
    (get self.configs root))

  (defn module-for-uri [self uri root]
    (try
      (setv path (Path (uris.to-fs-path uri)))
      (except [Exception]
        (return "")))
    (_module-name-for-path root path))

  (defn ensure-project-index [self root]
    (setv root (.resolve root))
    (when (in root self.indexed-roots)
      (return))
    (setv resolver (self.resolver-for-root root))
    (setv config (self.config-for-root root))
    (for [path (iter-hy-files root :limit (get config "index-limit") :exclude-dirs (get config "exclude-dirs"))]
      (setv doc-uri (uris.from-fs-path (str (.resolve path))))
      (when (in doc-uri self.documents)
        (continue))
      (try
        (setv (get self.documents doc-uri)
              (DocumentIndex.build doc-uri (.read-text path) resolver
                :compile-forms False :module (_module-name-for-path root path)))
        (except [UnicodeDecodeError]
          (continue))))
    (.add self.indexed-roots root))

  (defn reindex-root [self root [open-sources None]]
    "Force a fresh resolver and symbol index for ROOT."
    (setv root (.resolve root))
    (setv open-sources (or open-sources {}))
    (.pop self.configs root None)
    (setv (get self.resolvers root) (PythonResolver root (self.config-for-root root)))
    (.discard self.indexed-roots root)
    (for [doc-uri (list self.documents)]
      (when (= (.resolve (self.root-for-uri doc-uri)) root)
        (.pop self.documents doc-uri None)))
    (setv resolver (self.resolver-for-root root))
    (setv rebuilt [])
    (for [[doc-uri source] (.items open-sources)]
      (when (!= (.resolve (self.root-for-uri doc-uri)) root)
        (continue))
      (setv document (DocumentIndex.build doc-uri source resolver :module (self.module-for-uri doc-uri root)))
      (setv (get self.documents doc-uri) document)
      (.append rebuilt document))
    (self.ensure-project-index root)
    rebuilt)

  (defn symbols-for-completion [self uri prefix [line None] [character None]]
    (when (in "." prefix)
      (return (self._attribute-completions uri prefix)))
    (setv seen (set))
    (setv out [])
    (setv symbol-sources [])
    (when (in uri self.documents)
      (setv document (get self.documents uri))
      (when (and (is-not line None) (is-not character None))
        (.append symbol-sources (self._scoped-symbols-at document line character)))
      (.append symbol-sources (.values document.symbols))
      (.append symbol-sources (self._hy-import-completion-symbols uri document prefix)))
    (.extend symbol-sources
      (gfor [doc-uri document] (.items self.documents) :if (!= doc-uri uri) (.values document.symbols)))
    (.extend symbol-sources [(.values self.core-symbols) (.values self.builtin-symbols)])
    (for [symbols symbol-sources]
      (for [symbol symbols]
        (when (in (get symbol "name") seen)
          (continue))
        (when (.startswith (get symbol "name") prefix)
          (.add seen (get symbol "name"))
          (.append out symbol))))
    (for [symbol (.module-candidates (self.resolver-for-root (self.root-for-uri uri)) prefix)]
      (when (not (in (get symbol "name") seen))
        (.add seen (get symbol "name"))
        (.append out symbol)))
    (sorted out :key (fn [s] #((.startswith (get s "name") "_") (get s "name")))))

  (defn _scoped-symbols-at [self document line character]
    (lfor scoped document.scoped-symbols :if (.contains scoped line character) scoped.symbol))

  (defn _resolve-scoped [self document name line character]
    (setv matches (lfor scoped document.scoped-symbols
                        :if (and (= (get scoped.symbol "name") name) (.contains scoped line character))
                        scoped))
    (when (not matches)
      (return None))
    (. (min matches :key (fn [scoped]
                           (setv r (get scoped.scope "range"))
                           #((- (get (get r "end") "line") (get (get r "start") "line"))
                             (- (get (get r "end") "character") (get (get r "start") "character")))))
       symbol))

  (defn _hy-import-completion-symbols [self uri document prefix]
    (setv symbols [])
    (for [binding document.imports]
      (cond
        binding.star
          (do
            (setv module-document (self._document-for-module uri binding.module))
            (when (is-not module-document None)
              (.extend symbols
                (gfor symbol (.values module-document.symbols)
                      :if (.startswith (get symbol "name") prefix)
                      (_clone-symbol symbol (get symbol "name"))))))
        binding.member
          (do
            (setv symbol (self._symbol-from-hy-module uri binding.module binding.member binding.visible))
            (when (and (is-not symbol None) (.startswith (get symbol "name") prefix))
              (.append symbols symbol)))
        (.startswith binding.visible prefix)
          (do
            (setv module-symbol (self._hy-module-symbol uri binding.module binding.visible))
            (when (is-not module-symbol None)
              (.append symbols module-symbol)))))
    symbols)

  (defn _attribute-completions [self uri prefix]
    (setv [base-name _ attr-prefix] (.rpartition prefix "."))
    (setv base (self.resolve uri base-name))
    (when (and (is-not base None) (= (get base "kind") model.KIND-MODULE) (get base "module"))
      (setv hy-symbols (self._hy-module-attribute-symbols uri (get base "module") base-name attr-prefix))
      (when hy-symbols
        (return hy-symbols))
      (setv static-symbols (.static-member-symbols (self.resolver-for-root (self.root-for-uri uri))
                             (get base "module") attr-prefix :visible-base base-name))
      (when static-symbols
        (return static-symbols)))
    (when (is base None)
      (setv root (self.root-for-uri uri))
      (setv obj (.resolve-qualified (self.resolver-for-root root) base-name))
      (when (is obj None)
        (return []))
      (setv base (symbol-from-object base-name obj)))
    (when (is (get base "runtime-object") None)
      (return []))
    (.attr-symbols (self.resolver-for-root (self.root-for-uri uri)) base-name (get base "runtime-object") attr-prefix))

  (defn _hy-module-attribute-symbols [self uri module visible-base attr-prefix]
    (setv document (self._document-for-module uri module))
    (when (is document None)
      (return []))
    (sorted
      (gfor symbol (.values document.symbols)
            :if (.startswith (get symbol "name") attr-prefix)
            (_clone-symbol symbol (+ visible-base "." (get symbol "name"))))
      :key (fn [symbol] (get symbol "name"))))

  (defn _document-for-module [self uri module]
    (setv root (.resolve (self.root-for-uri uri)))
    (for [[doc-uri document] (.items self.documents)]
      (when (!= document.module module)
        (continue))
      (when (= (.resolve (self.root-for-uri doc-uri)) root)
        (return document)))
    None)

  (defn _hy-module-symbol [self uri module visible]
    (setv document (self._document-for-module uri module))
    (when (is document None)
      (return None))
    (model.symbol-info visible model.KIND-MODULE
      :detail f"Hy module {module}"
      :documentation f"Hy module `{module}`."
      :source (model.source-range document.uri 0 0 0 0)
      :module module))

  (defn _symbol-from-hy-module [self uri module member visible]
    (setv document (self._document-for-module uri module))
    (when (is document None)
      (return None))
    (setv symbol (.get document.symbols member))
    (if (is symbol None) None (_clone-symbol symbol visible)))

  (defn _resolve-hy-import [self uri document name]
    (for [binding document.imports]
      (cond
        binding.star
          (when (not (in "." name))
            (setv symbol (self._symbol-from-hy-module uri binding.module name name))
            (when (is-not symbol None)
              (return symbol)))
        binding.member
          (when (= name binding.visible)
            (setv symbol (self._symbol-from-hy-module uri binding.module binding.member binding.visible))
            (when (is-not symbol None)
              (return symbol)))
        True
          (do
            (when (= name binding.visible)
              (setv module-symbol (self._hy-module-symbol uri binding.module binding.visible))
              (when (is-not module-symbol None)
                (return module-symbol)))
            (setv prefix f"{binding.visible}.")
            (when (.startswith name prefix)
              (setv rest (cut name (len prefix) None))
              (setv symbol (self._resolve-hy-module-path uri binding.module rest name))
              (when (is-not symbol None)
                (return symbol))))))
    None)

  (defn _resolve-hy-module-path [self uri module rest visible]
    (setv parts (lfor part (.split rest ".") :if part part))
    (for [split (range 0 (+ (len parts) 1))]
      (setv module-suffix (.join "." (cut parts 0 split)))
      (setv candidate-module (if module-suffix f"{module}.{module-suffix}" module))
      (setv member (.join "." (cut parts split None)))
      (if (not member)
          (do
            (setv module-symbol (self._hy-module-symbol uri candidate-module visible))
            (when (is-not module-symbol None)
              (return module-symbol)))
          (do
            (setv symbol (self._symbol-from-hy-module uri candidate-module member visible))
            (when (is-not symbol None)
              (return symbol)))))
    None)

  (defn resolve [self uri name [line None] [character None]]
    (when (in "." name)
      (setv resolved (self._resolve-dotted uri name))
      (when (is-not resolved None)
        (return resolved)))
    (setv document (.get self.documents uri))
    (when (and document (is-not line None) (is-not character None))
      (setv scoped (self._resolve-scoped document name line character))
      (when (is-not scoped None)
        (return scoped)))
    (when (and document (in name document.symbols))
      (return (get document.symbols name)))
    (when document
      (setv imported (self._resolve-hy-import uri document name))
      (when (is-not imported None)
        (return imported)))
    (for [[doc-uri other] (.items self.documents)]
      (when (and (!= doc-uri uri) (in name other.symbols))
        (return (get other.symbols name))))
    (when (in name self.core-symbols)
      (return (get self.core-symbols name)))
    (when (in name self.builtin-symbols)
      (return (get self.builtin-symbols name)))
    (setv root (self.root-for-uri uri))
    (setv obj (.resolve-qualified (self.resolver-for-root root) name))
    (if (is-not obj None) (symbol-from-object name obj) None))

  (defn _resolve-dotted [self uri name]
    (setv document (.get self.documents uri))
    (when (is-not document None)
      (setv imported (self._resolve-hy-import uri document name))
      (when (is-not imported None)
        (return imported)))
    (setv [base-name _ rest] (.partition name "."))
    (setv base (if (!= base-name name) (self.resolve uri base-name) None))
    (when (and (is-not base None) (= (get base "kind") model.KIND-MODULE) (get base "module"))
      (setv static-symbol (.static-qualified-symbol (self.resolver-for-root (self.root-for-uri uri))
                            name (get base "module") rest))
      (when (is-not static-symbol None)
        (return static-symbol)))
    (setv obj (if (and base (is-not (get base "runtime-object") None)) (get base "runtime-object") None))
    (when (is-not obj None)
      (try
        (for [part (.split rest ".")]
          (setv obj (getattr obj (hy.mangle part))))
        (return (symbol-from-object name obj :detail f"attribute of {base-name}"))
        (except [Exception]
          None)))
    (setv root (self.root-for-uri uri))
    (setv obj (.resolve-qualified (self.resolver-for-root root) name))
    (if (is-not obj None) (symbol-from-object name obj) None)))

;; ---------------------------------------------------------------------------
;; import / require parsing
;; ---------------------------------------------------------------------------

(defn _parse-import-specs [items]
  (setv specs [])
  (setv i 0)
  (while (< i (len items))
    (setv model-form (get items i))
    (setv module-name (_module-name model-form))
    (if (not module-name)
        (+= i 1)
        (do
          (setv alias "")
          (setv alias-model None)
          (setv members #())
          (setv star False)
          (+= i 1)
          (cond
            (and (< (+ i 1) (len items)) (_is-keyword (get items i) "as") (isinstance (get items (+ i 1)) Symbol))
              (do (setv alias (str (get items (+ i 1)))) (setv alias-model (get items (+ i 1))) (+= i 2))
            (and (< i (len items)) (isinstance (get items i) HyList))
              (do (setv [members star] (_parse-member-selector (get items i))) (+= i 1))
            (and (< i (len items)) (_is-star (get items i)))
              (do (setv star True) (+= i 1)))
          (.append specs (ImportSpec module-name model-form :alias alias :alias-model alias-model
                           :members members :star star)))))
  specs)

(defn _parse-require-specs [items]
  (setv specs [])
  (setv i 0)
  (while (< i (len items))
    (setv module-name (_module-name (get items i)))
    (if (not module-name)
        (+= i 1)
        (do
          (+= i 1)
          (setv alias "")
          (setv members [])
          (setv readers [])
          (setv star False)
          (setv reader-star False)
          (setv saw-regular-selector False)
          (setv saw-reader-selector False)
          (while (< i (len items))
            (setv item (get items i))
            (cond
              (and (< (+ i 1) (len items)) (_is-keyword item "as") (isinstance (get items (+ i 1)) Symbol))
                (do (setv alias (str (get items (+ i 1)))) (+= i 2))
              (and (< (+ i 1) (len items)) (_is-keyword item "macros"))
                (do
                  (setv [selected selected-star] (_parse-selector-model (get items (+ i 1))))
                  (.extend members selected)
                  (setv star (or star selected-star))
                  (setv saw-regular-selector True)
                  (+= i 2))
              (and (< (+ i 1) (len items)) (_is-keyword item "readers"))
                (do
                  (setv [selected selected-star] (_parse-selector-model (get items (+ i 1))))
                  (.extend readers selected)
                  (setv reader-star (or reader-star selected-star))
                  (setv saw-reader-selector True)
                  (+= i 2))
              (isinstance item HyList)
                (do
                  (setv [selected selected-star] (_parse-member-selector item))
                  (.extend members selected)
                  (setv star (or star selected-star))
                  (setv saw-regular-selector True)
                  (+= i 1))
              (_is-star item)
                (do (setv star True) (setv saw-regular-selector True) (+= i 1))
              (isinstance item Keyword)
                (+= i 1)
              True
                (break)))
          (setv prefix-all (and (not saw-regular-selector) (not saw-reader-selector)))
          (.append specs (RequireSpec module-name :alias alias :prefix-all prefix-all
                           :members (tuple members) :star star
                           :readers (tuple readers) :reader-star reader-star)))))
  specs)

(defn _parse-selector-model [model-form]
  (cond
    (isinstance model-form HyList)
      (do (setv [members star] (_parse-member-selector model-form)) #((list members) star))
    (_is-star model-form) #([] True)
    (isinstance model-form Symbol)
      (do (setv name (str model-form)) #([(ImportMember name name model-form)] False))
    True #([] False)))

(defn _parse-member-selector [values]
  (setv raw (list values))
  (when (and (= (len raw) 1) (_is-star (get raw 0)))
    (return #(#() True)))
  (setv members [])
  (setv i 0)
  (while (< i (len raw))
    (setv value (get raw i))
    (if (not (isinstance value Symbol))
        (+= i 1)
        (do
          (setv original (str value))
          (setv visible original)
          (if (and (< (+ i 2) (len raw)) (_is-keyword (get raw (+ i 1)) "as") (isinstance (get raw (+ i 2)) Symbol))
              (do (setv visible (str (get raw (+ i 2)))) (+= i 3))
              (+= i 1))
          (.append members (ImportMember original visible value)))))
  #((tuple members) False))

(defn _is-star [model-form]
  (and (isinstance model-form Symbol) (= (str model-form) "*")))

;; ---------------------------------------------------------------------------
;; symbol helpers and core/builtin loading
;; ---------------------------------------------------------------------------

(defn _clone-symbol [symbol name]
  (setv out (dict symbol))
  (setv (get out "name") name)
  out)

(defn _module-name-for-path [root path]
  (try
    (setv relative (.relative-to (.resolve path) (.resolve root)))
    (except [ValueError]
      (setv relative (Path path.name))))
  (setv without-suffix (.with-suffix relative ""))
  (setv parts (list without-suffix.parts))
  (when (and parts (= (get parts -1) "__init__"))
    (.pop parts))
  (if (not parts)
      (hy.unmangle path.stem)
      (.join "." (gfor part parts (hy.unmangle part)))))

(setv _DEFCORE-DETAIL "Hy core form")

(defn _load-core-symbols []
  (setv macros (getattr builtins "_hy_macros" {}))
  (setv symbols {})
  (for [[name obj] (.items macros)]
    (setv doc (.get CORE-DOCS name))
    (setv runtime-doc (or (inspect.getdoc obj) ""))
    (setv (get symbols name)
          (model.symbol-info name model.KIND-CORE-FORM
            :detail _DEFCORE-DETAIL
            :signature (if doc (get doc "signature") "")
            :documentation (if doc (get doc "documentation") runtime-doc)
            :runtime-object obj)))
  (for [[name doc] (.items CORE-DOCS)]
    (.setdefault symbols name
      (model.symbol-info name model.KIND-CORE-FORM
        :detail _DEFCORE-DETAIL
        :signature (get doc "signature")
        :documentation (get doc "documentation"))))
  symbols)

(defn _load-builtin-symbols []
  (setv symbols {})
  (for [[name obj] (.items (vars builtins))]
    (when (.startswith name "_")
      (continue))
    (try
      (setv signature (if (callable obj) (str (inspect.signature obj)) ""))
      (except [#(TypeError ValueError)]
        (setv signature "")))
    (setv (get symbols name)
          (model.symbol-info name model.KIND-PYTHON-BUILTIN
            :detail "Python builtin"
            :signature signature
            :documentation (or (inspect.getdoc obj) "")
            :runtime-object obj)))
  symbols)

(defn _diagnostic-from-exception [exc source code]
  (setv line (max (- (int (or (getattr exc "lineno" 1) 1)) 1) 0))
  (setv character (max (- (int (or (getattr exc "offset" 1) 1)) 1) 0))
  (setv end-line-attr (getattr exc "end_lineno" None))
  (setv end-offset-attr (getattr exc "end_offset" None))
  (setv end-line (max (- (int (or end-line-attr (+ line 1))) 1) 0))
  (setv end-character (max (- (int (or end-offset-attr (+ character 2))) 1) 0))
  (setv lines (or (.splitlines source) [source]))
  (setv line (min line (- (len lines) 1)))
  (setv end-line (min (max end-line line) (- (len lines) 1)))
  (setv character (min character (len (get lines line))))
  (setv end-character (min end-character (len (get lines end-line))))
  (when (and (= end-line line) (<= end-character character))
    (setv end-character (min (+ character 1) (len (get lines line))))
    (when (<= end-character character)
      (setv end-character (+ character 1))))
  (setv message (or (getattr exc "msg" None) (str exc)))
  (parse-diagnostic message :line line :character character
    :end-line end-line :end-character end-character :code code))

;; ---------------------------------------------------------------------------
;; Hy model helpers
;; ---------------------------------------------------------------------------

(defn _symbol-name [model-form]
  (if (isinstance model-form Symbol) (str model-form) ""))

(defn _format-model [model-form]
  (try
    (.lstrip (hy.repr model-form) "'")
    (except [Exception]
      (str model-form))))

(defn _callable-symbol-kind [head]
  (cond
    (= head "defmacro") model.KIND-LOCAL-MACRO
    (= head "defreader") model.KIND-READER-MACRO
    True model.KIND-LOCAL-FUNCTION))

(defn _callable-signature [head raw-name visible-name params]
  (if (= head "defreader")
      f"(defreader {raw-name} {params})"
      f"({visible-name} {params})"))

(defn _parameter-models [params]
  (when (not (isinstance params HyList))
    (return []))
  (setv out [])
  (for [item params]
    (cond
      (isinstance item Symbol)
        (do
          (setv name (str item))
          (when (not (in name #{"/" "*"}))
            (.append out #(name item))))
      (and (isinstance item HyList) item (isinstance (get item 0) Symbol))
        (.append out #((str (get item 0)) (get item 0)))
      (and (isinstance item Expression) (>= (len item) 2))
        (do
          (setv head (_symbol-name (get item 0)))
          (when (and (in head #{"unpack-iterable" "unpack-mapping"}) (isinstance (get item 1) Symbol))
            (.append out #((str (get item 1)) (get item 1)))))))
  out)

(defn _assignment-target-models [target]
  (cond
    (isinstance target Symbol) [#((str target) target)]
    (isinstance target HyList)
      (do
        (setv out [])
        (for [item target]
          (.extend out (_assignment-target-models item)))
        out)
    (isinstance target HyDict)
      (do
        (setv out [])
        (setv values (if (hasattr target "values") (list (.values target)) (cut (list target) 1 None 2)))
        (for [item values]
          (.extend out (_assignment-target-models item)))
        out)
    (and (isinstance target Expression) target)
      (do
        (setv head (_symbol-name (get target 0)))
        (cond
          (= head ",")
            (do
              (setv out [])
              (for [item (cut target 1 None)]
                (.extend out (_assignment-target-models item)))
              out)
          (and (in head #{"unpack-iterable" "unpack-mapping"}) (>= (len target) 2))
            (_assignment-target-models (get target 1))
          True []))
    True []))

(defn _leading-docstring [body]
  (setv first (next (iter body) None))
  (if (isinstance first String) (str first) ""))

(defn _module-name [model-form]
  (cond
    (isinstance model-form Symbol) (str model-form)
    (and (isinstance model-form Expression) model-form (= (_symbol-name (get model-form 0)) "."))
      (.join "." (gfor part (cut model-form 1 None) :if (isinstance part Symbol) (str part)))
    True ""))

(defn _is-keyword [model-form name]
  (and (isinstance model-form Keyword) (= model-form.name name)))
