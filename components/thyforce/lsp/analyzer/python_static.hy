"Side-effect-free Python source indexing for workspace modules."

(import ast)
(import hy)
(import pathlib [Path])
(import thyforce.lsp.analyzer.model :as model)
(import thyforce.lsp.analyzer.uri :as uri)

(defn static-module [module path [documentation ""] [symbols None] [re-exports None]]
  {"module" module "path" path "documentation" documentation
   "symbols" symbols "re-exports" re-exports})

(defn _python-qualified-name [name]
  (.join "." (gfor part (.split name ".") (if part (hy.mangle part) part))))

(defn find-python-module-path [roots module-name]
  "Find a .pyi/.py module file for MODULE-NAME under one or more ROOTS."
  (setv python-module (_python-qualified-name module-name))
  (setv search-roots (if (isinstance roots Path) [roots] (list roots)))
  (for [root search-roots]
    (setv module-path (.joinpath root #* (.split python-module ".")))
    (setv candidates [(.with-suffix module-path ".pyi")
                      (/ module-path "__init__.pyi")
                      (.with-suffix module-path ".py")
                      (/ module-path "__init__.py")])
    (for [candidate candidates]
      (when (and (.exists candidate) (.is-file candidate))
        (return (.resolve candidate)))))
  None)

(defn load-static-python-module [roots module-name]
  "Parse a Python module from ROOTS without importing it, or None."
  (setv path (find-python-module-path roots module-name))
  (when (is path None)
    (return None))
  (try
    (setv source (.read-text path :encoding "utf-8"))
    (setv tree (ast.parse source :filename (str path)))
    (except [#(OSError SyntaxError UnicodeDecodeError)]
      (return None)))
  (setv [symbols re-exports] (_module-symbols-and-re-exports path module-name tree))
  (setv documentation (or (ast.get-docstring tree) ""))
  (setv companion-tree (_parse-companion-implementation path))
  (when (is-not companion-tree None)
    (setv [companion-symbols companion-re-exports]
          (_module-symbols-and-re-exports (.with-suffix path ".py") module-name companion-tree))
    (setv documentation (or documentation (ast.get-docstring companion-tree) ""))
    (setv symbols (_merge-symbol-docs symbols companion-symbols))
    (setv re-exports {#** companion-re-exports #** re-exports}))
  (static-module module-name path documentation symbols re-exports))

(defn _module-symbols-and-re-exports [path module-name tree]
  (setv symbols {})
  (setv re-exports {})
  (setv uri-str (uri.from-fs-path (str (.resolve path))))
  (setv is-package (= path.stem "__init__"))
  (for [node tree.body]
    (for [symbol (_symbols-from-node uri-str module-name node is-package)]
      (setv (get symbols (get symbol "name")) symbol))
    (.update re-exports (_re-exports-from-node module-name node is-package)))
  [symbols re-exports])

(defn _parse-companion-implementation [path]
  (when (!= path.suffix ".pyi")
    (return None))
  (setv companion (.with-suffix path ".py"))
  (when (not (.exists companion))
    (return None))
  (try
    (ast.parse (.read-text companion :encoding "utf-8") :filename (str companion))
    (except [#(OSError SyntaxError UnicodeDecodeError)]
      None)))

(defn _merge-symbol-docs [primary docs]
  (setv merged (dict primary))
  (for [[name doc-symbol] (.items docs)]
    (setv existing (.get merged name))
    (cond
      (is existing None) (setv (get merged name) doc-symbol)
      (and (not (get existing "documentation")) (get doc-symbol "documentation"))
        (setv (get merged name) (_replace-symbol-documentation existing (get doc-symbol "documentation")))))
  merged)


(defn module-symbol [root visible-name module-name]
  (setv module (load-static-python-module root module-name))
  (if (is module None) None (module-symbol-from-static-module module visible-name)))

(defn module-symbol-from-static-module [module visible-name]
  (setv mod (get module "module"))
  (model.symbol-info visible-name model.KIND-MODULE
    :detail f"Python module {mod} (static)"
    :documentation (or (get module "documentation") f"Python module `{mod}`.")
    :source (_range-for-path (get module "path"))
    :module mod))

(defn member-symbol [root visible-name module-name member-name]
  (setv module (load-static-python-module root module-name))
  (if (is module None) None (member-symbol-from-static-module module visible-name member-name)))

(defn member-symbol-from-static-module [module visible-name member-name]
  (when (is (get module "symbols") None)
    (return None))
  (setv symbols (get module "symbols"))
  (setv symbol (or (.get symbols member-name)
                   (.get symbols (hy.unmangle (hy.mangle member-name)))))
  (if (is symbol None) None (_with-visible-name symbol visible-name)))

(defn member-symbols-from-static-module [module [prefix ""] [visible-base ""]]
  (when (is (get module "symbols") None)
    (return []))
  (setv out [])
  (for [symbol (.values (get module "symbols"))]
    (setv sym-name (get symbol "name"))
    (when (.startswith sym-name prefix)
      (setv visible (if visible-base f"{visible-base}.{sym-name}" sym-name))
      (.append out (_with-visible-name symbol visible))))
  (sorted out :key (fn [symbol] (get symbol "name"))))


(defn _symbols-from-node [uri-str module-name node [is-package False]]
  (cond
    (isinstance node #(ast.FunctionDef ast.AsyncFunctionDef))
      (do
        (setv name (hy.unmangle node.name))
        [(model.symbol-info name model.KIND-LOCAL-FUNCTION
           :detail f"Python function {module-name}.{node.name} (static)"
           :signature f"({name}{(_format-arguments node.args)}{(_format-returns node)})"
           :documentation (or (ast.get-docstring node) "")
           :source (_range-for-node uri-str node)
           :module module-name)])
    (isinstance node ast.ClassDef)
      (do
        (setv name (hy.unmangle node.name))
        (setv bases (.join ", " (gfor base node.bases (_unparse base))))
        (setv signature (if bases f"class {name}({bases})" f"class {name}"))
        [(model.symbol-info name model.KIND-LOCAL-CLASS
           :detail f"Python class {module-name}.{node.name} (static)"
           :signature signature
           :documentation (or (ast.get-docstring node) "")
           :source (_range-for-node uri-str node)
           :module module-name)])
    (isinstance node ast.Assign)
      (do
        (setv out [])
        (for [target node.targets]
          (setv symbol (_symbol-from-assignment-target uri-str module-name target))
          (when (is-not symbol None)
            (.append out symbol)))
        out)
    (isinstance node ast.AnnAssign)
      (do
        (setv symbol (_symbol-from-assignment-target uri-str module-name node.target node.annotation))
        (if (is symbol None) [] [symbol]))
    (isinstance node ast.Import)
      (lfor alias node.names (_symbol-from-import-alias uri-str module-name node alias))
    (isinstance node ast.ImportFrom)
      (do
        (setv from-module (_absolute-import-from-module module-name node is-package))
        (lfor alias node.names :if (!= alias.name "*")
          (_symbol-from-import-alias uri-str module-name node alias from-module)))
    True []))

(defn _re-exports-from-node [module-name node [is-package False]]
  (when (not (isinstance node ast.ImportFrom))
    (return {}))
  (setv from-module (_absolute-import-from-module module-name node is-package))
  (when (not from-module)
    (return {}))
  (setv out {})
  (for [alias node.names]
    (when (!= alias.name "*")
      (setv visible (or alias.asname alias.name))
      (setv (get out (hy.unmangle visible)) #(from-module (hy.unmangle alias.name)))))
  out)

(defn _absolute-import-from-module [module-name node [is-package False]]
  (when (= node.level 0)
    (return node.module))
  (setv parts (.split module-name "."))
  (setv base (if is-package parts (cut parts 0 -1)))
  (when (> node.level 1)
    (setv base (if (<= (- node.level 1) (len base)) (cut base 0 (- (- node.level 1))) [])))
  (when node.module
    (setv base [#* base #* (.split node.module ".")]))
  (.join "." (gfor part base :if part part)))

(defn _symbol-from-import-alias [uri-str module-name node alias [from-module None]]
  (setv visible (or alias.asname (get (.split alias.name "." 1) 0)))
  (setv hy-name (hy.unmangle visible))
  (setv imported (if from-module f"{from-module}.{alias.name}" alias.name))
  (model.symbol-info hy-name model.KIND-UNKNOWN
    :detail f"Python import {imported} (static)"
    :documentation f"Imported `{imported}` in `{module-name}`."
    :source (_range-for-node uri-str node)
    :module module-name))

(defn _symbol-from-assignment-target [uri-str module-name target [annotation None]]
  (when (not (isinstance target ast.Name))
    (return None))
  (setv name (hy.unmangle target.id))
  (setv detail f"Python variable {module-name}.{target.id} (static)")
  (when (is-not annotation None)
    (setv detail f"{detail}: {(_unparse annotation)}"))
  (model.symbol-info name model.KIND-LOCAL-VARIABLE
    :detail detail
    :source (_range-for-node uri-str target)
    :module module-name))


(defn _format-arguments [args]
  (setv positional [#* args.posonlyargs #* args.args])
  (setv defaults (+ (* [None] (- (len positional) (len args.defaults))) (list args.defaults)))
  (setv parts (lfor [arg default] (zip positional defaults) (_format-arg arg default)))
  (when args.posonlyargs
    (.insert parts (len args.posonlyargs) "/"))
  (cond
    (is-not args.vararg None) (.append parts (+ "*" (_format-arg args.vararg None)))
    args.kwonlyargs (.append parts "*"))
  (.extend parts (lfor [arg default] (zip args.kwonlyargs args.kw-defaults) (_format-arg arg default)))
  (when (is-not args.kwarg None)
    (.append parts (+ "**" (_format-arg args.kwarg None))))
  (if (not parts) "" (+ " " (.join ", " parts))))

(defn _format-arg [arg default]
  (setv text arg.arg)
  (when (is-not arg.annotation None)
    (setv text f"{text}: {(_unparse arg.annotation)}"))
  (when (is-not default None)
    (setv text f"{text}={(_unparse default)}"))
  text)

(defn _format-returns [node]
  (if (is-not node.returns None) f" -> {(_unparse node.returns)}" ""))

(defn _unparse [node]
  (try
    (ast.unparse node)
    (except [Exception]
      "...")))


(defn _range-for-node [uri-str node]
  (setv start-line (max (- (getattr node "lineno" 1) 1) 0))
  (setv start-character (max (getattr node "col_offset" 0) 0))
  (setv end-line (max (- (getattr node "end_lineno" (getattr node "lineno" 1)) 1) 0))
  (setv end-character (max (getattr node "end_col_offset" (+ start-character 1)) 0))
  (model.source-range uri-str start-line start-character end-line end-character))

(defn _range-for-path [path]
  (model.source-range (uri.from-fs-path (str (.resolve path))) 0 0 0 0))

(defn _with-visible-name [symbol visible-name]
  (setv out (dict symbol))
  (setv (get out "name") visible-name)
  out)

(defn _replace-symbol-documentation [symbol documentation]
  (setv out (dict symbol))
  (setv (get out "documentation") documentation)
  out)
