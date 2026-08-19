#!/usr/bin/env bash
set -euo pipefail

repo="${1:?repo dir}"; catalog="${2:?catalog dir}"

# Env mode when the repo ships a test-compose file (its dependencies are declared there).
if [ -f "$repo/compose.test.yml" ] && [ -d "$catalog/node22-postgres16/.devcontainer" ]; then
  echo "node22-postgres16 env"; exit 0
fi

if [ -f "$repo/package.json" ] && [ -d "$catalog/node22-lint-test/.devcontainer" ]; then
  echo "node22-lint-test solo"; exit 0
fi

if [ -f "$repo/go.mod" ] && [ -d "$catalog/go1.23-test/.devcontainer" ]; then
  echo "go1.23-test solo"; exit 0
fi

echo "ctest: could not detect a toolchain for $repo. Pass --template <name> (see 'ctest list')." >&2
exit 2
