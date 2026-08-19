# node22-postgres16

Env devcontainer template (`kind: env`) for repos that need a running Postgres alongside the
Node runner to exercise integration tests — e.g. a test that opens `DATABASE_URL` and runs real
queries, instead of mocking the database. Runs via `docker compose` (a `runner` service plus a
`db` service) rather than a single container, and is torn down completely (`down -v
--remove-orphans`) after every run — see [`run-env.sh`](../../skills/container-testing/scripts/run-env.sh).

## Manifest

| Field | Value |
|---|---|
| `kind` | `env` |
| `orchestration` | `docker compose` (`.devcontainer/compose.test.yml`) |
| `service` (devcontainer target) | `runner` |
| `workspaceFolder` | `/workspace` |
| `image` | none (upstream images only, never published to ghcr) |
| `tasks` | target-repo-defined |

| Component | Pinned version |
|---|---|
| `runner` — Node.js | 22 (`node:22@sha256:0557ac14e0d45d02ed563067b82856ca5e7aa3437fa28d98d4350ea9c3d9494a`) |
| `db` — PostgreSQL | 16.4 (`postgres:16.4@sha256:e62fbf9d3e2b49816a32c400ed2dba83e3b361e6833e624024309c35d334b412`) |

Both are stock **upstream** images referenced directly by their upstream digest — this template
has **no owned layer** (no `Dockerfile`, no baked toolchain) and is therefore **never built or
published to ghcr**: `docker compose` pulls `node:22`/`postgres:16.4` straight from Docker Hub by
digest. If the `runner` service ever needs test tooling baked in beyond the target repo's own
deps, it becomes an owned image (a `Dockerfile` + ghcr publish, analogous to the
[`node22-lint-test`](../node22-lint-test/README.md) / [`go1.23-test`](../go1.23-test/README.md)
templates) — not the case here.

## What's wired up

- `runner` depends on `db` with `condition: service_healthy` — the target repo's task never
  starts before Postgres is actually accepting connections (`pg_isready`), not just "container
  started".
- `runner` gets `DATABASE_URL=postgres://postgres:postgres@db:5432/postgres` as a compose
  `environment` value — a target repo's own test code reads it directly (`process.env.DATABASE_URL`).
- The target repo is bind-mounted into `runner` at `/workspace` — for compose-based devcontainers
  this is **not** automatic (unlike the solo/Dockerfile templates), so `run-env.sh` passes it
  explicitly via `devcontainer up --mount type=bind,source=<repo>,target=/workspace`. See the
  `run-env.sh` header for the empirical confirmation.

## Tasks

Whatever the target repo's own scripts do with `DATABASE_URL` — e.g. `npm test` against a test
suite that reads it and runs real queries. There's no fixed task name; `run-env.sh` execs
whatever command is passed after `--`.

## Usage

Via the plugin's `ctest` command/scripts — `resolve-template.sh` picks this template up
automatically for any target repo that ships its own `compose.test.yml` (its dependencies are
declared there), and `run-env.sh` drives compose `up`/`exec`/`down -v --remove-orphans`:

```bash
skills/container-testing/scripts/run-env.sh <target-repo> \
    catalog/node22-postgres16/.devcontainer/devcontainer.json -- npm test
```

Or directly with the devcontainer CLI (note: this skips the `--mount`/`COMPOSE_PROJECT_NAME`/
absolute-`dockerComposeFile` workarounds `run-env.sh` applies — see its header comment for why
they're needed):

```bash
devcontainer up --workspace-folder <target-repo> --override-config catalog/node22-postgres16/.devcontainer/devcontainer.json
devcontainer exec --workspace-folder <target-repo> --override-config catalog/node22-postgres16/.devcontainer/devcontainer.json -- npm test
```

## Full teardown is load-bearing

`run-env.sh` runs `docker compose --project-name <derived-project> -f compose.test.yml down -v
--remove-orphans` **unconditionally** (in a `trap ... EXIT`), whether the task passed, failed, or
the script errored out before `exec` ever ran. Without `-v`, Postgres' data volume (the `postgres:16.4` image declares an anonymous `VOLUME /var/lib/postgresql/data`) would
survive the teardown and leak into the next run of the same target repo — silently reusing
whatever database state a previous (possibly failed) run left behind instead of starting from a
clean instance every time.
