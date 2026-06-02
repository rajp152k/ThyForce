# Workflow improvements to pick up later

Running list of tooling/process upgrades surfaced during the HyGround port.
Not blocking; harvest when convenient.

## Custom test runner (high value)

Today each test file is a standalone script with its own `run-tests` loop, run
via `uv run hy tests/thyforce/<domain>/test_core.hy`, and CI lists every file by
hand. Problems:

- **`sys.executable` is the `hy` launcher** under `uv run hy ...`, which breaks
  libraries that subprocess `[sys.executable, "-c", "<python>"]` (see
  hy-isms.md: typeshed stub fallback). Running tests through **Python** instead of
  the `hy` CLI fixes this and matches the production entrypoint.
- No aggregate pass/fail across the suite; no auto-discovery (new files must be
  added to CI manually).

Proposal: a single runner that discovers `tests/**/test_*.hy`, imports each under
Python (after `import hy`), invokes its `run-tests`, and returns an aggregate
exit code. Natural home: a `polhy test` subcommand so CI is one line
(`uv run polhy test`) and local runs are uniform. Keep per-file `run-tests` so
files stay individually runnable.

## polhy upgrades

- **`polhy test`** — discover + run the Hy test suites (see above).
- **deps parser** — currently regex over import/require lines (flagged prototype
  in AGENTS.md). Replace with real parsing: `hy.read-many` the source, walk the
  models for `import` / `require` expressions, and emit structured dep data
  (module, alias, members, star). The engine port already shows model walking is
  cheap; this removes the regex's blind spots (multi-clause, `:as`, members).
- **`polhy check`** — deepen beyond namespace presence: assert each brick has its
  interface file (`__init__.py`) and module file, and (once deps are model-based)
  flag dependencies on bricks that don't exist.

## Porting workflow (multi-agent)

When porting a module set (Python → Hy here), run a **parallel fidelity audit**:
one reviewer subagent per module comparing the Hy port against the Python
original for behavioral divergence (off-by-one, dropped branches, mistranslated
comprehensions). Cheaper and more thorough than eyeballing; catches the class of
bug found by luck during this port (`#_` discard-as-binding, a `".__init__.py"`
typo). Author as an `eval` fan-out over the module list.

## Deferred features (tracked, not blocking)

- **core-docs from Hy metadata.** `analysis/core-docs.hy` is an explicit, hand-
  maintained table of Hy core-form signatures/docs (matches HyGround's parity
  baseline). Hy compiler/pattern macros mostly expose no useful `__doc__`, which
  is why the table exists. A future improvement is to generate this data from an
  upstream-supported source (e.g. Hy's Sphinx inventory / docs metadata) so we
  don't maintain a parallel table. Until then the explicit table is the source of
  truth and new core forms must be added by hand.
