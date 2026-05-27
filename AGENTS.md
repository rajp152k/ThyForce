# AGENTS.md

Guidance for coding agents working in this repository.

## Project direction

This repository is moving toward a Hy-native, language-agnostic Polylith meta-tool named `poly-meta`.

Polylith is treated here as an architectural model, not as the existing Python `polylith-cli` implementation. The goal is to build flexible, data-oriented tooling that can later replace the current bootstrap dependency on Python Polylith tooling.

## Configuration policy

- Do not introduce TOML/YAML/JSON configuration for `poly-meta`.
- Use Hy config files with the suffix `.cfg.hy`.
- The workspace config is `workspace.cfg.hy` at the repository root.
- `pyproject.toml` is allowed only where Python/uv packaging requires it.
- `workspace.toml` exists only for the old Python Polylith bootstrap and should not be expanded for new work.
- Configuration should be data-first: maps, vectors/lists, strings, and other Hy data forms.
- Avoid hardcoding names such as `core.hy`, `__init__.py`, source extensions, path layouts, or templates in behavior when they can come from `workspace.cfg.hy`.

## Polylith structure

Use a disciplined Polylith layout from the start:

```text
bases/<namespace>/<domain>/<base>/
components/<namespace>/<domain>/<component>/
projects/
tests/<namespace>/<domain>/
```

For this repository, the top-level namespace is:

```text
thyforce
```

The `poly-meta` domain is grouped under `poly_meta`:

```text
bases/thyforce/poly_meta/cli/
components/thyforce/poly_meta/config/
components/thyforce/poly_meta/workspace/
components/thyforce/poly_meta/bricks/
components/thyforce/poly_meta/deps/
components/thyforce/poly_meta/check/
components/thyforce/poly_meta/sync/
components/thyforce/poly_meta/projects/
```

Do not flatten domain + component names into names like `poly_meta_config` unless there is a compelling reason. Prefer path-like brick names:

```text
poly_meta/config
poly_meta/workspace
poly_meta/cli
```

The grouping directory itself, e.g. `components/thyforce/poly_meta/`, is not a component. The leaf directories are the bricks.

## Interfaces

- Use `__init__.py` as the brick interface file for now.
- This mirrors Python Polylith's use of `__init__.py` as an interface analogous to Clojure Polylith's `interface.clj`.
- The implementation modules should be Hy, normally `core.hy` by configuration.
- The interface filename must remain configurable through `workspace.cfg.hy`.

## Hy and imports

- Source implementation should be written in Hy.
- Prefer Hy hyphenated import style in Hy files:

```hy
(import thyforce.poly-meta.config.core :as config_core)
```

- Hy mangles hyphenated names to underscore-based Python module names, so the corresponding filesystem path remains:

```text
thyforce/poly_meta/config/core.hy
```

- Python files, such as small entrypoint shims, must use Python-compatible underscore imports:

```python
from thyforce.poly_meta.cli import core
```

## Python shims

Small Python shims are acceptable when Python packaging or console entrypoints require them. Keep these minimal. The functional implementation should live in Hy components/bases.

Current example:

```text
bases/thyforce/poly_meta/cli/runner.py
```

## Data-oriented design

The `poly-meta` implementation should be data-oriented:

- functions consume and return plain data maps/lists where practical
- commands print machine-readable data, currently JSON
- behavior is driven by `workspace.cfg.hy`
- templates are data, not scattered constants
- layout rules are data, not hardcoded path assumptions
- future language support should be adapter-driven through config data

## CLI/base/component responsibilities

- CLI behavior belongs in the base:

```text
bases/thyforce/poly_meta/cli/
```

- Reusable Polylith functionality belongs in components:

```text
components/thyforce/poly_meta/config/
components/thyforce/poly_meta/workspace/
components/thyforce/poly_meta/bricks/
components/thyforce/poly_meta/deps/
components/thyforce/poly_meta/check/
components/thyforce/poly_meta/sync/
components/thyforce/poly_meta/projects/
```

- Projects should represent buildable/deployable artifacts later, but do not create separate project islands prematurely. The current root package is the bootstrap project for uv.

## Testing layout

Tests should mirror the namespace/domain hierarchy:

```text
tests/thyforce/poly_meta/
```

Do not put `poly-meta` tests in a flat unrelated path like `tests/poly_meta/`.

Run tests with:

```bash
PYTHONPATH=bases:components uv run python -m unittest tests.thyforce.poly_meta.test_poly_meta
```

## Git workflow

- Work on the local branch:

```text
feature/language-agnostic-polylith
```

- Commit meaningful, reviewable increments locally.
- Do not push to GitHub until explicitly requested after review.
- Use `gh`/GitHub only when the user asks to push or open a PR.

## Current CLI smoke checks

Useful checks while developing:

```bash
uv run poly-meta check
PYTHONPATH=bases:components uv run python -m thyforce.poly_meta.cli info
PYTHONPATH=bases:components uv run python -m thyforce.poly_meta.cli deps
PYTHONPATH=bases:components uv run python -m unittest tests.thyforce.poly_meta.test_poly_meta
```
