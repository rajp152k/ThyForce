"""Small JSON-RPC 2.0 message constructors used by the LSP engine."""

(import json)

(setv PARSE-ERROR -32700)
(setv INVALID-REQUEST -32600)
(setv METHOD-NOT-FOUND -32601)
(setv INVALID-PARAMS -32602)
(setv INTERNAL-ERROR -32603)

(defn response [id result]
  "Build a successful JSON-RPC response."
  {"jsonrpc" "2.0" "id" id "result" result})

(defn error-response [id code message [data None]]
  "Build an error JSON-RPC response."
  (setv error {"code" code "message" message})
  (when (is-not data None)
    (setv (get error "data") data))
  {"jsonrpc" "2.0" "id" id "error" error})

(defn notification [method [params None]]
  "Build a JSON-RPC notification."
  (setv out {"jsonrpc" "2.0" "method" method})
  (when (is-not params None)
    (setv (get out "params") params))
  out)

(defn request [id method [params None]]
  "Build a JSON-RPC request."
  (setv out {"jsonrpc" "2.0" "id" id "method" method})
  (when (is-not params None)
    (setv (get out "params") params))
  out)

(defn parse-message [payload]
  "Parse a JSON-RPC payload from bytes or text."
  (setv text (if (isinstance payload bytes) (.decode payload "utf-8") payload))
  (json.loads text))

(defn dump-message [message]
  "Serialize a JSON-RPC message with compact separators."
  (json.dumps message :separators ["," ":"]))
