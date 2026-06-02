"Word extraction utilities for Hy source."

(import re)

;; Hy symbols include many operator characters. Keep this conservative enough to
;; avoid swallowing delimiters but broad enough for normal Hy identifiers.
(setv WORD-RE (re.compile #[[[#\+\-.?!><$/*%=@^&|~:\\\w]+]]))

(defn line-word-prefix [line character]
  "Return the symbol prefix ending at CHARACTER on LINE."
  (setv character (max 0 (min character (len line))))
  (for [match (.finditer WORD-RE line)]
    (when (<= (.start match) character (.end match))
      (return (cut line (.start match) character))))
  "")

(defn line-word-range-at [line character]
  "Return the (start end) tuple of the symbol under CHARACTER, or None."
  (setv character (max 0 (min character (len line))))
  (for [match (.finditer WORD-RE line)]
    (when (<= (.start match) character (.end match))
      (return #((.start match) (.end match)))))
  None)

(defn line-word-at [line character]
  "Return the full symbol under CHARACTER on LINE."
  (setv found (line-word-range-at line character))
  (if (is found None)
      ""
      (cut line (get found 0) (get found 1))))

(defn word-prefix [source line character]
  (setv lines (.splitlines source))
  (if (<= 0 line (- (len lines) 1))
      (line-word-prefix (get lines line) character)
      ""))

(defn word-at [source line character]
  (setv lines (.splitlines source))
  (if (<= 0 line (- (len lines) 1))
      (line-word-at (get lines line) character)
      ""))

(defn word-range-at [source line character]
  (setv lines (.splitlines source))
  (if (<= 0 line (- (len lines) 1))
      (line-word-range-at (get lines line) character)
      None))

(defn occurrences [source name]
  "Return (line start end) tuples for each occurrence of NAME as a Hy word."
  (when (not name)
    (return []))
  (setv out [])
  (for [[line-no line] (enumerate (.splitlines source))]
    (for [match (.finditer WORD-RE line)]
      (when (= (.group match 0) name)
        (.append out #(line-no (.start match) (.end match))))))
  out)

(defn _active-parameter [args]
  (setv depth 0 active 0 in-token False in-string False escape False)
  (for [ch args]
    (cond
      in-string
        (do
          (cond
            escape (setv escape False)
            (= ch "\\") (setv escape True)
            (= ch "\"") (setv in-string False))
          (continue))
      (= ch "\"") (do (setv in-string True) (setv in-token True))
      (in ch "([{") (do (+= depth 1) (setv in-token True))
      (in ch ")]}") (do (setv depth (max (- depth 1) 0)) (setv in-token True))
      (and (= depth 0) (.isspace ch))
        (when in-token (+= active 1) (setv in-token False))
      (not (.isspace ch)) (setv in-token True)))
  active)

(defn enclosing-call [source line character]
  "Return (callee active-parameter) for the nearest open call, or None.

This is intentionally lightweight. Hy's reader remains the source of truth for
indexing; signature help just needs a useful local guess while the user is
editing incomplete forms.
  "
  (setv lines (.splitlines source :keepends True))
  (when (not (<= 0 line (- (len lines) 1)))
    (return None))
  (setv offset (+ (sum (gfor i (range line) (len (get lines i))))
                  (min character (len (get lines line)))))
  (setv prefix (cut source 0 offset))
  (setv depth 0)
  (setv start -1)
  (for [i (range (- (len prefix) 1) -1 -1)]
    (setv ch (get prefix i))
    (cond
      (= ch ")") (+= depth 1)
      (= ch "(") (if (= depth 0)
                     (do (setv start i) (break))
                     (-= depth 1))))
  (when (< start 0)
    (return None))
  (setv after (cut prefix (+ start 1) None))
  (setv match (.search WORD-RE after))
  (when (not match)
    (return None))
  (setv callee (.group match 0))
  (setv args (cut after (.end match) None))
  #(callee (_active-parameter args)))
