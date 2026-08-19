#!/usr/bin/env bats
# Tests for scripts/generate-index.sh (determinism/idempotency + drift guard) and
# skills/container-testing/scripts/prune.sh (local-cache-only image pruning).

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  GENERATE="$REPO_ROOT/scripts/generate-index.sh"
  PRUNE="$REPO_ROOT/skills/container-testing/scripts/prune.sh"
  INDEX="$REPO_ROOT/catalog/INDEX.md"
}

# --- generate-index.sh -------------------------------------------------------------------

@test "generate-index.sh lists every catalog template dir" {
  run bash "$GENERATE"
  [ "$status" -eq 0 ]
  for dir in "$REPO_ROOT"/catalog/*/; do
    name="$(basename "$dir")"
    [[ "$(cat "$INDEX")" == *"\`$name\`"* ]]
  done
}

@test "generate-index.sh is idempotent: running it twice yields an identical INDEX.md" {
  bash "$GENERATE"
  first="$(cat "$INDEX")"
  bash "$GENERATE"
  second="$(cat "$INDEX")"
  [ "$first" = "$second" ]
}

@test "generate-index.sh output is deterministic across independent runs in fresh dirs" {
  a="$(mktemp -d)"; b="$(mktemp -d)"
  cp -r "$REPO_ROOT/catalog" "$a/catalog"
  cp -r "$REPO_ROOT/scripts" "$a/scripts"
  cp -r "$REPO_ROOT/catalog" "$b/catalog"
  cp -r "$REPO_ROOT/scripts" "$b/scripts"

  bash "$a/scripts/generate-index.sh"
  bash "$b/scripts/generate-index.sh"

  diff "$a/catalog/INDEX.md" "$b/catalog/INDEX.md"
}

@test "drift guard: editing a README's Manifest and regenerating changes INDEX.md" {
  work="$(mktemp -d)"
  cp -r "$REPO_ROOT/catalog" "$work/catalog"
  cp -r "$REPO_ROOT/scripts" "$work/scripts"

  bash "$work/scripts/generate-index.sh"
  before="$(cat "$work/catalog/INDEX.md")"

  # Drift: change the go template's task list in its README manifest, WITHOUT regenerating.
  sed -i 's/| `tasks` | `test`, `vuln`, `lint` |/| `tasks` | `test`, `vuln`, `lint`, `NEWTASK` |/' \
    "$work/catalog/go1.23-test/README.md"

  # A stale committed INDEX.md (== "before") no longer matches a fresh regeneration -- this is
  # exactly what a CI `git diff --exit-code` after regenerating would catch.
  bash "$work/scripts/generate-index.sh"
  after="$(cat "$work/catalog/INDEX.md")"

  [ "$before" != "$after" ]
  [[ "$after" == *"NEWTASK"* ]]
}

@test "generate-index.sh fails loudly on a README with no 'kind' manifest field" {
  work="$(mktemp -d)"
  mkdir -p "$work/catalog/broken-template"
  cat > "$work/catalog/broken-template/README.md" <<'EOF'
# broken-template

No manifest at all.
EOF
  cp -r "$REPO_ROOT/scripts" "$work/scripts"

  run bash "$work/scripts/generate-index.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"kind"* ]]
}

# --- prune.sh -----------------------------------------------------------------------------

# The tests below `docker tag` this as a stand-in for a stale/kept local image. A fresh CI
# runner has no images cached at all, so pulling here (once for the whole file) is required --
# without it, every `docker tag busybox:1.36 ...` fails with "No such image" and the tests fail
# for a reason that has nothing to do with prune.sh itself. `docker pull` is idempotent, so this
# is a no-op on a machine that already has the image.
setup_file() {
  docker pull busybox:1.36 >/dev/null
}

teardown() {
  # Belt-and-braces: never leave test-tagged images behind, even if a test fails mid-way.
  docker rmi ghcr.io/strausmann/claude-container-testing/prune-test-stale:bats-test >/dev/null 2>&1 || true
  docker rmi ghcr.io/strausmann/claude-container-testing/node22-lint-test:bats-test >/dev/null 2>&1 || true
}

@test "prune.sh removes a local image whose name has no matching catalog dir" {
  docker tag busybox:1.36 ghcr.io/strausmann/claude-container-testing/prune-test-stale:bats-test

  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removing local image for catalog-less template 'prune-test-stale'"* ]]

  run docker images -q ghcr.io/strausmann/claude-container-testing/prune-test-stale:bats-test
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prune.sh keeps a local image whose name matches a catalog dir" {
  docker tag busybox:1.36 ghcr.io/strausmann/claude-container-testing/node22-lint-test:bats-test

  run bash "$PRUNE"
  [ "$status" -eq 0 ]

  run docker images -q ghcr.io/strausmann/claude-container-testing/node22-lint-test:bats-test
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "prune.sh never touches images outside its ghcr namespace" {
  run bash "$PRUNE"
  [ "$status" -eq 0 ]

  run docker images -q busybox:1.36
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
