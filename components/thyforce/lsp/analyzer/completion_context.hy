"Lightweight completion-context detection for incomplete Hy forms.

Hy's reader is the source of truth for complete forms, but completion often runs
while a form is incomplete. This scanner recognizes only enough structure to tell
whether the cursor sits in an import/require module slot or inside a member/macro
list. The result is a map {\"kind\" str \"module\" (or str None)}.
"

(setv _DELIMITERS (set "()[]{}"))
(setv _REQUIRE-SELECTORS #{":macros" ":readers"})

(defn ctx [kind [module None]]
  {"kind" kind "module" module})

(defn completion-context [source line character]
  "Return import/require-specific completion context at an LSP position."
  (setv prefix (_enclosing-form-prefix source line character))
  (when (is prefix None)
    (return (ctx "default")))
  (setv tokens (_tokenize prefix))
  (when (not tokens)
    (return (ctx "default")))
  (setv head (get (get tokens 0) "text"))
  (when (not (in head #{"import" "require"}))
    (return (ctx "default")))
  (setv square-index (_innermost-open-square tokens))
  (if (= head "import")
      (cond
        (is-not square-index None) (ctx "import-member" (_nearest-module-before tokens square-index))
        (= (_previous-token tokens) ":as") (ctx "default")
        True (ctx "import-module"))
      (do
        (when (is-not square-index None)
          (setv selector (if (> square-index 0) (get (get tokens (- square-index 1)) "text") ""))
          (setv module (_nearest-module-before tokens square-index))
          (return (if (= selector ":readers")
                      (ctx "require-reader" module)
                      (ctx "require-macro" module))))
        (setv previous (_previous-token tokens))
        (cond
          (= previous ":as") (ctx "default")
          (= previous ":readers") (ctx "require-reader" (_nearest-module-before tokens (len tokens)))
          (= previous ":macros") (ctx "require-macro" (_nearest-module-before tokens (len tokens)))
          True (ctx "require-module")))))

(defn _enclosing-form-prefix [source line character]
  (setv lines (.splitlines source :keepends True))
  (when (not (<= 0 line (- (len lines) 1)))
    (return None))
  (setv offset (+ (sum (gfor i (range line) (len (get lines i))))
                  (min character (len (get lines line)))))
  (setv stack [])
  (setv in-string False)
  (setv escape False)
  (setv in-comment False)
  (setv i 0)
  (while (< i offset)
    (setv ch (get source i))
    (cond
      in-comment (when (= ch "\n") (setv in-comment False))
      in-string
        (cond
          escape (setv escape False)
          (= ch "\\") (setv escape True)
          (= ch "\"") (setv in-string False))
      (= ch ";") (setv in-comment True)
      (= ch "\"") (setv in-string True)
      (= ch "(") (.append stack i)
      (and (= ch ")") stack) (.pop stack))
    (+= i 1))
  (if (not stack)
      None
      (cut source (+ (get stack -1) 1) offset)))

(defn _tokenize [text]
  (setv tokens [])
  (setv i 0)
  (setv n (len text))
  (while (< i n)
    (setv ch (get text i))
    (cond
      (.isspace ch) (+= i 1)
      (= ch ";")
        (do
          (setv newline (.find text "\n" i))
          (if (= newline -1)
              (setv i n)
              (setv i (+ newline 1))))
      (= ch "\"")
        (do
          (setv start i)
          (+= i 1)
          (setv escape False)
          (while (< i n)
            (cond
              escape (setv escape False)
              (= (get text i) "\\") (setv escape True)
              (= (get text i) "\"") (do (+= i 1) (break)))
            (+= i 1))
          (.append tokens {"text" (cut text start i) "start" start "end" i}))
      (in ch _DELIMITERS)
        (do
          (.append tokens {"text" ch "start" i "end" (+ i 1)})
          (+= i 1))
      True
        (do
          (setv start i)
          (while (< i n)
            (setv ch (get text i))
            (when (or (.isspace ch) (= ch ";") (in ch _DELIMITERS) (= ch "\""))
              (break))
            (+= i 1))
          (.append tokens {"text" (cut text start i) "start" start "end" i}))))
  tokens)

(defn _innermost-open-square [tokens]
  (setv stack [])
  (for [[index token] (enumerate tokens)]
    (cond
      (= (get token "text") "[") (.append stack index)
      (and (= (get token "text") "]") stack) (.pop stack)))
  (if stack (get stack -1) None))

(defn _nearest-module-before [tokens index]
  "Find the most plausible module token before INDEX."
  (setv depth 0)
  (setv skip-alias False)
  (for [i (range (- index 1) 0 -1)]
    (setv text (get (get tokens i) "text"))
    (cond
      (= text "]") (do (+= depth 1) (continue))
      (and (= text "[") depth) (do (-= depth 1) (continue))
      depth (continue)
      (or (in text _DELIMITERS) (= text "*") (in text _REQUIRE-SELECTORS)) (continue)
      (= text ":as") (do (setv skip-alias True) (continue))
      skip-alias (do (setv skip-alias False) (continue))
      (.startswith text ":") (continue)
      True (return text)))
  None)

(defn _previous-token [tokens]
  (for [token (reversed tokens)]
    (when (not (in (get token "text") _DELIMITERS))
      (return (get token "text"))))
  "")
