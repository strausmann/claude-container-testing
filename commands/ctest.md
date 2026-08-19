---
description: Run a repo's tests/lint/build in a reproducible, toolchain-decoupled devcontainer
argument-hint: "<test|lint|build|env|list|prune> [path] [--template <name>] [--cmd \"<...>\"]"
allowed-tools: Bash
---

# /ctest

Run a repo's tests, lint, or build inside this plugin's devcontainer catalog instead of relying
on whatever toolchain happens to be installed on the host. See the `container-testing` skill for
when this is mandatory (before every PR/merge, on any toolchain conflict) versus optional (fast
local iteration).

## Usage

```
/ctest <test|lint|build|env|list|prune> [path] [--template <name>] [--cmd "<...>"]
```

- `test` / `lint` / `build` — run the resolved template's default command for that task.
- `env` — drop into an interactive shell in the resolved container.
- `list` — print the template catalog (`catalog/INDEX.md`).
- `prune` — remove local Docker images for templates no longer in the catalog.
- `path` — target repo directory (default: `.`). The template is auto-detected from it
  (`go.mod`, `package.json`, `compose.test.yml`, …) unless `--template` is given.
- `--template <name>` — use this catalog template instead of auto-detecting.
- `--cmd "<...>"` — run this command instead of the task's default command.

## Execute

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/container-testing/scripts/ctest.sh" $ARGUMENTS
```
