"Small Language Server Protocol data helpers.

The engine intentionally keeps protocol objects as dictionaries. These helpers
cover common shapes without forcing a generated type layer on framework users.
"

(import thyforce.lsp.engine.jsonrpc [notification])

(setv TEXT-DOCUMENT-SYNC-NONE 0)
(setv TEXT-DOCUMENT-SYNC-FULL 1)
(setv TEXT-DOCUMENT-SYNC-INCREMENTAL 2)

(setv MESSAGE-TYPE-ERROR 1)
(setv MESSAGE-TYPE-WARNING 2)
(setv MESSAGE-TYPE-INFO 3)
(setv MESSAGE-TYPE-LOG 4)

(setv DIAGNOSTIC-SEVERITY-ERROR 1)
(setv DIAGNOSTIC-SEVERITY-WARNING 2)
(setv DIAGNOSTIC-SEVERITY-INFORMATION 3)
(setv DIAGNOSTIC-SEVERITY-HINT 4)

(setv POSITION-ENCODING-UTF8 "utf-8")
(setv POSITION-ENCODING-UTF16 "utf-16")
(setv POSITION-ENCODING-UTF32 "utf-32")

(defn position-encoding-capability [[encoding POSITION-ENCODING-UTF16]]
  "Build the server capability fragment for negotiated position encoding."
  {"positionEncoding" encoding})

(defn position [line character]
  "Build an LSP Position map."
  {"line" line "character" character})

(defn range [start-line start-character end-line end-character]
  "Build an LSP Range map."
  {"start" (position start-line start-character)
   "end" (position end-line end-character)})

(defn text-document-sync [[open-close True] [change TEXT-DOCUMENT-SYNC-INCREMENTAL] [save None]]
  "Build a common textDocumentSync capability fragment."
  (setv out {"openClose" open-close "change" change})
  (when (is-not save None)
    (setv (get out "save") save))
  out)

(defn completion-options [[trigger-characters None] [resolve-provider False]]
  "Build CompletionOptions as plain data."
  (setv out {"resolveProvider" resolve-provider})
  (when (is-not trigger-characters None)
    (setv (get out "triggerCharacters") trigger-characters))
  out)

(defn diagnostic [message range [severity DIAGNOSTIC-SEVERITY-WARNING] [source "thyforce"] [code None] [data None]]
  "Build a Diagnostic map."
  (setv out {"range" range
             "severity" severity
             "source" source
             "message" message})
  (when (is-not code None)
    (setv (get out "code") code))
  (when (is-not data None)
    (setv (get out "data") data))
  out)

(defn publish-diagnostics [uri diagnostics [version None]]
  "Build a textDocument/publishDiagnostics notification."
  (setv params {"uri" uri "diagnostics" diagnostics})
  (when (is-not version None)
    (setv (get params "version") version))
  (notification "textDocument/publishDiagnostics" params))

(defn show-message [message [type MESSAGE-TYPE-INFO]]
  "Build a window/showMessage notification."
  (notification "window/showMessage" {"type" type "message" message}))

(defn log-message [message [type MESSAGE-TYPE-LOG]]
  "Build a window/logMessage notification."
  (notification "window/logMessage" {"type" type "message" message}))
