# Ticket 03 evidence

Evidence for [ticket 03](../../issues/03-foundation.md). Gathered on 2026-10-07 on an Apple-silicon Mac (Darwin arm64) with pixi 0.81.0. Nothing here ran on linux-64; 05's first CI run is the first native linux-64 gate.

[fresh-clone.sh](fresh-clone.sh) exits non-zero on any unexpected result, and [fresh-clone.txt](fresh-clone.txt) is its transcript. It writes only to the work directory it is given.

## Rerun

```sh
sh .scratch/bootstrap/evidence/03/fresh-clone.sh <repository> <branch> "$(mktemp -d)"
```

This needs network for the first run inside the clone, and pixi 0.81.0, git and curl. It uses a `just` on the host's `PATH` if there is one, and `sh scripts/initialize.sh` otherwise. The offline run uses `sandbox-exec` on macOS and `unshare -rn` on Linux.

## What it shows

In a fresh clone of the branch, which is a primary checkout:

- `just initialize` alone, run with the host's own `just` before any pixi environment exists, completes. It installs the pre-commit hook and leaves the worktree clean. The first-run time it prints is with warm pixi and Gleam caches on this machine, so it is not a cold-machine time. 11 times a cold one.
- With outbound network denied, `curl https://github.com` fails and `just check` passes, including the Gleam build and tests from the package cache. The worktree is unchanged afterwards.
- With `PATH=/usr/bin:/bin`, as git runs hooks, a commit runs every hook through `scripts/with-env.sh`. markdownlint-cli2, a `#!/usr/bin/env node` script, runs, and an unformatted Gleam file is refused.
- Moving the `shellcheck` pin in `pixi.toml` fails `just lock-check` (exit 1) and leaves `pixi.lock` byte for byte unchanged.
- Widening a range in `gleam.toml` fails `just check` at `manifest-check`, before any gleam command runs, and leaves `manifest.toml` unchanged.
- A recipe that appends to `README.md` fails the snapshot runner with status 1, naming `README.md`.

The linked-worktree path is shown by the pytest test `scripts/checks/tests/test_install_hooks.py`, and by `just initialize` in the ticket's own linked worktree, which printed the skip notice and installed no hook.
