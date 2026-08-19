#!/usr/bin/env bats
# Tests for devcontainer CLI resolver

setup() { SCRIPTS="$BATS_TEST_DIRNAME/../skills/container-testing/scripts"; }

@test "devcontainer_bin resolves a global install when present" {
  source "$SCRIPTS/devcontainer-bin.sh"
  # simulate a global bin dir containing devcontainer
  tmp="$(mktemp -d)"; touch "$tmp/devcontainer"; chmod +x "$tmp/devcontainer"
  run devcontainer_bin "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == "$tmp/devcontainer" ]]
}

@test "devcontainer_bin falls back to npx when no global binary" {
  source "$SCRIPTS/devcontainer-bin.sh"
  tmp="$(mktemp -d)"   # empty, no devcontainer
  run devcontainer_bin "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == npx*@devcontainers/cli* ]]
}

@test "detects node repo -> node template, solo" {
  repo="$(mktemp -d)"; echo '{}' > "$repo/package.json"
  cat="$(mktemp -d)"; mkdir -p "$cat/node22-lint-test/.devcontainer" "$cat/go1.23-test/.devcontainer"
  run bash "$SCRIPTS/resolve-template.sh" "$repo" "$cat"
  [ "$status" -eq 0 ]; [[ "$output" == "node22-lint-test solo" ]]
}

@test "detects go repo -> go template, solo" {
  repo="$(mktemp -d)"; echo 'module x' > "$repo/go.mod"
  cat="$(mktemp -d)"; mkdir -p "$cat/node22-lint-test/.devcontainer" "$cat/go1.23-test/.devcontainer"
  run bash "$SCRIPTS/resolve-template.sh" "$repo" "$cat"
  [ "$status" -eq 0 ]; [[ "$output" == "go1.23-test solo" ]]
}

@test "detects compose.test.yml -> env mode" {
  repo="$(mktemp -d)"; echo '{}' > "$repo/package.json"; touch "$repo/compose.test.yml"
  cat="$(mktemp -d)"; mkdir -p "$cat/node22-postgres16/.devcontainer"
  run bash "$SCRIPTS/resolve-template.sh" "$repo" "$cat"
  [ "$status" -eq 0 ]; [[ "$output" == node22-postgres16\ env ]] || [[ "$output" == *" env" ]]
}

@test "unknown toolchain exits non-zero with guidance" {
  repo="$(mktemp -d)"; cat="$(mktemp -d)"
  run bash "$SCRIPTS/resolve-template.sh" "$repo" "$cat"
  [ "$status" -ne 0 ]; [[ "$output" == *"--template"* ]]
}

# --- ctest.sh (entry dispatch) -----------------------------------------------------------
# These two cases need no docker: "list" is a pure file read, and the resolve+dry-run case
# exercises arg-parsing + template resolution + dispatch construction only (CTEST_DRY_RUN=1
# makes ctest.sh echo the resolved run-solo.sh invocation instead of executing it).

@test "ctest.sh list prints the catalog index" {
  run bash "$SCRIPTS/ctest.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Template Catalog Index"* ]]
  [[ "$output" == *"node22-lint-test"* ]]
}

@test "ctest.sh --cmd dry-run resolves a node repo to node22-lint-test and echoes the run-solo invocation" {
  repo="$(mktemp -d)"; echo '{}' > "$repo/package.json"
  export CTEST_DRY_RUN=1
  run bash "$SCRIPTS/ctest.sh" --cmd "true" "$repo"
  unset CTEST_DRY_RUN
  [ "$status" -eq 0 ]
  [[ "$output" == *"run-solo.sh"* ]]
  [[ "$output" == *"catalog/node22-lint-test/.devcontainer/devcontainer.json"* ]]
  [[ "$output" == *"-- true" ]]
}
