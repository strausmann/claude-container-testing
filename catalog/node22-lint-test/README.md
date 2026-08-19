# node22-lint-test

Solo devcontainer template for repos that ship their own `package.json` test/lint scripts.
Runs a target repo's `npm test` / `npm run lint` inside a reproducible container instead of
depending on whatever toolchain happens to be installed on the host.

## What's baked in

The image bakes in Node 22 plus a **pinned, TypeScript-5-compatible** eslint toolchain — pinned
specifically because a target repo's own local TypeScript-7-preview compiler was found to break
`typescript-eslint@8` (the toolchain drift that unblocked mcp-dockhand#213). Baking the toolchain
into the image means it does **not** depend on what's in the mounted target repo — only the
target repo's own app dependencies (its own `npm ci`) stay with the target repo.

| Component | Version |
|---|---|
| Node.js | 22 (base image, digest-pinned — see `.devcontainer/Dockerfile`) |
| typescript | 5.6.3 |
| eslint | 9.13.0 |
| @typescript-eslint/parser | 8.13.0 |
| @typescript-eslint/eslint-plugin | 8.13.0 |

## Tasks

- `test` — runs the target repo's `npm test` (expects a `test` script, e.g. `node --test`)
- `lint` — runs the target repo's `npm run lint` (expects a `lint` script, e.g. `eslint .`)

The pinned TS-5 lint toolchain is invoked as the exec command by `run-solo.sh`, mirroring
mcp-dockhand#213's container-lint pattern — the difference being that the toolchain now ships
inside the image itself, instead of being assumed present in the target repo or on the host.

## Usage

Via the plugin's `ctest` command/scripts (`run-solo.sh` picks this template up automatically for
any target repo with a `package.json`, see `skills/container-testing/scripts/resolve-template.sh`),
or directly with the devcontainer CLI:

```bash
devcontainer up --workspace-folder <target-repo> --override-config catalog/node22-lint-test/.devcontainer/devcontainer.json
devcontainer exec --workspace-folder <target-repo> --override-config catalog/node22-lint-test/.devcontainer/devcontainer.json -- npm test
```

## Publishing state (important — do not hand-edit)

`.devcontainer/devcontainer.json` currently builds from the local `Dockerfile` (`build:
{dockerfile}`). It does **not** yet reference a published image by digest, because nothing has
been published yet.

The CI publish job (Task 11) builds and pushes this template to
`ghcr.io/strausmann/claude-container-testing/node22-lint-test` on merge to `main`, and rewrites
`devcontainer.json` to `image: ghcr.io/strausmann/claude-container-testing/node22-lint-test@sha256:<digest>`
via an automated bot commit on first publish.

**Do not manually add an `image` field or a guessed digest before that CI job has run.** If
`devcontainer.json` is still on `build: {dockerfile}`, that means the template hasn't been
published yet — not that something is broken.

The digest-referencing mechanic itself (`devcontainer up`/`exec` accepting a
digest-referenced `image` in `devcontainer.json`) was empirically verified in this task against a
locally built image, ahead of Task 6's Go template depending on the same mechanic.
