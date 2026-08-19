#!/usr/bin/env bash
# Env runner: up the compose stack (runner + its declared service dependencies, e.g. postgres),
# exec the task against the mounted target repo, then ALWAYS tear the whole stack down with
# `docker compose ... down -v --remove-orphans` -- so a failed test never leaks a postgres (or
# any other dependency) container/volume/network. Propagates the task's exit code verbatim.
#
# Three environment realities this script works around, all confirmed empirically in this
# environment while building this template (see the Task 7 report):
#
# 1. `devcontainer up` (CLI 0.80.0) never returns for a compose-based config either -- same as
#    the solo runner (see run-solo.sh header, point 1). So `up` is started in the background,
#    readiness is confirmed by polling `docker ps` for the id-label (which the CLI applies only
#    to the target `service` container, not to its compose dependencies), then `exec` runs the
#    actual task.
# 2. A compose-based `devcontainer.json`'s `dockerComposeFile` path, when driven via
#    `--override-config` against a `--workspace-folder` that differs from the config file's own
#    directory (exactly this runner's normal use: target repo as workspace, template config as
#    override), resolves relative to `<workspace-folder>/.devcontainer/` instead of relative to
#    the override-config's own directory -- confirmed by a direct repro (`no such file or
#    directory` against a path built from the *repo's* .devcontainer, not the template's). Same
#    class of bug as run-solo.sh's Dockerfile-path pitfall (point 2 there), just for
#    `dockerComposeFile`. Worked around the same way: a scratch override-config identical to the
#    template's config but with `dockerComposeFile` rewritten to an *absolute* path, so path
#    resolution is sidestepped entirely.
# 3. Unlike the Dockerfile/image path, a compose-based devcontainer does **not** auto-mount the
#    workspace folder into the target service -- `workspaceFolder` in devcontainer.json is only
#    metadata there (confirmed empirically: `/workspace` did not exist in the container without
#    an explicit mount). The target repo is bind-mounted in explicitly via `devcontainer up
#    --mount type=bind,source=<repo>,target=<workspaceFolder>`.
#
# Teardown targets the exact stack this run started: `COMPOSE_PROJECT_NAME` is set explicitly
# before `up` (devcontainer CLI passes it through as `docker compose --project-name <name>`,
# confirmed empirically) so the project name is known up front rather than guessed afterwards.
set -uo pipefail
source "$(dirname "$0")/devcontainer-bin.sh"

repo="${1:?repo}"; config="${2:?template devcontainer.json}"; shift 2
[ "${1:-}" = "--" ] && shift

BIN="$(devcontainer_bin)" || exit 1

repo_abs="$(cd "$repo" && pwd)"
config_abs="$(cd "$(dirname "$config")" && pwd)/$(basename "$config")"

workspace_folder="$(jq -r '.workspaceFolder // "/workspace"' "$config_abs")"
compose_rel="$(jq -r '.dockerComposeFile' "$config_abs")"
if [ -z "$compose_rel" ] || [ "$compose_rel" = "null" ]; then
  echo "ctest: $config_abs has no 'dockerComposeFile' -- run-env.sh is for compose (env) templates only, use run-solo.sh for solo templates" >&2
  exit 1
fi
compose_abs="$(cd "$(dirname "$config_abs")" && cd "$(dirname "$compose_rel")" && pwd)/$(basename "$compose_rel")"

# Scratch override-config identical to $config but with dockerComposeFile rewritten to the
# absolute compose path -- see header comment, point 2.
scratch_config="$(mktemp /tmp/ctest-run-env-XXXXXX.json)"
jq --arg c "$compose_abs" '.dockerComposeFile = $c' "$config_abs" > "$scratch_config"

label="ctest-env=$(printf '%s' "$repo_abs$config_abs" | sha256sum | cut -c1-12)"
project="ctestenv$(printf '%s' "$repo_abs$config_abs" | sha256sum | cut -c1-12)"
export COMPOSE_PROJECT_NAME="$project"

up_pid=""

cleanup() {
  [ -n "$up_pid" ] && kill "$up_pid" >/dev/null 2>&1 || true
  # Always tear the whole stack down -- containers, named volumes, networks, orphans -- so a
  # failed/aborted run never leaks the postgres (or any other) service. Unconditional: runs
  # whether the task passed, failed, or the script errored out before exec.
  docker compose --project-name "$project" -f "$compose_abs" down -v --remove-orphans \
    >/dev/null 2>&1 || true
  rm -f "$scratch_config" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_container() {
  local i
  for i in $(seq 1 90); do
    [ -n "$(docker ps -q --filter "label=$label" 2>/dev/null)" ] && return 0
    if [ -n "$up_pid" ] && ! kill -0 "$up_pid" 2>/dev/null; then
      return 1
    fi
    sleep 1
  done
  return 1
}

# Started in the background and never awaited directly -- see header comment, point 1.
$BIN up --workspace-folder "$repo_abs" --override-config "$scratch_config" \
    --id-label "$label" --id-label "ctest-test=1" --remove-existing-container \
    --mount "type=bind,source=$repo_abs,target=$workspace_folder" \
    >/dev/null 2>&1 &
up_pid=$!

if ! wait_for_container; then
  echo "ctest: env stack did not become ready (runner service never reported healthy/running)" >&2
  exit 1
fi

# exec: run the task in the runner service container (matched by id-label); propagate its exit
# code verbatim.
$BIN exec --workspace-folder "$repo_abs" --override-config "$scratch_config" \
    --id-label "$label" --id-label "ctest-test=1" -- "$@"
code=$?

exit "$code"
