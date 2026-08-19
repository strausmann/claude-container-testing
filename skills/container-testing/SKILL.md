---
name: container-testing
version: 1.0.0
description: >
  This skill should be used whenever a repository's tests, lint, or build need to run in a
  reproducible, toolchain-decoupled container instead of relying on whatever toolchain
  happens to be installed on the host. Container-first is the default testing posture in this
  environment: it is mandatory before any PR or merge (to guarantee parity with CI), whenever
  there is a toolchain conflict (wrong version on the host, or none installed at all), and
  whenever a devcontainer or testcontainers setup is itself being changed. Fast local runs
  remain fine for quick inner-loop iteration. Use when the user asks to "im Container testen",
  "container test", "reproduzierbar testen", "Toolchain-Konflikt", "CI-Parität", "devcontainer",
  "testcontainers", "run this in a container", "toolchain conflict", "reproducible test run",
  "test in isolation", "matches CI", or mentions ctest, the container-testing plugin, the
  devcontainer catalog, or reproducing a CI failure locally.
---

# Container Testing

**MANDATORY SKILL INVOCATION**

**This skill MUST be invoked (not optional) whenever any of the following applies:**

- Before opening or updating a pull request, and before any merge — container-based testing is
  the parity guarantee against CI, not a nice-to-have.
- The host's toolchain doesn't match what the repo needs (wrong Go/Node version, a toolchain
  that isn't installed at all, or a version conflict with something else already on the host).
- Someone asks to "test this reproducibly", "test in a container", "test like CI does", or
  reports that "it works on my machine but not in CI".
- A devcontainer, `testcontainers` setup, or anything under this plugin's `catalog/` is being
  added, changed, or debugged.

**NOT mandatory for:** quick inner-loop iteration while actively writing code — a fast local
`go test ./...` or `npm test` while poking at a single failing case is fine. Container-first
means "the last run before you call it done or open a PR runs in the container", not "every
keystroke".

## Why container-first is the default here

A host toolchain drifts: a different Go/Node version than CI, a globally installed linter that
disagrees with the pinned one, a system library CI doesn't have. Every one of those turns "tests
pass locally" into a false signal. Running the same devcontainer image that CI would use removes
the host as a variable — the test either passes in the exact environment that will judge the PR,
or it doesn't, with nothing else to blame.

## How it works

The single entry point is `scripts/ctest.sh`. It wires together the pieces below so nothing has
to be invoked by hand:

1. **Detect** — `resolve-template.sh <repo> <catalog>` inspects the target repo (`go.mod`,
   `package.json`, a `compose.test.yml`, …) and picks the matching catalog template, reporting
   both its name and its kind (`solo` or `env`). Pass `--template <name>` explicitly when
   detection is ambiguous or wrong (see `ctest list` for the catalog).
2. **Run** — the matching runner (`run-solo.sh` or `run-env.sh`, see the table below) brings the
   container up, execs the requested task (`test`, `lint`, `vuln`, …) against the repo mounted
   read-write inside it, and propagates that task's exit code verbatim — a failing test inside
   the container is a failing `ctest` run, not a swallowed warning.
3. **Clean up** — every runner tears down what it started before exiting, success or failure
   alike, so a crashed or `Ctrl-C`'d run never leaves a container, compose stack, or volume
   behind. Longer-lived local image cruft (stale pulls, orphaned local builds) is reclaimed
   separately with `prune.sh` — see Storage below.

### The two modes

| | **solo** | **env** |
|---|---|---|
| When the catalog picks it | Repo is self-contained — its own toolchain is all it needs (a `go.mod`, a `package.json` with its own test/lint scripts) | Repo declares dependencies the tests need running alongside it (e.g. a `compose.test.yml` requiring a real Postgres for integration tests) |
| What actually runs | One container, built from the template's `devcontainer.json`/Dockerfile, with the repo bind-mounted in | A `docker compose` stack — a runner service plus its declared dependencies (e.g. `runner` + `db`) |
| Runner script | `run-solo.sh` | `run-env.sh` |
| Teardown | Container + its `up` process are removed | Whole stack (`down -v --remove-orphans`): containers, named volumes, networks, orphans — a failed integration test never leaks a lingering Postgres |

Detection prefers `env` when the repo signals it needs one (a test-compose file present); it
falls back to `solo` otherwise. Either way, the repo is mounted read-write into the container —
the run edits the working tree exactly like a local test run would (coverage files, generated
fixtures, etc. land where you'd expect).

### Storage discipline: ghcr-published, digest-pinned, locally cached

Solo templates' images are built once and published to
`ghcr.io/strausmann/claude-container-testing/<template>`, referenced by **digest**, not by a
moving tag — so "the same template" means bit-for-bit the same image every time it's pulled,
not "whatever ghcr happens to be serving today". Env templates run straight from upstream images
declared in their own compose file (e.g. `node:22`, `postgres:16`) and are never published under
this plugin's own ghcr namespace.

Every pulled or locally-built image lands in the host's ordinary Docker image cache — nothing
plugin-specific to manage day to day. Over time that cache accumulates images for templates that
have since been removed from the catalog, plus dangling layers from rebuilds. `prune.sh`
reclaims exactly that: it removes local images whose template directory no longer exists in
`catalog/`, then runs a plain `docker image prune`. It never talks to ghcr and never touches an
image for a template still in the catalog — ghcr stays the source of truth, this is strictly
local housekeeping.

### Security note: two levels, not one

There are two different things running here, and only one of them ever sees Docker:

- **The `@devcontainers/cli` runs on the host.** It legitimately needs the Docker socket — it's
  the thing driving `docker`/`docker compose` to build and start containers in the first place.
  This is ordinary host tooling, the same trust level as running `docker` directly.
- **The test containers themselves never get the Docker socket.** Whatever the target repo's
  test suite does, it does it as an isolated process inside its own container, with no path back
  out to the host's Docker daemon. A compromised or malicious test dependency can't use the
  container it's running in to reach the host's other containers, volumes, or images.

Keep that distinction in mind before adding anything to a template's `devcontainer.json` or
compose file — a socket mount on the *runner* service is the one thing that would collapse this
boundary, and it should never be needed for running tests/lint/build.

## More detail

CLI-specific quirks worth knowing before debugging a runner script yourself (the `devcontainer
up` process that never returns, the relative-path resolution pitfall, exec dropping `PATH`) are
documented in the plugin `README.md`, not repeated here — this skill is the habit, not the
troubleshooting manual.
