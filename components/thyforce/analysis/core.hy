"Public entry module for source analysis.

Analysis turns source text into a queryable semantic model (symbols, source
ranges, and — as further modules land — indexing, resolution, diagnostics,
folds, and tokens). It is independent of the Language Server Protocol: every
public result is a plain data map, validated by `thyforce.spec`.

Submodules:

- `model`               symbol-info / source-range constructors, kinds, predicates
- `word`                symbol extraction, occurrences, enclosing-call detection
- `folding`             delimiter-based folding ranges
- `completion-context`  import/require completion-context detection
- `semantic`            best-effort semantic tokens + LSP encoding
- `core-docs`           explicit documentation table for Hy core forms
"

(import thyforce.analysis.model :as model)
(import thyforce.analysis.word :as word)
(import thyforce.analysis.folding :as folding)
(import thyforce.analysis.completion-context :as completion-context)
(import thyforce.analysis.semantic :as semantic)
(import thyforce.analysis.core-docs :as core-docs)