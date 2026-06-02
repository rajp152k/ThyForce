"Public entry module for source analysis.

Analysis turns source text into a queryable semantic model (symbols, source
ranges, and — as further modules land — indexing, resolution, diagnostics,
folds, and tokens). It is independent of the Language Server Protocol: every
public result is a plain data map, validated by `thyforce.spec`.

Submodules:

- `model`  symbol-info / source-range constructors, kinds, and shape predicates
"

(import thyforce.analysis.model :as model)
