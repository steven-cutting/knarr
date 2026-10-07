# Ticket 02 evidence

Evidence for [Decision 0004: Gate checkers](../../../../docs/decisions/0004-gate-checkers.md). Gathered on 2026-10-07 on an Apple-silicon Mac (Darwin arm64) with pixi 0.81.0. All of it ran natively on osx-arm64. The linux-64 rows are conda-forge solves and release-asset hashes; no linux-64 binary ran here.

Each script exits non-zero on an unexpected result, and each `.txt` file is the transcript of the script with the same name. Every script writes only to the work directory it is given, never to this directory. `provenance.sh` only reads the clone it is given and never fetches into it.

## Rerun everything

```sh
sh .scratch/bootstrap/evidence/02/run-all.sh "$(mktemp -d)" ~/projects/biscuit_games_tooling
```

This needs network, pixi 0.81.0, curl, an authenticated `gh` and a clone of [biscuit_games_tooling](https://github.com/steven-cutting/biscuit_games_tooling) whose `origin/main` is current. It rewrites every transcript here. `python.sh` is meant to fail once conda-forge publishes a newer pytest, ruff or 3.14 python. That failure means the pins in 0004 need a deliberate move, not that the script is broken. `provenance.sh` is meant to fail if anything under `src/` changes on upstream `main` after `v0.3.0`.

## Scripts

| Script | Transcript | What it shows |
|---|---|---|
| [provenance.sh](provenance.sh) `<clone>` | [provenance.txt](provenance.txt) | Tag `v0.3.0` is commit `6c5c07f` locally and on the remote; upstream `main` changes only the README and CHANGELOG after it; the tree has no licence file and `pyproject.toml` no `license` field; the sha256 and line count of each of the seven source files |
| [python.sh](python.sh) `<dir>` | [python.txt](python.txt) | python 3.14.8, pytest 9.1.1 and ruff 0.16.10 on both platforms; 0003's [pixi.toml.proposed](../01/pixi.toml.proposed) solves with and without them; the default environment grows from 521 MB to 622 MB on osx-arm64; `tomllib` and `hashlib.file_digest` import; `python3` resolves through a `PATH` export alone |
| [allium.sh](allium.sh) `<dir>` | [allium.txt](allium.txt) | allium-tools 3.6.1 for linux-64 and osx-arm64 matches both the checksums `install_allium.py` carried and GitHub's asset digests; each archive holds one member, `allium`; the macOS binary prints `allium 3.6.1`; the two `tools.txt` lines; 3.6.1 is still the newest release |
| [ripsecrets.sh](ripsecrets.sh) `<dir>` | [ripsecrets.txt](ripsecrets.txt) | The proposed wrapper [ripsecrets-redacted.sh](ripsecrets-redacted.sh), run against 0003's pinned ripsecrets 0.1.11 in throwaway worktrees: a clean pass, a planted token (status 1, fixed message, token absent from the output), other non-zero statuses kept and suppressed, and refusals (status 2) for a missing or non-executable binary and for a directory outside Git |

## The ripsecrets wrapper

[ripsecrets-redacted.sh](ripsecrets-redacted.sh) is the rewrite 0004 proposes. 03 copies it into `scripts/checks/`. It was built test-first: each case in `ripsecrets.sh` was written and seen to fail before the wrapper was changed to pass it. The planted token is made at run time, so no committed file carries one, and the transcript never prints it. The control case shows that bare ripsecrets does print it.

One ripsecrets behaviour the wrapper inherits: given a path that does not exist, ripsecrets 0.1.11 prints an error and exits 0. prek passes only staged paths that exist, so the hook never meets this.
