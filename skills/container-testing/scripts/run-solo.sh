#!/usr/bin/env bash
# Solo runner: up + exec against the mounted target repo, propagate the task's exit code verbatim.
#
# Two environment realities this script works around (both confirmed in this environment,
# see docs/superpowers/sdd/2026-08-19-container-testing-plugin/task-4-report.md Concerns):
#
# 1. `devcontainer up` (CLI 0.80.0) starts the container fine but then never returns. So `up`
#    is never awaited directly: it is started in the background, readiness is confirmed by
#    polling `docker ps` for the id-label, then `exec` runs the actual task. The leftover `up`
#    process and the container are always cleaned up before this script exits.
# 2. A `devcontainer.json` with a *relative* `build.dockerfile` path (the interim state before
#    a ghcr digest is published) resolves that path against `<--workspace-folder>/.devcontainer/`
#    -- NOT against the override-config file's own directory -- when `up`/`exec` are driven with
#    `--override-config` against a workspace-folder that differs from the template dir (i.e.
#    exactly this runner's normal use: target repo as workspace, template config as override).
#    That makes a direct `up --workspace-folder <repo> --override-config <template config>` fail
#    with an ENOENT on the Dockerfile whenever the config is still build-based. So: whenever the
#    template's config has no `image` field yet, this script builds the image itself via
#    `devcontainer build --workspace-folder <template-dir>` (workspace IS the template dir there,
#    so the Dockerfile resolves correctly) and drives `up`/`exec` against a scratch override-config
#    that swaps `build` for the resulting local `image:` reference -- sidestepping path resolution
#    entirely. Once the template is published with `image: <ghcr-digest>` (Task 11), the direct
#    path is tried first and this local-build path becomes purely the offline/pull-failed fallback.
set -uo pipefail
source "$(dirname "$0")/devcontainer-bin.sh"

repo="${1:?repo}"; config="${2:?template devcontainer.json}"; shift 2
[ "${1:-}" = "--" ] && shift

BIN="$(devcontainer_bin)" || exit 1
label="ctest=$(printf '%s' "$repo$config" | sha256sum | cut -c1-12)"
template_dir="$(dirname "$(dirname "$config")")"

up_pid=""
scratch_config=""

cleanup() {
  [ -n "$up_pid" ] && kill "$up_pid" >/dev/null 2>&1 || true
  local cids
  cids="$(docker ps -aq --filter "label=$label" 2>/dev/null)"
  [ -n "$cids" ] && docker rm -f $cids >/dev/null 2>&1 || true
  [ -n "$scratch_config" ] && rm -f "$scratch_config" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_container() {
  local i
  for i in $(seq 1 90); do
    [ -n "$(docker ps -q --filter "label=$label" 2>/dev/null)" ] && return 0
    # If `up` already exited (crashed/failed fast), stop waiting on it.
    if [ -n "$up_pid" ] && ! kill -0 "$up_pid" 2>/dev/null; then
      return 1
    fi
    sleep 1
  done
  return 1
}

start_up() {
  local cfg="$1"
  # Started in the background and never awaited directly -- see header comment, point 1.
  $BIN up --workspace-folder "$repo" --override-config "$cfg" \
      --id-label "$label" --id-label "ctest-test=1" --remove-existing-container \
      >/dev/null 2>&1 &
  up_pid=$!
}

build_local_image() {
  # Workspace-folder IS the template dir here, so the Dockerfile resolves correctly --
  # see header comment, point 2.
  local out
  out="$($BIN build --workspace-folder "$template_dir" 2>&1)"
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "$out" >&2
    return 1
  fi
  local image
  image="$(printf '%s\n' "$out" | grep -o '{"outcome":"success"[^$]*}' | tail -1 | jq -r '.imageName[0] // empty')"
  if [ -z "$image" ]; then
    echo "ctest: could not determine the built image name from 'devcontainer build' output" >&2
    echo "$out" >&2
    return 1
  fi
  printf '%s' "$image"
}

run_via_local_build() {
  # NOTE: this function is called directly (not via `$(...)`), specifically so its assignment
  # to the global `scratch_config` survives into the parent shell -- `cleanup()`'s trap relies
  # on that to remove the scratch file. Do not wrap this call in a command substitution.
  local image
  image="$(build_local_image)" || return 1
  # A scratch devcontainer.json identical to $config but with build/dockerfile replaced by a
  # concrete local image reference -- see header comment, point 2.
  scratch_config="$(mktemp /tmp/ctest-run-solo-XXXXXX.json)"
  jq --arg img "$image" 'del(.build, .dockerFile, .context) | .image = $img' "$config" > "$scratch_config"
  start_up "$scratch_config"
  wait_for_container || return 1
  active_config="$scratch_config"
  return 0
}

active_config="$config"
has_image_field="$(jq -r 'has("image")' "$config")"

if [ "$has_image_field" = "true" ]; then
  # Ghcr-digest-published state: try the direct pull-based config first.
  start_up "$config"
  if ! wait_for_container; then
    echo "ctest: pull of the published template image failed, falling back to a local build (loses the ghcr bit-for-bit guarantee for this run)" >&2
    [ -n "$up_pid" ] && kill "$up_pid" >/dev/null 2>&1 || true
    up_pid=""
    if ! run_via_local_build; then
      echo "ctest: container still not ready after local build fallback" >&2
      exit 1
    fi
  fi
else
  # Interim state (no published digest yet): build is the only option, always local.
  if ! run_via_local_build; then
    echo "ctest: container did not become ready after local build" >&2
    exit 1
  fi
fi

# exec: run the task in that same container (matched by id-label); propagate its exit code verbatim.
$BIN exec --workspace-folder "$repo" --override-config "$active_config" \
    --id-label "$label" --id-label "ctest-test=1" -- "$@"
code=$?

exit "$code"
