# claude-container-testing

Run a repo's tests/lint/build in a reproducible, toolchain-decoupled dev container. This Claude
Code plugin provides a `/ctest` command and a `container-testing` skill that wire together a
small catalog of devcontainer templates so "test this like CI does" is one command instead of a
manually maintained Dockerfile per repo.

**Requires:** Docker + `@devcontainers/cli` (pinned, see [Install](#install)) + `bash` + `jq`.

## Why

A host toolchain drifts: a different Go/Node version than CI, a globally installed linter that
disagrees with the pinned one, a system library CI doesn't have. Every one of those turns "tests
pass locally" into a false signal. `ctest` runs the exact same container image CI would use,
removing the host as a variable — the test either passes in the environment that will actually
judge the PR, or it doesn't, with nothing else to blame. See the `container-testing` skill
(`skills/container-testing/SKILL.md`) for when this is mandatory (before every PR/merge, on any
toolchain conflict) versus optional (fast local inner-loop iteration).

## Install

As a Claude Code plugin, via the marketplace manifest in this repo
(`plugin-marketplace.json`) — see Claude Code's plugin documentation for adding a marketplace
and installing a plugin from it. Once installed, the `/ctest` command and the `container-testing`
skill are available in any project.

The plugin itself needs, on the host running Claude Code:

- **Docker**, running and reachable (`docker ps` works).
- **`@devcontainers/cli`, pinned to `0.80.0`**:
  ```bash
  npm install -g @devcontainers/cli@0.80.0
  ```
  If no global install is found, `skills/container-testing/scripts/devcontainer-bin.sh` falls
  back to `npx @devcontainers/cli@0.80.0` automatically — slower per-run (npx re-resolves the
  package) but works without the global install step. The pin lives in exactly one place
  (`CTEST_DEVCONTAINER_PIN` in that script); `.github/workflows/ci.yml` and
  `.github/workflows/publish-templates.yml` install the same pinned version and must be kept in
  sync with it by hand if it's ever bumped.
- **`jq`** and **`bash`** — used throughout the scripts under `skills/container-testing/scripts/`.

Nothing else needs installing per target repo: the catalog templates already bake in the
toolchains they run (see [ghcr publish, digest-pinning, and feature strategy](#ghcr-publish-digest-pinning-and-feature-strategy) below).

## Usage

### `/ctest`

```
/ctest <test|lint|build|env|list|prune> [path] [--template <name>] [--cmd "<...>"]
```

| Task | What it does |
|---|---|
| `test` | Run the resolved template's default test command (`npm test`, `go test ./...`, …). |
| `lint` | Run the resolved template's default lint command (`npm run lint`, `go vet ./...`). |
| `build` | Run the resolved template's default build command (`npm run build`, `go build ./...`). |
| `env` | Drop into an interactive shell in the resolved container. |
| `list` | Print the template catalog (`catalog/INDEX.md`). |
| `prune` | Remove local Docker images for templates no longer in the catalog (see [Storage discipline](#storage-discipline)). |

- `path` — target repo directory (default: `.`). Ignored by `list`/`prune`.
- `--template <name>` — use this catalog template instead of auto-detecting from `path`.
- `--cmd "<...>"` — run this command instead of the task's default command (e.g.
  `--cmd "golangci-lint run ./..."` on `go1.23-test`, whose default `lint` task runs `go vet`
  instead — the baked-in `golangci-lint` is still there, just not the default).

Examples:

```bash
/ctest test                          # test . , auto-detected template
/ctest lint ./my-service
/ctest test --template go1.23-test   # force a template instead of auto-detecting
/ctest build --cmd "npm run build:prod"
/ctest env ./my-service              # interactive shell in the resolved container
/ctest list
/ctest prune
```

### Modes: `solo` vs `env`

Every catalog template is one of two kinds (see `catalog/INDEX.md`'s `Kind` column):

| | **solo** | **env** |
|---|---|---|
| When it's picked | The repo is self-contained — its own toolchain is all it needs (a `go.mod`, or a `package.json` with its own test/lint scripts) | The repo declares dependencies its tests need running alongside it (currently: a `compose.test.yml` requiring a real Postgres for integration tests) |
| What runs | One container, from the template's `devcontainer.json`/`Dockerfile`, with the repo bind-mounted in | A `docker compose` stack — a `runner` service plus its declared dependencies (e.g. `runner` + `db`) |
| Runner script | `skills/container-testing/scripts/run-solo.sh` | `skills/container-testing/scripts/run-env.sh` |
| Teardown | Container (+ its `up` process) removed | Whole stack torn down: `docker compose ... down -v --remove-orphans` — containers, named volumes, networks, orphans |

`resolve-template.sh` prefers `env` when the target repo signals it needs one (a `compose.test.yml`
present), falling back to `solo` otherwise. Either way the target repo is mounted **read-write**
into the container — a `ctest` run edits the working tree exactly like a local run would (coverage
files, generated fixtures, etc. land where expected).

Direct script usage (bypassing `/ctest`'s dispatch), if a fixed script call is more convenient
than the command wrapper — e.g. from another script or CI job:

```bash
skills/container-testing/scripts/run-solo.sh <target-repo> catalog/go1.23-test/.devcontainer/devcontainer.json -- go test ./...
skills/container-testing/scripts/run-env.sh   <target-repo> catalog/node22-postgres16/.devcontainer/devcontainer.json -- npm test
```

### Catalog

`catalog/INDEX.md` is generated by `scripts/generate-index.sh` from each template's
`catalog/<name>/README.md` `## Manifest` block — never hand-edit `INDEX.md` directly, regenerate
it after changing a template's manifest. CI enforces this: `.github/workflows/ci.yml` regenerates
the index and fails the run if that changes anything (`git diff --exit-code catalog/INDEX.md`).

Current catalog (see each template's own `README.md` for the full detail — pinned component
versions, task list, usage):

| Template | Kind | Ships |
|---|---|---|
| [`go1.23-test`](catalog/go1.23-test/README.md) | `solo` | Go 1.23 + pinned `govulncheck`/`golangci-lint` |
| [`node22-lint-test`](catalog/node22-lint-test/README.md) | `solo` | Node 22 + pinned TS-5-compatible `eslint`/`typescript-eslint` |
| [`node22-postgres16`](catalog/node22-postgres16/README.md) | `env` | Node 22 runner + Postgres 16.4, via `docker compose` |

## ghcr publish, digest-pinning, and feature strategy

### Core toolchain baked in, not a devcontainer feature

Each **solo, owned-layer** template (one with its own `.devcontainer/Dockerfile` — currently
`go1.23-test` and `node22-lint-test`) bakes its pinned toolchain (linters, vuln scanners, …)
directly into the image with plain `RUN` steps, rather than composing it from [devcontainer
features](https://containers.dev/features). That's a deliberate choice, not an oversight:

- A feature is resolved and installed by the CLI **at `up` time**, against whatever's in the
  feature's own registry entry at that moment — the opposite of the pinned, bit-for-bit-reproducible
  image this plugin exists to provide (see [Why](#why)). Baking the toolchain into the `Dockerfile`
  means every version that matters (base image, linter, scanner) is pinned in exactly one file,
  reviewed in exactly one diff, and baked into the exact image the digest below points at.
- A **`devcontainer-feature.json`** is not part of any published, ghcr-hosted image in this
  catalog. If one is ever added to a template directory, it is for **local, opt-in development
  use only** (e.g. a contributor's own editor/IDE devcontainer convenience layered on top) — it
  must never be a dependency of what `ctest`/CI actually run, and it is never resolved as part of
  the `devcontainer build --push` step described below.
- `node22-postgres16` (the one `env` template) has no owned layer at all — its `runner` and `db`
  services are stock upstream images (`node:22`, `postgres:16.4`), referenced by their own
  upstream digest, and are therefore never built or published under this plugin's ghcr namespace
  either.

### Publish + digest-pinning (`.github/workflows/publish-templates.yml`)

`devcontainer build --push true` runs in **exactly one place** in this whole plugin: the
`publish-templates` GitHub Actions workflow, triggered by a push to `main` that touches
`catalog/*/.devcontainer/**`. Everywhere else — `run-solo.sh`'s local-build fallback, `run-env.sh`
— only builds or pulls, never pushes; see [Two levels, not one](#two-levels-not-one) below for why
that boundary matters.

For each **owned-layer** template that changed in that push (Node/Go — not `node22-postgres16`,
which has nothing to publish):

1. `devcontainer build --workspace-folder catalog/<template> --push true --image-name
   ghcr.io/strausmann/claude-container-testing/<template>:<short-sha>` — builds from that
   template's own `Dockerfile` and pushes the result, tagged with the triggering commit's short
   sha.
2. The resulting manifest digest is captured (`docker inspect --format='{{index .RepoDigests
   0}}'` against the just-pushed tag).
3. That template's `devcontainer.json` is rewritten: `build: {dockerfile}` is dropped (first
   publish) or the previous digest is replaced (every publish after), and
   `image: ghcr.io/strausmann/claude-container-testing/<template>@sha256:<digest>` is written in
   its place.
4. The rewritten `devcontainer.json` file(s) are committed back to `main` as a bot commit
   (`chore(catalog): pin published digest(s) [skip ci]`) and pushed.
5. Untagged/orphaned versions of the just-published package are pruned
   (`actions/delete-package-versions@v5`, `delete-only-untagged-versions: true` — **never**
   `false`: a tagged version, including every short-sha tag a previous publish left behind, is a
   reproducibility guarantee for anything that still references it, not clutter).

The upshot: after a template's first publish, `catalog/<template>/.devcontainer/devcontainer.json`
references a **digest**, not a moving tag — "the `node22-lint-test` template" means bit-for-bit the
same image every time it's pulled, not "whatever ghcr happens to be serving today". `run-solo.sh`
tries that direct, digest-pinned pull first and only falls back to a local rebuild
(re-losing the ghcr guarantee for that one run) if the pull fails — see [CLI quirks](#environment--cli-quirks-devcontainers-cli-0800), point 3.

**Open verification points — not yet confirmed against a real run, and deliberately not claimed
as working in the workflow's own comments (`.github/workflows/publish-templates.yml`):**

- Whether the default `GITHUB_TOKEN`'s `packages: write` scope is actually sufficient to push a
  brand-new, first-time **public** container package to ghcr.io.
- Whether that same `GITHUB_TOKEN` is sufficient for `actions/delete-package-versions@v5` to
  delete versions of a repo-owned container package — if not, the prune step needs its own
  scoped token, kept separate from the classic PAT below.
- Whether `devcontainer build --workspace-folder catalog/<template>` still rebuilds from that
  template's `Dockerfile` once `devcontainer.json` already holds a digest-pinned `image` (no
  `build` key) from a prior publish — untestable until a template has actually gone through a
  second publish cycle.
- The `[skip ci]` loop-prevention marker on the bot commit — relies on GitHub's documented
  push-event-level skip behavior; kept alongside a job-level `if:` guard as a second check.

### Manual, targeted image removal (separate from the automatic prune)

The automatic prune above only ever removes **untagged** versions of the package(s) a run just
published. Removing a specific **tagged** (faulty, or otherwise unwanted) image from ghcr is a
deliberate, human/Claude-triggered action — using the classic PAT stored as the Vaultwarden item
`GitHub PAT - GHCR Image Cleanup` — and is never wired into the automatic CI prune step. Keep the
two separate: CI cleans up its own untagged debris after every publish; a targeted tagged-image
deletion is a conscious decision made outside CI.

## Security note: two levels, not one

There are two different things running when `ctest` (or the publish workflow) executes, and only
one of them ever touches Docker:

- **The `@devcontainers/cli` runs on the host.** It legitimately needs the Docker socket — it's
  the thing driving `docker`/`docker compose` to build and start containers in the first place.
  This is ordinary host tooling, the same trust level as running `docker` directly (or, in CI,
  the same trust level as any other step in the runner).
- **The test containers themselves never get the Docker socket.** Whatever a target repo's test
  suite does, it does it as an isolated process inside its own container, with no path back out
  to the host's Docker daemon. A compromised or malicious test dependency in the *target repo*
  can't use the container it's running in to reach the host's other containers, volumes, or
  images.

Keep that distinction in mind before adding anything to a template's `devcontainer.json` or
compose file: a socket mount on the *runner*/target service is the one thing that would collapse
this boundary, and it should never be needed for running tests/lint/build.

## Evolving templates

Templates are named after the toolchain **major** version they ship (`go1.23-test`,
`node22-lint-test`) — that name is also the ghcr image path
(`ghcr.io/strausmann/claude-container-testing/<name>`) and, once published, appears pinned by
digest wherever a target repo or a CI config references this template directly. That naming
choice drives the policy for how a template is allowed to change:

- **In-place update (same name, new digest):** a patch/minor-level toolchain bump within the
  template's existing major version — e.g. rebasing the `golang:1.23` base image to a newer
  `1.23.x` digest, or bumping the pinned `golangci-lint`/`eslint` version. Edit the template's
  `Dockerfile` (and its `README.md` Component/Version table), merge to `main`. The publish
  workflow rebuilds, re-pushes, and rewrites the digest automatically — no template rename, no
  catalog restructuring, nothing a caller needs to change.
- **New template (new name):** a change that alters what the template fundamentally *is* — a new
  major toolchain version (Go 1.24, Node 24), a materially different baked-in toolchain, or a new
  kind of dependency (e.g. a Redis-backed `env` template alongside `node22-postgres16`) — gets a
  **new** `catalog/<new-name>/` directory and its own README/Manifest, rather than repurposing an
  existing template's name or Dockerfile. This keeps a name-plus-digest reference stable for as
  long as anything still points at it: nothing that pinned `go1.23-test@sha256:...` silently
  starts resolving to Go 1.24 content.
- **Removing a template:** delete `catalog/<name>/` (and re-run `scripts/generate-index.sh`).
  `skills/container-testing/scripts/prune.sh` then reclaims the *local* Docker cache for any
  image tagged under that now-catalog-less name — see [Storage discipline](#storage-discipline).
  The ghcr package itself is **not** automatically deleted by that removal; deleting a
  no-longer-catalogued package (or any of its still-tagged versions) is the same deliberate,
  human/Claude-triggered action described under [Manual, targeted image removal](#manual-targeted-image-removal-separate-from-the-automatic-prune)
  above, not an automatic side effect of editing the catalog.
- Adding a **new owned-layer template** (one with its own `Dockerfile`) also means adding a
  corresponding step to `.github/workflows/publish-templates.yml`'s prune section — see the
  `FLAGGED FOR REVIEW` comment there for why that isn't a dynamic loop.

### Storage discipline

Solo templates' images are pulled by digest from ghcr (bit-for-bit reproducible); `env` templates
pull straight from upstream (`node:22`, `postgres:16.4`, …) and are never published under this
plugin's own ghcr namespace. Every pulled/locally-built image lands in the host's ordinary Docker
image cache. Over time that accumulates images for templates since removed from the catalog, plus
dangling layers from rebuilds — `prune.sh` (`/ctest prune`) reclaims exactly that: local images
whose template directory no longer exists in `catalog/`, then a plain `docker image prune`. It
never talks to ghcr and never touches an image for a template still in the catalog.

## Environment / CLI quirks (`@devcontainers/cli` 0.80.0)

Three real, empirically-confirmed behaviors of the pinned CLI version that the scripts under
`skills/container-testing/scripts/` work around. Documented here so a future change doesn't
"simplify" one of these away without understanding why it's there — each is cross-referenced from
the script header comment that relies on it.

1. **`devcontainer up` starts the container but never returns.** Confirmed against both a
   Dockerfile-based (`run-solo.sh`) and a compose-based (`run-env.sh`) config: the container comes
   up and is fully usable, but the `up` process itself hangs instead of exiting once the container
   is ready. Both runner scripts start `up` in the background (`&`) and poll `docker ps --filter
   "label=<id-label>"` until the container appears (or `up`'s own process dies first, which means
   it failed fast) — never awaiting `up` directly. The background process and its container are
   always cleaned up in an `EXIT` trap, success or failure alike.
2. **`devcontainer exec` drops the container runtime `PATH`.** A base image's own `PATH` (set via
   `ENV PATH=...` or inherited from its parent image — e.g. `golang:1.23`'s
   `/go/bin:/usr/local/go/bin:...`) is visible to `docker exec` on the same container, but **not**
   to `devcontainer exec` against it — confirmed empirically (`go1.23-test`'s baked-in `go`,
   `govulncheck`, and `golangci-lint`, all installed outside `/usr/local/bin`, were reported "not
   found" until the full path was restated). The fix is `remoteEnv.PATH` in the template's
   `devcontainer.json`, spelled out explicitly — **not** `containerEnv.PATH` with
   `${containerEnv:PATH}` substitution, which 0.80.0 does not resolve (it's passed to `docker run
   -e` literally, unexpanded, breaking even the container's own keep-alive command). See
   `catalog/go1.23-test/README.md` for the full empirical writeup of both things tried.
3. **A relative `build.dockerfile` path resolves against `--workspace-folder`, not the
   override-config's own directory.** `run-solo.sh`/`run-env.sh` drive `up`/`exec` with
   `--workspace-folder <target-repo> --override-config <template's devcontainer.json>` — a
   target-repo workspace paired with a *different* directory's config, which is the whole point
   (one template config, driven against any matching target repo). But a still-`build`-based
   template's relative `Dockerfile`/`dockerComposeFile` path is resolved by the CLI against
   `<workspace-folder>/.devcontainer/` — i.e. the **target repo's** `.devcontainer/`, which
   doesn't have the template's `Dockerfile` — not against the override-config file's own
   directory, giving an ENOENT that has nothing to do with the target repo. `run-solo.sh` works
   around this by first running `devcontainer build --workspace-folder <template-dir>` (workspace
   folder **is** the template dir there, so the relative path resolves correctly), then driving
   `up`/`exec` against a scratch override-config with `build` swapped for the resulting local
   `image:` reference. `run-env.sh` applies the same idea to a compose config's
   `dockerComposeFile` path, rewriting it to an absolute path in its own scratch config instead.
   This is exactly why the `publish-templates.yml` build step's own `--workspace-folder
   catalog/<template>` also works correctly (workspace folder is the template dir there too) —
   see [ghcr publish, digest-pinning, and feature strategy](#ghcr-publish-digest-pinning-and-feature-strategy).
   Once a template is published with a digest-pinned `image:` field, this whole path-resolution
   pitfall stops applying to normal `ctest` runs (there's no `build`/`dockerComposeFile` left to
   resolve) — it only still matters for `run-solo.sh`'s offline/pull-failed local-build fallback,
   and for the publish workflow's own build step.

## Contributing a new template

1. `catalog/<name>/.devcontainer/` — a `devcontainer.json` (plus a `Dockerfile` if it's an owned
   solo template, or a `compose.test.yml` if it's an `env` template).
2. `catalog/<name>/README.md` — description, a `## Manifest` table (`kind`, `image`, `tasks` —
   see any existing template's README for the exact shape `scripts/generate-index.sh` expects),
   and whatever component-version/usage detail matters for that template.
3. If it's a `solo` template with detectable repo markers (a manifest file, a lockfile, …), add a
   detection branch to `skills/container-testing/scripts/resolve-template.sh`.
4. Run `scripts/generate-index.sh` and commit the resulting `catalog/INDEX.md` change alongside
   the new template — CI's drift gate fails the build otherwise.
5. If it's an owned-layer (`Dockerfile`-having) template, add its prune step to
   `.github/workflows/publish-templates.yml` (see the `FLAGGED FOR REVIEW` comment there) —
   otherwise its untagged ghcr versions never get cleaned up automatically.
