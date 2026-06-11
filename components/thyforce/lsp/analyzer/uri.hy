"Filesystem-path / file URI conversion for the file:// scheme."

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
