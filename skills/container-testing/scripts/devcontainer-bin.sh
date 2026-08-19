#!/usr/bin/env bash
# Resolve a runnable devcontainer CLI. Global (pinned) install preferred; npx fallback.
# The CLI is a HOST tool — it drives Docker on the host; the test containers never get the socket.
CTEST_DEVCONTAINER_PIN="${CTEST_DEVCONTAINER_PIN:-0.80.0}"
devcontainer_bin() {
  local bindir="${1:-$(npm config get prefix 2>/dev/null)/bin}"
  if [ -x "$bindir/devcontainer" ]; then
    printf '%s' "$bindir/devcontainer"; return 0
  fi
  if command -v npx >/dev/null 2>&1; then
    printf 'npx @devcontainers/cli@%s' "$CTEST_DEVCONTAINER_PIN"; return 0
  fi
  echo "ctest: @devcontainers/cli not found. Install it: npm i -g @devcontainers/cli@$CTEST_DEVCONTAINER_PIN" >&2
  return 1
}
