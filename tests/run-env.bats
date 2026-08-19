#!/usr/bin/env bats
# Tests for the env runner (compose up + exec against the mounted repo, full teardown incl. -v)

setup() {
  command -v docker >/dev/null || skip "docker required"
  SCRIPTS="$BATS_TEST_DIRNAME/../skills/container-testing/scripts"
  ROOT="$BATS_TEST_DIRNAME/.."
}
teardown() { docker rm -f $(docker ps -aq --filter "label=ctest-test=1") 2>/dev/null || true; }

@test "env run: integration test against postgres passes, stack fully torn down" {
  before=$(docker ps -aq | wc -l)
  run bash "$SCRIPTS/run-env.sh" "$ROOT/tests/fixtures/integration-repo" \
      "$ROOT/catalog/node22-postgres16/.devcontainer/devcontainer.json" -- npm test
  [ "$status" -eq 0 ]
  after=$(docker ps -aq | wc -l)
  [ "$before" -eq "$after" ]   # no ctest containers left behind (runner AND postgres)
}
