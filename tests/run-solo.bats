#!/usr/bin/env bats
# Tests for the solo runner (up + exec against the mounted repo, verbatim exit code)

setup() {
  command -v docker >/dev/null || skip "docker required"
  SCRIPTS="$BATS_TEST_DIRNAME/../skills/container-testing/scripts"
  ROOT="$BATS_TEST_DIRNAME/.."
}
teardown() { docker rm -f $(docker ps -aq --filter "label=ctest-test=1") 2>/dev/null || true; }

@test "solo run: passing command exits 0" {
  run bash "$SCRIPTS/run-solo.sh" "$ROOT/tests/fixtures/node-repo" \
      "$ROOT/catalog/node22-lint-test/.devcontainer/devcontainer.json" -- node --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"v22"* ]]
}
@test "solo run: failing command propagates non-zero" {
  run bash "$SCRIPTS/run-solo.sh" "$ROOT/tests/fixtures/node-repo" \
      "$ROOT/catalog/node22-lint-test/.devcontainer/devcontainer.json" -- node -e "process.exit(3)"
  [ "$status" -eq 3 ]
}

# The catalog's own devcontainer.json still uses `build:` (no published ghcr digest yet, see
# Task 11), so the tests above only ever exercise the `has_image_field == false` branch. The
# `true` branch (direct-pull-first, the normal post-publish path) needs its own synthetic config
# to be reachable at all right now. Uses `node:22` -- already pulled locally in this environment
# -- so `up` resolves the image from the local cache with no real registry pull involved.
image_branch_config() {
  local cfg
  cfg="$(mktemp /tmp/ctest-run-solo-image-XXXXXX.json)"
  cat > "$cfg" <<'JSON'
{
  "name": "ctest-image-branch-fixture",
  "image": "node:22",
  "containerEnv": { "CI": "true" },
  "overrideCommand": true
}
JSON
  printf '%s' "$cfg"
}

@test "solo run: image field (direct-pull branch) exits 0" {
  local cfg
  cfg="$(image_branch_config)"
  run bash "$SCRIPTS/run-solo.sh" "$ROOT/tests/fixtures/node-repo" "$cfg" -- node --version
  rm -f "$cfg"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v22"* ]]
}

@test "solo run: image field (direct-pull branch) propagates non-zero" {
  local cfg
  cfg="$(image_branch_config)"
  run bash "$SCRIPTS/run-solo.sh" "$ROOT/tests/fixtures/node-repo" "$cfg" -- node -e "process.exit(3)"
  rm -f "$cfg"
  [ "$status" -eq 3 ]
}

@test "solo run: go test passes in the go template" {
  run bash "$SCRIPTS/run-solo.sh" "$ROOT/tests/fixtures/go-repo" \
      "$ROOT/catalog/go1.23-test/.devcontainer/devcontainer.json" -- go test ./...
  [ "$status" -eq 0 ]
}
