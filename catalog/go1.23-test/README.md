# go1.23-test

Solo devcontainer template for repos that ship a Go module (`go.mod`). Runs a target repo's
`go test` (and, via the same baked-in toolchain, `govulncheck` / `golangci-lint`) inside a
reproducible container instead of depending on whatever Go toolchain happens to be installed on
the host.

## Manifest

| Field | Value |
|---|---|
| `kind` | `solo` |
| `image` | `ghcr.io/strausmann/claude-container-testing/go1.23-test` |
| `tasks` | `test`, `vuln`, `lint` |

## What's baked in

The image bakes in Go 1.23 plus a **pinned Go test toolchain** — pinned for the same reason as the
Node lint template ([`node22-lint-test`](../node22-lint-test/README.md)): baking the toolchain into
the image means it does **not** depend on what's in the mounted target repo — only the target
repo's own module dependencies (its own `go mod download`) stay with the target repo. Both pinned
versions were confirmed to install and run cleanly against this exact base image (`go1.23.12`)
before commit — see the Task 6 report for the full build/verification transcript.

| Component | Version |
|---|---|
| Go | 1.23 (base image, digest-pinned — see `.devcontainer/Dockerfile`) |
| govulncheck | v1.1.3 |
| golangci-lint | v1.61.0 |

## `PATH` is set via `remoteEnv`, not `containerEnv` (load-bearing)

The `golang:1.23` base image sets `PATH=/go/bin:/usr/local/go/bin:...` so `go`, `govulncheck`, and
`golangci-lint` (installed to `/usr/local/go/bin` and `$GOPATH/bin` respectively) resolve without
qualification. `devcontainer exec` (CLI 0.80.0), however, does **not** carry that image/`docker
run`-time `PATH` through to the executed command — confirmed empirically: `docker exec` on the
same container shows the full image `PATH`, but `devcontainer exec` against it shows only the bare
OS default (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`), so `go`/`govulncheck`/
`golangci-lint` are reported "not found" unless `PATH` is restated. Two things were tried and only
the second worked:

- `containerEnv.PATH` with `${containerEnv:PATH}` variable substitution to extend the base image's
  `PATH` — **substitution is not resolved in `containerEnv`** (0.80.0 passes it to `docker run -e`
  literally, unexpanded), which broke even the container's own stay-alive keep-alive command
  (`sh: sleep: not found`) since the resulting `PATH` value was garbage.
- `remoteEnv.PATH` with the full path spelled out explicitly — **works**, and is what
  `.devcontainer/devcontainer.json` uses.

**Do not move this back to `containerEnv`** without re-verifying against a newer devcontainer CLI
that variable substitution actually resolves there.

## Tasks

- `test` — runs the target repo's `go test ./...`
- `vuln` — runs `govulncheck ./...` against the target repo's module
- `lint` — runs `golangci-lint run ./...` against the target repo's module

## Usage

Via the plugin's `ctest` command/scripts (`run-solo.sh` picks this template up automatically for
any target repo with a `go.mod`, see `skills/container-testing/scripts/resolve-template.sh`), or
directly with the devcontainer CLI:

```bash
devcontainer up --workspace-folder <target-repo> --override-config catalog/go1.23-test/.devcontainer/devcontainer.json
devcontainer exec --workspace-folder <target-repo> --override-config catalog/go1.23-test/.devcontainer/devcontainer.json -- go test ./...
```

## Publishing state (important — do not hand-edit)

`.devcontainer/devcontainer.json` currently builds from the local `Dockerfile` (`build:
{dockerfile}`). It does **not** yet reference a published image by digest, because nothing has
been published yet.

The CI publish job (Task 11) builds and pushes this template to
`ghcr.io/strausmann/claude-container-testing/go1.23-test` on merge to `main`, and rewrites
`devcontainer.json` to `image: ghcr.io/strausmann/claude-container-testing/go1.23-test@sha256:<digest>`
via an automated bot commit on first publish.

**Do not manually add an `image` field or a guessed digest before that CI job has run.** If
`devcontainer.json` is still on `build: {dockerfile}`, that means the template hasn't been
published yet — not that something is broken.

The digest-referencing mechanic itself (`devcontainer up`/`exec` accepting a digest-referenced
`image` in `devcontainer.json`) was already empirically verified in Task 4 against a locally built
image; this template relies on the same mechanic without repeating that verification.
