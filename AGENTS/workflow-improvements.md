# Workflow improvements to pick up later

Running list of tooling/process upgrades surfaced during the HyGround port.
Not blocking; harvest when convenient.

## polhy maturity (status)

The four-phase polhy maturation (deps → spec traces → test runner → project
machinery) is **implemented**. What landed:

- **deps** — form-based (`forms.hy`: `hy.read-many` + walk import/require),
  classified into brick / lib / stdlib edges (`{brick -> {bricks, libs}}`). The
  regex scanner is retired.
- **spec traces** — `thyforce.spec` `validate` returns path-precise problems
  (`{path, pred, value, message}`); `explain` / `named` added; specs stay callable.
- **`polhy test`** — discovers `tests/**/test_*.hy`, runs each through the
  workspace `.venv` Python (real `sys.executable`, so typeshed works), aggregates
  pass/fail + exit code. CI is one line: `uvx --from ./projects/polhy polhy test`.
- **project machinery** — `projects/<name>/project.cfg.hy` declares entry bricks +
  metadata; polhy computes the brick closure + libs (pinned from the root dev
  project) and generates the `pyproject.toml`. `polhy create project` scaffolds,
  `polhy sync` regenerates, `polhy check` flags invalid defs + pyproject drift.

Still open:

- **`polhy check` depth** — beyond drift + namespace presence: assert each brick
  has its interface/module files, flag brick deps on non-existent bricks, detect
  cycles.
- **Namespace-shim scaffolding** — `polhy create` (brick) does NOT emit the
  `extend_path` `__init__.py` for intermediate domain dirs under
  `components/`/`bases/`; a missing one fails silently at import. `create` should
  generate/repair these and `check` should assert they exist. (Project generation
  already emits domain `__init__.py` for grouping domains via force-include; the
  on-disk brick scaffolding gap remains.)
- **Shared `hy/forms` extraction** — `polhy/forms.hy` and `lsp/analyzer` both
  parse Hy import/require forms. Once the analyzer is migrated onto a shared
  parser, extract a `hy/forms` component both depend on (it now has two consumers).
- **`polhy diff` / incremental** — bricks changed since a git ref → drive
  `polhy test --since` and incremental builds (Polylith's headline feature).

## Porting workflow (multi-agent)

When porting a module set (Python → Hy here), run a **parallel fidelity audit**:
one reviewer subagent per module comparing the Hy port against the Python
original for behavioral divergence (off-by-one, dropped branches, mistranslated
comprehensions). Cheaper and more thorough than eyeballing; catches the class of
bug found by luck during this port (`#_` discard-as-binding, a `".__init__.py"`
typo). Author as an `eval` fan-out over the module list.

## Deferred features (tracked, not blocking)

- **core-docs from Hy metadata.** `lsp/analyzer/core-docs.hy` is an explicit, hand-
  maintained table of Hy core-form signatures/docs (matches HyGround's parity
  baseline). Hy compiler/pattern macros mostly expose no useful `__doc__`, which
  is why the table exists. A future improvement is to generate this data from an
  upstream-supported source (e.g. Hy's Sphinx inventory / docs metadata) so we
  don't maintain a parallel table. Until then the explicit table is the source of
  truth and new core forms must be added by hand.
