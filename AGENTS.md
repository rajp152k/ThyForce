# AGENTS.md

Guidance for coding agents working in this repository.

## Repository direction

This repository follows the Polylith architectural idea using Hy as the primary implementation language.

Polylith is treated here as an architectural model, not as the existing Python `polylith-cli` implementation. The repository no longer uses Python `polylith-cli`; all Polylith workspace operations should be done with the in-repo `polhy` tooling.

## Configuration policy

- Do not introduce TOML/YAML/JSON configuration for application/tooling behavior.
- Use Hy config files with the suffix `.cfg.hy`.
- The workspace config is `workspace.cfg.hy` at the repository root.
- `pyproject.toml` is allowed only where Python/uv packaging requires it.
- Do not add `workspace.toml`; the old Python Polylith bootstrap has been removed.
- Configuration should be data-first: maps, vectors/lists, strings, and other Hy data forms.
- Avoid hardcoding names such as `core.hy`, `__init__.py`, source extensions, path layouts, or templates in behavior when they can come from config data.
- If something starts as a constant for bootstrapping, prefer making it config-driven in the next iteration rather than spreading the assumption.

## Polylith tooling usage

Use the in-repo `polhy` command for Polylith operations. The root `pyproject.toml`
exposes no console scripts; run `polhy` through its project (`projects/polhy`):

Do use:

```bash
uvx --from ./projects/polhy polhy info
uvx --from ./projects/polhy polhy check
uvx --from ./projects/polhy polhy deps
uvx --from ./projects/polhy polhy create component <domain>/<component>
uvx --from ./projects/polhy polhy create base <domain>/<base>
```

Tip: alias it for interactive use — `alias polhy='uvx --from ./projects/polhy polhy'`.

Do not use:

```bash
uv run poly ...
```

Do not reintroduce `polylith-cli` or `workspace.toml` unless explicitly requested. If `polhy` lacks a feature, implement or extend the relevant Hy component/base rather than falling back to Python Polylith.

`polhy` is the repository's local tool for applying Polylith operations. The broader architecture rules in this file remain independent of any one domain or feature.

## Supplementary notes (AGENTS/)

Running, append-only knowledge lives in the `AGENTS/` directory alongside this file:

- `AGENTS/hy-isms.md` — Hy language gotchas hit in this repo (no triple-quoted strings, f-string `!`-conversion vs `!`-in-symbols, decorator syntax, namespace-shim shadowing, `sys.executable` under the `hy` launcher, …).
- `AGENTS/workflow-improvements.md` — tooling/process upgrades to pick up later (custom `polhy test` runner, model-based deps parser, `polhy create project`, deferred features).

This root `AGENTS.md` holds the canonical, repo-wide conventions; it is auto-loaded by agent tooling at the repository root, so it stays here rather than moving inside `AGENTS/`. The `AGENTS/` files are the supplementary log. Keep both current.

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

Group related bricks under a domain directory when they are genuinely separate reusable capabilities. For the current `polhy` development effort, the reusable capability is a single component:

```text
components/thyforce/polhy/
```

and its CLI entrypoint is a base:

```text
bases/thyforce/polhy/cli/
```

Do not flatten domain + component names into names like `polhy_config` unless there is a compelling reason. Prefer path-like brick names when there are truly multiple bricks:

```text
some_domain/some_component
some_domain/some_base
```

A directory under `components/<namespace>/` can itself be a component if it has the brick files, e.g. `components/thyforce/polhy/core.hy`. A nested grouping directory is only a grouping directory when its leaf children are the actual bricks.

Before creating a new brick, determine its identity explicitly:

```text
namespace: thyforce
domain: <domain>
brick: <component-or-base>
brick name: <domain>/<brick>
component path: components/thyforce/<domain>/<brick>/
base path: bases/thyforce/<domain>/<brick>/
Hy import: thyforce.<domain-with-hyphens>.<brick-with-hyphens>.core
Python import: thyforce.<domain_with_underscores>.<brick_with_underscores>.core
```

Do this planning before writing files. Avoid creating then refactoring between unrelated layouts.

## Interfaces

- Use `__init__.py` as the brick interface file for now.
- This mirrors Python Polylith's use of `__init__.py` as an interface analogous to Clojure Polylith's `interface.clj`.
- Implementation modules should be Hy, normally `core.hy` by configuration.
- Interface filenames and implementation module names should remain configurable.
- Each brick should normally contain both:

```text
__init__.py
core.hy
```

`__init__.py` is the public interface. `core.hy` is the public implementation entry module. A brick may contain additional internal Hy modules, e.g. `config.hy`, `workspace.hy`, or `deps.hy`; these are internal modules, not separate Polylith bricks.

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

## Python / Hy interop and shims

Small Python shims are acceptable when Python packaging, console entrypoints, or `python -m ...` execution require them. Keep these minimal. All functional code, including tests, should live in Hy. Python remains only for interop/delegation shims.

Why shims may be needed:

- Python packaging console scripts in `pyproject.toml` expect a Python-importable object of the form `module.path:function`.
- Hy modules are importable from Python only after Hy's import hook has been installed, usually by `import hy`.
- A tiny Python shim can install the Hy import hook, import the Hy implementation module, and delegate immediately.

Recommended console-script shim pattern:

```python
# bases/thyforce/<domain>/<base>/runner.py

def main():
    import hy  # installs Hy import hook
    from thyforce.<domain_with_underscores>.<base_with_underscores> import core

    return core.main()
```

Then `pyproject.toml` may point to the Python shim:

```toml
[project.scripts]
some-command = "thyforce.<domain_with_underscores>.<base_with_underscores>.runner:main"
```

Recommended `python -m ...` shim pattern:

```python
# bases/thyforce/<domain>/<base>/__main__.py

import hy
from thyforce.<domain_with_underscores>.<base_with_underscores> import core

if __name__ == "__main__":
    core.main()
```

Use `runner.py` when:

- exposing a command through `[project.scripts]`
- uv/Python packaging needs a stable Python import target
- the real CLI implementation is in `core.hy`

Use `__main__.py` when:

- you want `python -m thyforce.<domain>.<base>` to work
- it is useful for development smoke checks or debugging

A base may have both:

```text
core.hy      # real implementation
runner.py    # console-script shim
__main__.py  # python -m shim
```

This is acceptable as long as the Python files only delegate. Do not put business/tooling logic in the shims.

Shims are not needed when:

- a Hy module is only imported by other Hy code
- there is no Python packaging entrypoint
- there is no need to support `python -m ...`
- the caller has already imported `hy` and can import Hy modules directly

In Hy source, prefer hyphenated imports:

```hy
(import thyforce.some-domain.some-base.core :as base_core)
```

In Python shims, use underscore imports because Python syntax cannot import hyphenated module names:

```python
from thyforce.some_domain.some_base import core
```


## Spec and validation direction

Validation is a foundational data capability and should remain separate from configuration management.

Use the `thyforce/spec` component for predicate-based specs:

```text
components/thyforce/spec/
tests/thyforce/spec/
```

A spec is fundamentally a predicate: a function of one argument returning true/false.

```hy
(defn non-empty-string? [value]
  (and (spec.str? value) (> (len value) 0)))
```

The `genspec` macro may be used to generate nested map predicates from Hy data forms:

```hy
(require thyforce.spec.core [genspec])
(import thyforce.spec.core :as spec)

(setv workspace?
  (genspec {"namespace" spec.str?
            "paths" {"components" spec.str?
                     "bases" spec.str?
                     "test-root" spec.str?}}))
```

Configuration management should later build on top of this validation backend. Do not embed config-file, env-var, secret, or application initialization concerns into the spec component.

## Data-oriented design

Code in this repository should be data-oriented:

- functions consume and return plain data maps/lists where practical
- commands should prefer machine-readable data output when appropriate
- behavior is driven by `.cfg.hy` config data
- templates are data, not scattered constants
- layout rules are data, not hardcoded path assumptions
- future language/tool support should be adapter-driven through config data
- separate pure data transformation from IO and CLI printing
- validate and return structured error data where practical instead of only printing strings

For tooling code, prefer this layering:

```text
config/data loading -> pure component functions -> base/CLI adapter -> printed output
```

Avoid putting reusable behavior directly in bases.

## Base/component/project responsibilities

- Bases contain entrypoints/adapters such as CLIs, HTTP handlers, workers, etc.
- Components contain reusable domain/tooling functionality.
- Projects represent buildable/deployable artifacts.
- Projects are deployable artifacts, created once a real one exists — which is now the case. Live projects under `projects/`: `hyground` (the Hy language server) and `polhy` (the workspace tooling). The root `pyproject.toml` is the **development project** — an editable install of all bricks that provides the `.venv` (deps + `import thyforce.*`) for in-repo work and tests. It exposes no console scripts; entrypoints are reached through their projects (`uvx --from ./projects/<name> <script>`). Each `projects/<name>/pyproject.toml` is a slim standalone deployable. See the Projects section below.

Example:

```text
bases/thyforce/<domain>/<base>/
components/thyforce/<domain>/<component>/
projects/<artifact>/
```

When adding functionality, implement and test the component API first, then wire it into a base.

A Polylith component is not the same thing as every internal module. Prefer one cohesive component with internal modules until a part earns extraction. Split a new component only when it has a stable public interface, an independent reason to change, and a plausible reuse site outside the original component.

Recommended sequence:

```text
1. define namespace/domain/brick identity
2. create component/base files in the correct hierarchy
3. implement component data functions
4. add component tests
5. add or update base/CLI wrapper
6. add CLI/adapter tests
7. update AGENTS.md only if a convention changes
8. commit a meaningful local increment
```

## Projects (deployables)

A project is a buildable/deployable artifact with its own `pyproject.toml` that composes a chosen set of bricks plus only the third-party deps that set needs. Bases stay bases; a project *includes* a base, it does not replace it.

Current projects:

```text
projects/hyground/   lsp/engine + lsp/analyzer + lsp/providers + lsp/server + spec   (deps: hy, typeshed-client)
projects/polhy/      polhy + polhy/cli                                                (deps: hy)
```

Packaging pattern (hatchling): the project `pyproject.toml` declares `[project]` metadata, slim `dependencies`, and `[project.scripts]`, then pulls bricks from the workspace root via `force-include` (paths are relative to the project file):

```toml
[tool.hatch.build.targets.wheel.force-include]
"../../components/thyforce/__init__.py" = "thyforce/__init__.py"
"../../components/thyforce/<domain>/<component>" = "thyforce/<domain>/<component>"
"../../bases/thyforce/<domain>/<base>" = "thyforce/<domain>/<base>"
```

Install/run a project straight from git with uv:

```bash
uvx --from "git+https://github.com/rajp152k/ThyForce@master#subdirectory=projects/<name>" <script>
```

Do not bolt a wheel target onto the root `pyproject.toml` to ship bricks — that bundles everything under one distribution and defeats the point. Add a `projects/<name>/` instead. (Generating these files is a planned `polhy create project` command; see `AGENTS/workflow-improvements.md`.)

## Testing layout

Use `tests/` as the repository test root. Do not create or use a singular `test/` root.

Tests should mirror the namespace/domain hierarchy:

```text
tests/thyforce/<domain>/
```

For example:

```text
tests/thyforce/polhy/
```

Do not put tests for a domain in a flat unrelated path like `tests/polhy/`.

For a component such as:

```text
components/thyforce/auth/tokens/
```

prefer tests under one of:

```text
tests/thyforce/auth/test_tokens.py
tests/thyforce/auth/tokens/test_core.py
```

Keep the namespace/domain mirrored either way.

Tests should cover both happy paths and meaningful failure cases, especially:

- missing config files
- malformed `.cfg.hy` config
- unknown language/tool adapters
- missing templates
- invalid brick names
- overwrite behavior
- dependency parser edge cases
- CLI output shape

Tests should be written in Hy. Python test files should not be added unless they are explicitly testing Python interop shim behavior. Even then, keep the Python part minimal and put functional assertions in Hy where possible.

## Quality expectations for new bricks

For a new component/base, avoid the mistakes of early bootstrapping:

- do not start with a flat or temporary namespace if the final domain path is known
- do not split every internal module into a separate brick; split only around reusable capabilities with independent reasons to change
- do not create microcomponents that cannot be imagined being used from anywhere else
- do not create `projects/` entries until a real buildable/deployable artifact exists (now satisfied by `hyground` and `polhy`; see the Projects section)
- do not hardcode names that should be config/data-driven
- do not put logic in a CLI base that belongs in a component
- do not rely on regex parsing when a real language/data parser is needed for correctness, except as an explicit prototype
- do not leave placeholder components without marking their status clearly

A prototype is acceptable, but make prototype boundaries explicit in code, tests, or docs.

## Git workflow

- Work on the local branch:

```text
feature/language-agnostic-polylith
```

- Commit meaningful, reviewable increments locally.
- Do not push to GitHub until explicitly requested after review.
- Use `gh`/GitHub only when the user asks to push or open a PR.
- If early commits contain structural churn, consider squashing/rebasing before merge, but only when requested.

## Useful current smoke checks

Workspace + tests:

```bash
uvx --from ./projects/polhy polhy check
uvx --from ./projects/polhy polhy deps
PYTHONPATH=bases:components uv run hy tests/thyforce/lsp/engine/test_core.hy
PYTHONPATH=bases:components uv run hy tests/thyforce/lsp/analyzer/test_core.hy
PYTHONPATH=bases:components uv run hy tests/thyforce/lsp/analyzer/test_index.hy
PYTHONPATH=bases:components uv run hy tests/thyforce/lsp/providers/test_core.hy
PYTHONPATH=bases:components uv run hy tests/thyforce/lsp/server/test_core.hy
PYTHONPATH=bases:components uv run hy tests/thyforce/polhy/test_polhy.hy
PYTHONPATH=bases:components uv run hy tests/thyforce/spec/test_spec.hy
```

Deployables (build + run from the project subdirs via uv):

```bash
uvx --from ./projects/hyground hyground --version
uvx --from ./projects/polhy polhy info
```

Note: the `hy` launcher sets `sys.executable` to `hy`, which breaks libraries that subprocess `[python, -c, ...]` (e.g. typeshed stub lookup). Tests run under `hy`; the deployables run under Python via uvx, where that path works. See `AGENTS/hy-isms.md`.
