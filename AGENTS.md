# AGENTS.md

Guidance for coding agents working in this repository.

## Repository direction

This repository follows the Polylith architectural idea using Hy as the primary implementation language.

Polylith is treated here as an architectural model, not as the existing Python `polylith-cli` implementation. `poly-meta` is only one development effort inside this repository that follows these practices; do not make repository-wide conventions depend on `poly-meta` specifically.

## Configuration policy

- Do not introduce TOML/YAML/JSON configuration for application/tooling behavior.
- Use Hy config files with the suffix `.cfg.hy`.
- The workspace config is `workspace.cfg.hy` at the repository root.
- `pyproject.toml` is allowed only where Python/uv packaging requires it.
- `workspace.toml` exists only for the old Python Polylith bootstrap and should not be expanded for new work.
- Configuration should be data-first: maps, vectors/lists, strings, and other Hy data forms.
- Avoid hardcoding names such as `core.hy`, `__init__.py`, source extensions, path layouts, or templates in behavior when they can come from config data.

## Polylith structure

Use a disciplined Polylith layout:

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

Group related bricks under a domain directory. For example, the `poly-meta` development effort is grouped under `poly_meta`:

```text
bases/thyforce/poly_meta/cli/
components/thyforce/poly_meta/config/
components/thyforce/poly_meta/workspace/
components/thyforce/poly_meta/bricks/
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
- Implementation modules should be Hy, normally `core.hy` by configuration.
- Interface filenames and implementation module names should remain configurable.

## Hy and imports

- Source implementation should be written in Hy.
- Prefer Hy hyphenated import style in Hy files:

```hy
(import thyforce.some-domain.some-component.core :as component_core)
```

- Hy mangles hyphenated names to underscore-based Python module names, so the corresponding filesystem path uses underscores:

```text
thyforce/some_domain/some_component/core.hy
```

- Python files, such as small entrypoint shims, must use Python-compatible underscore imports:

```python
from thyforce.some_domain.some_component import core
```

## Python shims

Small Python shims are acceptable when Python packaging or console entrypoints require them. Keep these minimal. Functional implementation should live in Hy components/bases.

## Data-oriented design

Code in this repository should be data-oriented:

- functions consume and return plain data maps/lists where practical
- commands should prefer machine-readable data output when appropriate
- behavior is driven by `.cfg.hy` config data
- templates are data, not scattered constants
- layout rules are data, not hardcoded path assumptions
- future language/tool support should be adapter-driven through config data

## Base/component/project responsibilities

- Bases contain entrypoints/adapters such as CLIs, HTTP handlers, workers, etc.
- Components contain reusable domain/tooling functionality.
- Projects represent buildable/deployable artifacts.
- Do not create separate project islands prematurely. The current root package can serve as a bootstrap project for uv until project generation is deliberately designed.

Example:

```text
bases/thyforce/<domain>/<base>/
components/thyforce/<domain>/<component>/
projects/<artifact>/
```

## Testing layout

Tests should mirror the namespace/domain hierarchy:

```text
tests/thyforce/<domain>/
```

For example:

```text
tests/thyforce/poly_meta/
```

Do not put tests for a domain in a flat unrelated path like `tests/poly_meta/`.

## Git workflow

- Work on the local branch:

```text
feature/language-agnostic-polylith
```

- Commit meaningful, reviewable increments locally.
- Do not push to GitHub until explicitly requested after review.
- Use `gh`/GitHub only when the user asks to push or open a PR.

## Useful current smoke checks

For the current `poly-meta` development effort:

```bash
uv run poly-meta check
PYTHONPATH=bases:components uv run python -m thyforce.poly_meta.cli info
PYTHONPATH=bases:components uv run python -m thyforce.poly_meta.cli deps
PYTHONPATH=bases:components uv run python -m unittest tests.thyforce.poly_meta.test_poly_meta
```
