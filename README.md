# Knarr

A Kubernetes controller, written in Gleam on the BEAM, that biases Deployment scale-down away from busy worker pods. It polls each worker over HTTP and sets `controller.kubernetes.io/pod-deletion-cost` (and optionally `cluster-autoscaler.kubernetes.io/safe-to-evict`) on the pod.

See [docs/OVERVIEW.md](docs/OVERVIEW.md) for the project overview, goals, worker contract draft and open questions.

AI agents start at [AGENTS.md](AGENTS.md), the one contract for working here; `CLAUDE.md` and the Copilot instructions only point to it.

## Getting started

You need [pixi](https://pixi.sh) 0.81.0 or later, git, curl and a POSIX shell. pixi installs everything else from `pixi.lock`: Gleam, Erlang/OTP, `just`, Python and every gate tool ([Decision 0003](docs/decisions/0003-tool-manager.md)).

From a fresh clone, run one command:

```sh
just initialize
```

Any recent `just` works; 1.51 and the pinned 1.58 are known to. Without one, run `sh scripts/initialize.sh`, which is exactly what the recipe runs. Afterwards the pinned `just` is at `.pixi/envs/default/bin/just`. `just initialize` is the one first-run command:

- It installs the pixi environment, exactly as `pixi.lock` pins it.
- It downloads the tools conda-forge lacks into `.tools/bin`, refusing any whose sha256 differs from `tools.txt`.
- It downloads Gleam's hex packages.
- In the primary checkout, it installs the pre-commit hook.

It never formats, stages, commits or pushes, and it is safe to rerun. Rerun it after a pull that moves a pin in `pixi.lock` or `tools.txt`. Until you do, `just check` fails at `env-check` rather than running the old tools.

**`just initialize` is the only step that needs network.** An agent needs an explicit network grant for that first run. After it, `just check` runs offline.

Then run the gate:

```sh
just check
```

`just --list` shows every recipe in six groups: setup, develop, format, check, audit and cluster.
The [local cluster guide](docs/how-to/local-cluster.md) covers the walking skeleton.

## The gate

`just check` is read-only. It runs each recipe in the check group through `scripts/checks/run_project_check.py`, which snapshots every tracked and untracked-unignored file first. The gate fails on the first recipe that changes any of them, even when that recipe passed ([Decision 0004](docs/decisions/0004-gate-checkers.md)).

Recipes may write ignored paths, such as `build/` and the `<title>.new` a failing snapshot test leaves; `just initialize` writes nothing else. Four recipes change tracked files on purpose, all outside the gate:

- `just fix` repairs formatting and lint findings.
- `just snapshots-review` and `just snapshots-accept` accept snapshot changes into `test/birdie_snapshots/`.
- `just birdie` runs any other birdie command. `just birdie reject` and `just birdie stale delete` can change tracked snapshot files.

The pre-commit hook runs the read-only config, `.pre-commit-config.yaml`. `just fix` runs `.pre-commit-fix.yaml`. The [testing reference](docs/reference/testing.md) covers the snapshot recipes and how `just check` stays read-only around them.

[CI](.github/workflows/ci.yml) runs `just check` on every pull request and
every push to `main`, using the same locked environment and `just initialize`
as contributors. Its aggregate `check` fails if any gate job fails, is cancelled,
or is skipped. `check` is the only required status check on `main`.
Add only required gate jobs to the aggregate's `needs` list. The initial kind
and kwok jobs stay outside it; the kind smoke job must demonstrate stability
for a stated period before becoming required (tickets 10 and 13).

The separate [audit](.github/workflows/audit.yml) runs `just links-audit` on
Mondays at 06:00 UTC and on manual dispatch. Remote link availability stays
outside the required gate.

Moving a pin is a manual edit, never a recipe:

- **A conda package:** edit its `==` line in `pixi.toml`, run `pixi update <package>`, read the `pixi.lock` diff, commit both files, and rerun `just initialize`.
- **A tools.txt download:** replace both platforms' lines with the new URL and sha256, and rerun `just initialize`.
- **A Gleam dependency:** edit `gleam.toml`, run `gleam deps download` (or `gleam deps update`), read the `manifest.toml` diff, and commit both. The gate fails while the two disagree.

## Specifications

Allium modules live in [docs/specs/](docs/specs/knarr.allium), configured by
`[allium] specs` in `checks.toml`. The root module is a skeleton; later tickets
add behaviour clauses. `just initialize` installs Allium 3.6.1 from the
checksum pins in `tools.txt`.

- `just check-specs` fails on every diagnostic, including informational ones.
- `just analyse-specs` fails on every finding or diagnostic.
- `just plan-spec docs/specs/knarr.allium` prints the module's test plan and obligation count.

Both checks run inside `just check`. They read the JSON reports because
Allium's exit status alone does not establish that a spec is clean. Planning
is a development command and is not part of the gate.

## Branches and worktrees

Each ticket is worked on its own branch, in its own git worktree. The branch name is the ticket's file name without `.md`: a two-digit ticket number, a hyphen and the ticket's slug. For example, the ticket `.scratch/bootstrap/issues/03-foundation.md` is worked on the branch `03-foundation`.

Hooks are installed from the primary checkout only, because every linked worktree shares its `.git/hooks`. In a linked worktree, `just initialize` skips the hook step with a notice and completes the rest, and `just check` passes without hooks.

The bootstrap tickets and the evidence the decision records cite live in `.scratch/`, which is tracked. Temporary work goes in `ai_tmp/`, which is ignored.

## Licence

knarr is licensed under the [Apache License 2.0](LICENSE).
