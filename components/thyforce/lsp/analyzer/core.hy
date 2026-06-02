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
- `python-static`       side-effect-free AST indexing of Python modules
- `uri`                 filesystem-path / file-URI conversion
- `config`              workspace configuration ([tool.hyground] adapter)
- `resolver`            workspace-scoped Python/Hy runtime + static resolution
- `index`               document + workspace indexes, completion, resolution
"

(import thyforce.lsp.analyzer.model :as model)
(import thyforce.lsp.analyzer.word :as word)
(import thyforce.lsp.analyzer.folding :as folding)
(import thyforce.lsp.analyzer.completion-context :as completion-context)
(import thyforce.lsp.analyzer.semantic :as semantic)
(import thyforce.lsp.analyzer.core-docs :as core-docs)
(import thyforce.lsp.analyzer.python-static :as python-static)
(import thyforce.lsp.analyzer.uri :as uri)
(import thyforce.lsp.analyzer.config :as config)
(import thyforce.lsp.analyzer.resolver :as resolver)
(import thyforce.lsp.analyzer.index :as index)