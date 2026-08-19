#!/usr/bin/env bash
# Entry dispatch for /ctest -- the single command a user/agent runs instead of invoking
# resolve-template.sh / run-solo.sh / run-env.sh / prune.sh by hand.
#
# Usage: ctest.sh <test|lint|build|env|list|prune> [path] [--template <name>] [--cmd "<...>"]
#
# - `list`  prints catalog/INDEX.md and exits -- no repo/template resolution involved.
# - `prune` runs prune.sh (local ghcr-cache cleanup) -- no repo/template resolution involved.
# - `test`/`lint`/`build`/`env` (or a bare `--cmd` with no task word) resolve a template for
#   `path` (default `.`) -- either auto-detected via resolve-template.sh, or the catalog entry
#   named by `--template` -- then dispatch to run-solo.sh (solo templates) or run-env.sh (env
#   templates) with the task's command (or `--cmd`'s override, verbatim).
#
# `env` as a *task* (drop into an interactive shell in the resolved container) is a different
# thing from `env` as a template *mode* (compose-based, see resolve-template.sh) -- don't confuse
# the two; a solo template can still take the `env` task.
#
# CTEST_DRY_RUN=1: instead of executing the resolved run-solo.sh/run-env.sh invocation, echo it
# and exit 0. This is the seam that makes dispatch testable without Docker (see
# tests/resolve-template.bats) -- everything up to the actual `exec` is real: real arg parsing,
# real resolve-template.sh call, real catalog lookup.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS="$ROOT/skills/container-testing/scripts"
CATALOG="$ROOT/catalog"

usage() {
  cat <<'USAGE'
Usage: ctest.sh <test|lint|build|env|list|prune> [path] [--template <name>] [--cmd "<...>"]

  test|lint|build   Run the toolchain's task command for the resolved template.
  env               Drop into an interactive shell in the resolved container.
  list              Print the template catalog (catalog/INDEX.md).
  prune             Remove local Docker images for templates no longer in the catalog.

  path              Target repo directory to test (default: .). Ignored by list/prune.
  --template NAME   Use this catalog template instead of auto-detecting from `path`.
  --cmd "..."       Run this command instead of the task's default command.
USAGE
}

task=""
path=""
template_override=""
cmd_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --template)
      template_override="${2:?ctest: --template needs a value}"
      shift 2
      ;;
    --cmd)
      cmd_override="${2:?ctest: --cmd needs a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    test|lint|build|env|list|prune)
      if [ -z "$task" ]; then
        task="$1"
      elif [ -z "$path" ]; then
        path="$1"
      else
        echo "ctest: unexpected argument '$1'" >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
    *)
      if [ -z "$path" ]; then
        path="$1"
      else
        echo "ctest: unexpected argument '$1'" >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ "$task" = "list" ]; then
  cat "$CATALOG/INDEX.md"
  exit 0
fi

if [ "$task" = "prune" ]; then
  exec bash "$SCRIPTS/prune.sh"
fi

if [ -z "$task" ] && [ -z "$cmd_override" ]; then
  echo "ctest: missing task (test|lint|build|env|list|prune) or --cmd" >&2
  usage >&2
  exit 2
fi

[ -z "$path" ] && path="."
if [ ! -d "$path" ]; then
  echo "ctest: no such directory: $path" >&2
  exit 2
fi
path="$(cd "$path" && pwd)"

# task_command <template> <task> -- default command for a task on a resolved template.
# Node templates (node22-lint-test, node22-postgres16, ...) run the target repo's own npm
# scripts against the baked-in, pinned toolchain (see catalog/node22-lint-test/README.md); go
# templates run the standard go subcommands, `go vet` for lint per this plugin's convention
# (golangci-lint is baked in too, but `go vet` is the default -- pass --cmd for golangci-lint).
task_command() {
  local template="$1" tsk="$2"
  case "$template" in
    node*)
      case "$tsk" in
        test)  echo "npm test" ;;
        lint)  echo "npm run lint" ;;
        build) echo "npm run build" ;;
        env)   echo "bash" ;;
        *) echo "ctest: no default '$tsk' command for template '$template'; pass --cmd" >&2; return 2 ;;
      esac
      ;;
    go*)
      case "$tsk" in
        test)  echo "go test ./..." ;;
        lint)  echo "go vet ./..." ;;
        build) echo "go build ./..." ;;
        env)   echo "bash" ;;
        *) echo "ctest: no default '$tsk' command for template '$template'; pass --cmd" >&2; return 2 ;;
      esac
      ;;
    *)
      echo "ctest: no default task commands known for template '$template'; pass --cmd" >&2
      return 2
      ;;
  esac
}

if [ -n "$template_override" ]; then
  template="$template_override"
  config="$CATALOG/$template/.devcontainer/devcontainer.json"
  if [ ! -f "$config" ]; then
    echo "ctest: unknown template '$template' (see 'ctest list')" >&2
    exit 2
  fi
  if jq -e 'has("dockerComposeFile")' "$config" >/dev/null 2>&1; then
    mode="env"
  else
    mode="solo"
  fi
else
  resolved="$(bash "$SCRIPTS/resolve-template.sh" "$path" "$CATALOG")" || exit $?
  template="${resolved% *}"
  mode="${resolved##* }"
  config="$CATALOG/$template/.devcontainer/devcontainer.json"
fi

if [ -n "$cmd_override" ]; then
  cmd_str="$cmd_override"
else
  cmd_str="$(task_command "$template" "$task")" || exit $?
fi

runner="run-solo.sh"
[ "$mode" = "env" ] && runner="run-env.sh"

# Word-split the (possibly multi-word) command into argv entries -- read -ra splits on IFS
# without globbing, unlike eval.
IFS=' ' read -ra cmd_arr <<< "$cmd_str"

if [ -n "${CTEST_DRY_RUN:-}" ]; then
  echo "$SCRIPTS/$runner $path $config -- ${cmd_arr[*]}"
  exit 0
fi

exec bash "$SCRIPTS/$runner" "$path" "$config" -- "${cmd_arr[@]}"
