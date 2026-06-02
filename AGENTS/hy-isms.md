# Hy gotchas (running log)

Hard-won quirks of Hy (1.3.x) discovered while porting to this workspace. Append
as you hit new ones. Each entry: the trap, why, and the fix.

## Strings

- **No triple-quoted strings.** `"""x"""` lexes as three forms: `"" "x" ""`
  (empty string, content, empty string). It does not error on its own, so a
  module/function "docstring" written with `"""` silently becomes `__doc__ = ""`
  with stray string expression statements. If the content contains a `"`, the
  string closes early and you get `LexException: invalid string prefix '...'`.
  - Fix: use a single-quoted string. Hy strings are multi-line by default:
    `"line one\nline two"`.

- **f-strings can't nest double-quoted string literals in `{}`.** The embedded
  code in `f"... {expr} ..."` is real Hy, but a nested `"..."` collides with the
  outer quotes. `f"{(get m \"k\")}"` raises `invalid string prefix`.
  - Fix: bind the value first — `(setv v (get m "k"))` then `f"{v}"`.

- **Regex / raw strings:** there is no `r"..."` prefix. Use a bracket string
  `#[[ ... ]]` (raw, no escape processing) for regexes. With the empty delimiter
  the terminator is `]]`; pick a named delimiter `#[x[ ... ]x]` if the body
  contains `]]`.

## Macros / reader macros

- **`#@` decorator reader macro is gone** (Hy 1.x). Decorators now go in a
  bracket list before the name: `(defn [deco1 deco2] name [args] ...)`. Works for
  methods inside `defclass` too, e.g. `(defn [contextlib.contextmanager] cm [self] ...)`.

- **`#_` is the discard reader macro** — it drops the *next form entirely*. Do NOT
  use it as a throwaway binding in destructuring: `(setv [a #_ c] xs)` binds only
  `a` (it discards `c`!). Use a real throwaway name: `(setv [a _ c] xs)`.

- **`unquote` / `quote` collide with core macros.** Importing a function named
  `unquote` (e.g. `urllib.parse.unquote`) and then calling `(unquote x)` invokes
  the quasiquote macro, not the function (`ValueError: unquote is not allowed
  here`). Alias on import: `(import urllib.parse [unquote :as url-unquote])`.

## Imports

- **Aliased member import syntax:** `(import mod [name :as alias other])` — the
  `:as alias` follows the name inline. Nesting brackets
  (`[name [other :as alias]]`) is a parse error.

- **Hyphen ↔ underscore:** `(import thyforce.lsp.analyzer.completion-context)` resolves
  to the file `completion_context.hy`. Filenames use underscores; imports may use
  hyphens (Hy mangles them).

## Runtime / environment

- **`sys.executable` is the `hy` launcher under `hy -c` / `hy file.hy`.** Any
  library that spawns `[sys.executable, "-c", "<python code>"]` breaks, because
  `hy -c` parses the argument as Hy. Observed with
  `typeshed_client.get_stub_file`, which subprocesses
  `[python, "-c", "import sys, json; print(json.dumps(sys.path))"]` → `NameError:
  name 'import' is not defined` and a `CalledProcessError`.
  - Impact: typeshed stub fallback (builtins / C-extensions) is unavailable when
    code runs under the `hy` launcher (i.e. our `uv run hy tests/...` runner).
    It works under a real Python entrypoint (`python -m ...`, console scripts),
    so the production language-server entrypoint is unaffected.
  - The resolver already wraps it in try/except, so this is only stderr noise in
    tests — but it argues for running tests via Python, not the `hy` CLI (see
    workflow-improvements.md, custom test runner).

- **`uvx --from ./projects/<name>` serves stale wheels after brick edits.** uv
  caches the built wheel keyed on the project tree (`projects/<name>/`), but a
  Polylith project pulls its bricks via `force-include` from `../../components`
  and `../../bases` — *outside* that tree. Editing a brick does not change the
  cache key, so uv reuses the old wheel. `--refresh` and `--reinstall` do NOT
  rebuild it; only `uv cache clean <name>` (or touching the project's own
  `pyproject.toml`) forces a rebuild.
  - Unaffected: CI (fresh machine, no cache) and git installs
    (`git+...@<ref>#subdirectory=...` keys on the commit SHA).
  - Local dev after editing bricks: prefer live source
    (`PYTHONPATH=bases:components uv run hy ...`, or `cli.main` directly) over
    `uvx --from ./projects/...`, or `uv cache clean <name>` first.
  - PYTHONPATH order matters: use `bases:components` (bases first). The `polhy`
    component's interface `__init__.py` is a regular package; with components
    first it shadows the `bases` `extend_path` shim and `thyforce.polhy.cli`
    (the base) fails to import. Bases-first lets the namespace span both.

## Shadowing / scoping

- **Module alias shadowed by a same-named parameter.** `(import x.y.uri :as uri)`
  at module top, then a method `(defn root-for-uri [self uri] ... (uri.to-fs-path uri))`:
  inside that method `uri` is the *parameter* (a string), so `uri.to-fs-path`
  raises `AttributeError`. If that call sits inside a broad `(try ... (except
  [Exception] (return (Path.cwd))))`, the failure is swallowed and you get a
  silent wrong fallback (here: every URI resolved to cwd, so the indexer scanned
  the whole repo instead of the target workspace). Two lessons:
  - Don't alias a module to a name you also use as a parameter/local. We renamed
    the import to `uris`.
  - Beware broad `except` that masks `AttributeError`/`NameError` from typos and
    shadowing. When a "tolerant" fallback fires suspiciously often, suspect a
    masked programming error, not bad input.
