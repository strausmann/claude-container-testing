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
