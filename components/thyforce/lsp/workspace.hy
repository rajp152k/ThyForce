"Generic immutable-ish workspace/document state helpers.

The helpers here are deliberately framework-level and language-agnostic. They
store LSP text documents as plain dictionaries under the `documents` state key and
return replacement state maps instead of mutating the caller's state in place.
"

(setv POSITION-ENCODING-UTF8 "utf-8")
(setv POSITION-ENCODING-UTF16 "utf-16")
(setv POSITION-ENCODING-UTF32 "utf-32")

(defn _documents [state]
  (dict (.get (or state {}) "documents" {})))

(defn with-document [state document]
  "Return state with `document` stored by URI."
  (setv next-state (dict (or state {})))
  (setv docs (_documents state))
  (setv (get docs (get document "uri")) document)
  (setv (get next-state "documents") docs)
  next-state)

(defn without-document [state uri]
  "Return state with a URI removed from the document table."
  (setv next-state (dict (or state {})))
  (setv docs (_documents state))
  (when (in uri docs)
    (del (get docs uri)))
  (setv (get next-state "documents") docs)
  next-state)

(defn get-document [state uri [default None]]
  "Look up a document map from workspace state."
  (.get (.get (or state {}) "documents" {}) uri default))

(defn document [uri text [language-id None] [version None]]
  "Build a generic text document map."
  (setv out {"uri" uri "text" text})
  (when (is-not language-id None)
    (setv (get out "languageId") language-id))
  (when (is-not version None)
    (setv (get out "version") version))
  out)

(defn open-document [state params]
  "Apply textDocument/didOpen params to state."
  (setv text-document (get params "textDocument"))
  (with-document
    state
    (document
      (get text-document "uri")
      (get text-document "text")
      (.get text-document "languageId")
      (.get text-document "version"))))

(defn close-document [state params]
  "Apply textDocument/didClose params to state."
  (without-document state (get (get params "textDocument") "uri")))

(defn _line-content [line-text]
  (cond
    (.endswith line-text "\r\n") (cut line-text 0 -2)
    (.endswith line-text "\n") (cut line-text 0 -1)
    (.endswith line-text "\r") (cut line-text 0 -1)
    True line-text))

(defn _char-width [ch encoding]
  (cond
    (= encoding POSITION-ENCODING-UTF16) (// (len (.encode ch "utf-16-le")) 2)
    (= encoding POSITION-ENCODING-UTF8) (len (.encode ch "utf-8"))
    (in encoding [POSITION-ENCODING-UTF32 "codepoint" "python"]) 1
    True (raise (ValueError (.format "unsupported position encoding: {}" encoding)))))

(defn encoded-length [text [encoding POSITION-ENCODING-UTF16]]
  "Return the LSP character length of text in a position encoding."
  (setv units 0)
  (for [ch text]
    (setv units (+ units (_char-width ch encoding))))
  units)

(defn _character-to-index [line-text character encoding]
  (setv target (max 0 (int character)))
  (setv units 0)
  (setv index 0)
  (for [ch line-text]
    (when (>= units target)
      (return index))
    (setv units (+ units (_char-width ch encoding)))
    (setv index (+ index 1)))
  index)

(defn position-to-offset [text position [encoding POSITION-ENCODING-UTF16]]
  "Convert a line/character position to a Python string offset.

`encoding` may be `utf-16`, `utf-8`, `utf-32`, `codepoint`, or `python`. LSP
clients default to UTF-16 unless `positionEncoding` is negotiated.
  "
  (setv target-line (max 0 (int (.get position "line" 0))))
  (setv target-char (max 0 (int (.get position "character" 0))))
  (setv offset 0)
  (setv lines (.splitlines text True))
  (when (and (= target-line 0) (= (len lines) 0))
    (return 0))
  (for [[index line-text] (enumerate lines)]
    (if (< index target-line)
        (setv offset (+ offset (len line-text)))
        (return (+ offset (_character-to-index (_line-content line-text) target-char encoding)))))
  (len text))

(defn offset-to-position [text offset [encoding POSITION-ENCODING-UTF16]]
  "Convert a Python string offset to an LSP-like position map."
  (setv safe-offset (min (max 0 (int offset)) (len text)))
  (setv before (cut text 0 safe-offset))
  (setv line (.count before "\n"))
  (setv last-newline (.rfind before "\n"))
  (setv line-start (if (= last-newline -1) 0 (+ last-newline 1)))
  (setv line-text (cut text line-start safe-offset))
  {"line" line "character" (encoded-length line-text encoding)})

(defn apply-text-change [text change [encoding POSITION-ENCODING-UTF16]]
  "Apply one LSP content change to text.

Full-document changes are represented by a change with no `range`; incremental
changes use `range.start` and `range.end` positions.
  "
  (when (not (in "range" change))
    (return (get change "text")))
  (setv change-range (get change "range"))
  (setv start (position-to-offset text (get change-range "start") encoding))
  (setv end (position-to-offset text (get change-range "end") encoding))
  (+ (cut text 0 start) (get change "text") (cut text end None)))

(defn apply-text-changes [text changes [encoding POSITION-ENCODING-UTF16]]
  "Apply a sequence of content changes in order."
  (setv out text)
  (for [change changes]
    (setv out (apply-text-change out change encoding)))
  out)

(defn change-document [state params [encoding POSITION-ENCODING-UTF16]]
  "Apply textDocument/didChange params to state."
  (setv text-document (get params "textDocument"))
  (setv uri (get text-document "uri"))
  (setv current (get-document state uri))
  (when (is current None)
    (raise (KeyError (.format "document is not open: {}" uri))))
  (setv next-document (dict current))
  (setv (get next-document "text") (apply-text-changes (get current "text") (get params "contentChanges") encoding))
  (when (in "version" text-document)
    (setv (get next-document "version") (get text-document "version")))
  (with-document state next-document))
