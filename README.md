# Knarr

A Kubernetes controller, written in Gleam on the BEAM, that biases Deployment scale-down away from busy worker pods. It polls each worker over HTTP and sets `controller.kubernetes.io/pod-deletion-cost` (and optionally `cluster-autoscaler.kubernetes.io/safe-to-evict`) on the pod.

See [docs/OVERVIEW.md](docs/OVERVIEW.md) for the project overview, goals, worker contract draft and open questions.

## Getting started

You need [pixi](https://pixi.sh) 0.81.0 or later, git, curl and a POSIX shell. pixi installs everything else from `pixi.lock`: Gleam, Erlang/OTP, `just`, Python and every gate tool ([Decision 0003](docs/decisions/0003-tool-manager.md)).

From a fresh clone, run these two commands once:

```sh
pixi install --locked
.pixi/envs/default/bin/just initialize
```

The first installs the locked environment, which provides `just`. A `just` you installed some other way works too, if it is 1.27 or later. `just initialize` is the one first-run command:

- It installs the pixi environment, exactly as `pixi.lock` pins it.
- It downloads the tools conda-forge lacks into `.tools/bin`, refusing any whose sha256 differs from `tools.txt`.
- It downloads Gleam's hex packages.
- In the primary checkout, it installs the pre-commit hook.

It never formats, stages, commits or pushes, and it is safe to rerun.

**`just initialize` is the only step that needs network.** An agent needs an explicit network grant for that first run. After it, `just check` runs offline.

Then run the gate:

```sh
.pixi/envs/default/bin/just check
```

`just --list` shows every recipe in four groups: setup, develop, format and check.

## The gate

`just check` is read-only. It runs each recipe in the check group through `scripts/checks/run_project_check.py`, which snapshots every tracked and untracked-unignored file first. The gate fails on the first recipe that changes any of them, even when that recipe passed ([Decision 0004](docs/decisions/0004-gate-checkers.md)).

Only two recipes write files: `just initialize`, which writes ignored paths only, and `just fix`, which repairs formatting and lint findings in tracked files. The pre-commit hook runs the read-only config, `.pre-commit-config.yaml`. `just fix` runs `.pre-commit-fix.yaml`.

Moving a pin is a manual edit, never a recipe:

- **A conda package:** edit its `==` line in `pixi.toml`, run `pixi update <package>`, read the `pixi.lock` diff, and commit both files.
- **A tools.txt download:** replace both platforms' lines with the new URL and sha256, and rerun `just initialize`.
- **A Gleam dependency:** edit `gleam.toml`, run `gleam deps download` (or `gleam deps update`), read the `manifest.toml` diff, and commit both. The gate fails while the two disagree.

## Branches and worktrees

Each ticket is worked on its own branch, in its own git worktree. The branch name is the ticket's file name without `.md`: a two-digit ticket number, a hyphen and the ticket's slug. For example, the ticket `.scratch/bootstrap/issues/03-foundation.md` is worked on the branch `03-foundation`.

Hooks are installed from the primary checkout only, because every linked worktree shares its `.git/hooks`. In a linked worktree, `just initialize` skips the hook step with a notice and completes the rest, and `just check` passes without hooks.

The bootstrap tickets and the evidence the decision records cite live in `.scratch/`, which is tracked. Temporary work goes in `ai_tmp/`, which is ignored.

## Licence

knarr is licensed under the [Apache License 2.0](LICENSE).
