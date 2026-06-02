"Filesystem-path / file URI conversion.

A small, dependency-free replacement for pygls.uris covering the file scheme on
POSIX-style paths. Symbols carry file:// URIs in their source locations, so this
lives with analysis rather than in the protocol engine.
"

(import pathlib [Path])
(import urllib.parse [urlparse unquote :as url-unquote])
(import urllib.request [url2pathname pathname2url])

(defn from-fs-path [path]
  "Convert a filesystem path to an absolute file:// URI."
  (.as-uri (.resolve (Path path))))

(defn to-fs-path [uri]
  "Convert a file:// URI back to a filesystem path."
  (setv parsed (urlparse uri))
  (url2pathname (url-unquote parsed.path)))
