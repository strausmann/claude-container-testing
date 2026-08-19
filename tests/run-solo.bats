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
