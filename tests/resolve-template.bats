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
