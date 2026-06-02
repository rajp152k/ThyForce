"LSP stdio framing and serving helpers.

Transport is intentionally small and separate from server generation. Any code
that can provide parsed JSON-RPC dictionaries can reuse `thyforce.lsp.engine.server.dispatch`;
stdio just adds Language Server Protocol `Content-Length` framing.
"

(import json)
(import thyforce.lsp.engine.jsonrpc [error-response PARSE-ERROR dump-message])
(import thyforce.lsp.engine.server [dispatch])

(defn encode-message [message]
  "Encode a JSON-RPC message as an LSP Content-Length frame."
  (setv payload (.encode (dump-message message) "utf-8"))
  (setv header (.encode (.format "Content-Length: {}\r\n\r\n" (len payload)) "ascii"))
  (+ header payload))

(defn _content-length [headers]
  (setv content-length None)
  (for [line headers]
    (when (in ":" line)
      (setv [key value] (.split line ":" 1))
      (when (= (.lower (.strip key)) "content-length")
        (setv content-length (int (.strip value))))))
  content-length)

(defn decode-frame [frame]
  "Decode one complete LSP Content-Length frame into a message dictionary."
  (setv separator b"\r\n\r\n")
  (setv header-end (.find frame separator))
  (when (= header-end -1)
    (raise (ValueError "missing LSP header separator")))
  (setv header (.decode (cut frame 0 header-end) "ascii"))
  (setv content-length (_content-length (.split header "\r\n")))
  (when (is content-length None)
    (raise (ValueError "missing Content-Length header")))
  (setv body-start (+ header-end (len separator)))
  (setv body (cut frame body-start (+ body-start content-length)))
  (when (!= (len body) content-length)
    (raise (ValueError "incomplete LSP frame body")))
  (json.loads (.decode body "utf-8")))

(defn read-message [stream]
  "Read one Content-Length-framed JSON-RPC message from a binary stream."
  (setv headers [])
  (while True
    (setv line (.readline stream))
    (when (= line b"")
      (return None))
    (when (in line [b"\r\n" b"\n"])
      (break))
    (.append headers (.rstrip (.decode line "ascii") "\r\n")))
  (setv content-length (_content-length headers))
  (when (is content-length None)
    (raise (ValueError "missing Content-Length header")))
  (setv body (.read stream content-length))
  (when (!= (len body) content-length)
    (raise (ValueError "incomplete LSP frame body")))
  (json.loads (.decode body "utf-8")))

(defn write-message [stream message]
  "Write one Content-Length-framed JSON-RPC message to a binary stream."
  (.write stream (encode-message message))
  (.flush stream))

(defn serve [server input-stream output-stream]
  "Serve a generated server over binary input/output streams until EOF.

Returns the final server map, which is useful for tests and embedded transports.
Malformed frames produce JSON-RPC parse-error responses and the loop continues
until the input stream is exhausted.
  "
  (setv current server)
  (while True
    (try
      (setv message (read-message input-stream))
      (except [exc Exception]
        (write-message
          output-stream
          (error-response None PARSE-ERROR "parse error" {"exception" (getattr (type exc) "__name__")}))
        (continue)))
    (when (is message None)
      (break))
    (setv result (dispatch current message))
    (setv current (get result "server"))
    (for [outbound (get result "messages")]
      (write-message output-stream outbound)))
  current)
