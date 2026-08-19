#!/usr/bin/env bash
# Prunes LOCAL Docker-cache copies of ghcr.io/strausmann/claude-container-testing/* images.
#
# ghcr is the source of truth for published templates -- this script never talks to it and never
# deletes anything there. It only ever runs `docker rmi`/`docker image prune` against the local
# Docker engine's own image cache, to reclaim disk on a machine that has run `ctest` against many
# templates/repos over time:
#
#   1. List every LOCAL image whose repository matches
#      `ghcr.io/strausmann/claude-container-testing/*` (a stale pull or a leftover local build
#      tagged that way).
#   2. For each, take the last path segment of the repository as the template name and check
#      whether `catalog/<name>` still exists. If the template has since been removed from the
#      catalog, `docker rmi` the local copy. Templates still present in the catalog are left
#      alone (this is a "was it removed from the catalog" prune, not a "clear everything" prune --
#      use `docker image prune` / `run-solo.sh`'s own cleanup for that).
#   3. Run `docker image prune -f` to also reclaim dangling (`<none>:<none>`) layers left behind
#      by rebuilds -- these have no repository/tag to map to a catalog dir at all.
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
catalog="$root/catalog"

if [ ! -d "$catalog" ]; then
  echo "prune.sh: no catalog dir at $catalog" >&2
  exit 1
fi

removed=0
kept=0

while IFS=$'\t' read -r ref id; do
  [ -z "$ref" ] && continue

  repo="${ref%:*}"
  name="${repo##*/}"

  if [ -d "$catalog/$name" ]; then
    kept=$((kept + 1))
    continue
  fi

  echo "prune.sh: removing local image for catalog-less template '$name': $ref ($id)"
  docker rmi "$ref" >/dev/null
  removed=$((removed + 1))
done < <(docker images --filter "reference=ghcr.io/strausmann/claude-container-testing/*" --format '{{.Repository}}:{{.Tag}}	{{.ID}}')

echo "prune.sh: removed $removed local image(s), kept $kept (still in catalog)"

echo "prune.sh: pruning dangling images"
docker image prune -f >/dev/null
