"Folding range support for Hy source.

Folding deliberately does not call Hy's reader: editors ask for folding while
buffers are incomplete, and a reader error should not disable structural folding
for the rest of the file. A fold range is a plain map with zero-based
start-line / start-character / end-line / end-character keys.
"

(setv _OPEN-TO-CLOSE {"(" ")" "[" "]" "{" "}"})
(setv _CLOSE-TO-OPEN (dfor [k v] (.items _OPEN-TO-CLOSE) v k))

(defn fold-range [start-line start-character end-line end-character]
  {"start-line" start-line "start-character" start-character
   "end-line" end-line "end-character" end-character})

(defn folding-ranges [source]
  "Return foldable multi-line delimiter ranges, sorted by position."
  (setv ranges [])
  (setv stack [])
  (setv line 0)
  (setv character 0)
  (setv in-string False)
  (setv escape False)
  (setv in-comment False)
  (for [ch source]
    (cond
      in-comment
        (do
          (if (= ch "\n")
              (do (setv in-comment False) (+= line 1) (setv character 0))
              (+= character 1))
          (continue))
      in-string
        (do
          (cond
            escape (setv escape False)
            (= ch "\\") (setv escape True)
            (= ch "\"") (setv in-string False))
          (if (= ch "\n")
              (do (+= line 1) (setv character 0))
              (+= character 1))
          (continue))
      (= ch ";") (do (setv in-comment True) (+= character 1) (continue))
      (= ch "\"") (do (setv in-string True) (+= character 1) (continue)))
    (cond
      (in ch _OPEN-TO-CLOSE) (.append stack #(ch line character))
      (in ch _CLOSE-TO-OPEN)
        (when (and stack (= (get (get stack -1) 0) (get _CLOSE-TO-OPEN ch)))
          (setv popped (.pop stack))
          (setv start-line (get popped 1))
          (setv start-character (get popped 2))
          (when (> line start-line)
            (.append ranges (fold-range start-line start-character line (+ character 1))))))
    (if (= ch "\n")
        (do (+= line 1) (setv character 0))
        (+= character 1)))
  (sorted ranges
          :key (fn [r] #((get r "start-line") (get r "start-character")
                         (get r "end-line") (get r "end-character")))))
