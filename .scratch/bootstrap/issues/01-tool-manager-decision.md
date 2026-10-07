# 01: Tool manager decision: pixi owns Gleam, OTP and the tools

**Context:** knarr is a Kubernetes controller in Gleam on the BEAM (OVERVIEW §1, §8). libpawdoku's D02 made pixi the owner of its tools while rustup kept the compiler. Here pixi can own the compiler too. conda-forge carries `gleam` 1.19.0 and `erlang` 29.1.1. It also has the repo tooling (`just`, `prek`, `typos`, `lychee`, `taplo`, `markdownlint-cli2`, `actionlint`, `shellcheck`) and the cluster tooling (`kubernetes-kind` 0.33, `kubernetes-client`, `kustomize`, `tilt`). All of it can sit in one lockfile.

**What to build:** A decision record stating that pixi owns Gleam, OTP and every repo and cluster tool through one manifest and one lockfile. It gives the exact manifest content and pins, and the escape hatch for tools pixi cannot supply. It closes the five open questions below with evidence, so the foundation ticket can write the files without guessing.

**Non-goals:** Writing the Justfile, the gate or CI (03, 05). Choosing which gate checkers to carry over (02). Choosing a local cluster (10).

**Blocked by:** None (can start immediately)

**MVP critical path:** yes. Every build, test and image ticket rests on this pin set.

**Status:** done. See [Decision 0003](../../../docs/decisions/0003-tool-manager.md) and its [evidence](../evidence/01/README.md).

- [x] Each package above is confirmed with `pixi search` on a stated date, with the exact version to pin. Both `linux-64` and `osx-arm64` solve.
- [x] **Verify 1, TLS:** conda-forge's Erlang `ssl`/`crypto` completes a `verify_peer` handshake with an explicit `cacertfile` and a hostname check, and it rejects a server signed by a different CA. Record the evidence, because S1 (14) builds on it.
- [x] **Verify 2, OTP major:** one place owns the OTP major. The record says how pixi, CI and both Dockerfile stages (build and runtime) read that owner or are checked against it.
- [x] **Verify 3, rebar3:** decide where `rebar3` comes from (it is not on conda-forge), pinned by version and checksum. Prove it by fetching and compiling one Erlang hex dependency that needs rebar3, such as `prometheus`.
- [x] **Verify 4, missing tools:** decide a source for each of `kubeconform`, `hadolint`, `helm`, `ripsecrets`, `editorconfig-checker`, `kwok`, `k3d`, `setup-envtest` and the Cluster Autoscaler binary (10 and 15 need them for the cluster spikes): a SHA-pinned prek hook, a checksum-pinned release download into a gitignored tool directory, or dropped with a reason. Record that the conda `k3d` package is an unrelated Python package.
- [x] **Verify 5, manifest.toml:** find out whether `gleam` can fail rather than rewrite `manifest.toml` when the manifest and `gleam.toml` disagree. If it cannot, name the workaround the read-only gate will use, such as a before-and-after comparison by the snapshot runner.
- [x] The record says how recipes reach the environment (a `PATH` export or `pixi run`) and why. It names the `pixi` commands for install, the lock check (never rewriting the lock) and the update.
- [x] The pixi version is pinned for local use and for CI.
- [x] A decision record is written. Follow-ups for 02 and 03 are drafted in the hand-back notes.

## Hand-back notes

These are corrections to the premise above, found while gathering the evidence on 2026-10-07:

- `helm` is on conda-forge as `kubernetes-helm` 4.3.0 and is in the manifest.
- A plain `pixi lock --check` rewrites `pixi.lock` on drift, even though it exits 1. The lock check is `pixi lock --check --offline --dry-run`.
- `pixi run` rewrites a stale lock and exits 0. This is the main reason recipes use a `PATH` export.
- The conda-forge `kubectl` (1.34.3) is three minors behind kind 0.33's default node image (v1.37.0).

### Follow-ups for 02

- The runtime for any kept or rewritten checker comes from `pixi.toml`. A Python checker adds `python` to the default feature of 0003's manifest. An Erlang escript needs nothing new, because `escript` is already in the environment. Do not add a second installer.
- No remote prek hook may install a tool that pixi or `.tools/bin` already provides. Such tools run as `repo: local`, `language: system` hooks, or through a recipe (0003, "One owner per pin").
- ripsecrets and editorconfig-checker come from `.tools/bin` as checksum-pinned release binaries (0003's escape-hatch table), not from their upstream prek hooks. The ripsecrets hook is `language: rust`, and knarr has no Rust toolchain. The ripsecrets wrapper decision should assume the binary is on `PATH`.
- The snapshot runner is the backstop for `manifest.toml`. 0003 relies on it to catch any gleam rewrite the pre-check misses.

### Follow-ups for 03

- Write `pixi.toml` exactly as 0003's manifest block, solve it, and commit `pixi.lock`. Gitignore `.pixi/`, `.tools/` and gleam's `build/`.
- Write `tools.txt` with the rebar3 lines from 0003. Add the ripsecrets and editorconfig-checker lines if 02 keeps them. Use the line format `name version platform url sha256 member`. Write the recipe that installs the host platform's lines into `.tools/bin`. It must refuse any download whose sha256 differs, and run `gh attestation verify` on rebar3 when `gh` is authenticated. `just initialize` runs `pixi install --locked`, then that recipe, before anything calls `gleam`.
- The Justfile exports `PATH` in this order: `.pixi/envs/default/bin`, `.pixi/envs/cluster/bin`, `.tools/bin`, then the inherited `PATH`. No recipe uses `pixi run`.
- The `lock-check` recipe is `pixi lock --check --offline --dry-run`. The plain `--check` form is ruled out because it writes.
- Guard `manifest.toml` with the pre-check from 0003 before any gleam recipe: `taplo get -o json` on both files, then the comparison in `evidence/01/manifest/requirements_check.escript`, ported in. End the gleam recipes with `git diff --exit-code manifest.toml`, under the snapshot runner.
- Prove that `just check` passes offline after `just initialize`, including gleam's build from its package cache. 0003 shows only the lock check passing offline.
- Pick one way to bootstrap `just` on a fresh clone and document it: `.pixi/envs/default/bin/just initialize` after `pixi install --locked`, or a separately installed `just`. Hooks run from git without the Justfile's `PATH`, so a hook entry calls the environment's `just` or tool by its repository-relative path. That is unverified here.

### For other lanes

- 05 pins setup-pixi by SHA (v0.11.0 is `9dabb60412d3d2d967a8d682f7ce01317af40514`, released 2026-10-06), with `pixi-version: v0.81.0` and `locked: true`. Its first native linux-64 run also confirms the TLS and rebar3 results, which were gathered under Rosetta.
- 10 picks a node image within kubectl's skew. 1.35 is the one minor that kind, kwok, CA and the conda kubectl all support. 10 adds the kwok, kwokctl, k3d and setup-envtest lines it keeps.
- 13 follows 0003's Dockerfile shape and OTP check. It weighs the runtime environment's 257 MB on linux-64. It adds the hadolint and kubeconform lines.
- 14 matches a hostname failure as a `bad_certificate` alert carrying `hostname_check_failed`. IP-SAN checking works locally on OTP 29.1.1.
- 15 pins the CA image by digest at the minor 10 picks.
