"Core data model: symbol-info maps, source ranges, and kind predicates."
(import thyforce.spec.core :as spec)
(require thyforce.spec.core [genspec])


(setv KIND-CORE-FORM "core-form")
(setv KIND-PYTHON-BUILTIN "python-builtin")
(setv KIND-LOCAL-FUNCTION "local-function")
(setv KIND-LOCAL-MACRO "local-macro")
(setv KIND-READER-MACRO "reader-macro")
(setv KIND-LOCAL-CLASS "local-class")
(setv KIND-LOCAL-VARIABLE "local-variable")
(setv KIND-PARAMETER "parameter")
(setv KIND-MODULE "module")
(setv KIND-UNKNOWN "unknown")

(setv KINDS
  #{KIND-CORE-FORM KIND-PYTHON-BUILTIN KIND-LOCAL-FUNCTION KIND-LOCAL-MACRO
    KIND-READER-MACRO KIND-LOCAL-CLASS KIND-LOCAL-VARIABLE KIND-PARAMETER
    KIND-MODULE KIND-UNKNOWN})

(defn kind? [value]
  "True when `value` is a known symbol-kind string."
  (and (spec.str? value) (in value KINDS)))


(defn position [line character]
  "Build a zero-based source position map."
  {"line" line "character" character})

(defn source-range [uri start-line start-character end-line end-character]
  "Build a source range map carrying its document URI."
  {"uri" uri
   "range" {"start" (position start-line start-character)
            "end" (position end-line end-character)}})

(defn from-hy-model [uri model]
  "Build a source range from a Hy model's 1-based position attributes."
  (setv start-line (max (- (getattr model "start_line" 1) 1) 0))
  (setv start-character (max (- (getattr model "start_column" 1) 1) 0))
  (setv end-line (max (- (getattr model "end_line" (getattr model "start_line" 1)) 1) 0))
  (setv end-character (max (getattr model "end_column" (getattr model "start_column" 1)) 0))
  (source-range uri start-line start-character end-line end-character))


(setv source-range?
  (genspec {"uri" spec.str?
            "range" {"start" {"line" spec.int? "character" spec.int?}
                     "end" {"line" spec.int? "character" spec.int?}}}))


(defn symbol-info [name kind [detail ""] [documentation ""] [signature ""]
                   [source None] [module ""] [runtime-object None]]
  "Build a symbol-info map; source is a source-range map or None."
  {"name" name
   "kind" kind
   "detail" detail
   "documentation" documentation
   "signature" signature
   "source" source
   "module" module
   "runtime-object" runtime-object})

(defn hover-text [symbol]
  "Render Markdown-ish hover text for a symbol-info map."
  (setv name (get symbol "name"))
  (setv signature (.get symbol "signature" ""))
  (setv detail (.get symbol "detail" ""))
  (setv documentation (.get symbol "documentation" ""))
  (setv header (if signature f"{name} {signature}" name))
  (when detail
    (setv header f"{header}\n[{detail}]"))
  (setv parts [header])
  (when documentation
    (.append parts documentation))
  (.join "\n\n" parts))

(setv symbol-info?
  (spec.and-spec
    (spec.key-pred "name" spec.str?)
    (spec.key-pred "kind" kind?)
    (spec.key-pred "detail" spec.str?)
    (spec.key-pred "documentation" spec.str?)
    (spec.key-pred "signature" spec.str?)
    (spec.key-pred "source" (spec.maybe source-range?))
    (spec.key-pred "module" spec.str?)))
