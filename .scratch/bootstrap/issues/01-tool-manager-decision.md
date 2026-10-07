# 01: Tool manager decision: pixi owns Gleam, OTP and the tools

**Context:** knarr is a Kubernetes controller in Gleam on the BEAM (OVERVIEW §1, §8). libpawdoku's D02 made pixi the owner of its tools while rustup kept the compiler. Here pixi can own the compiler too. conda-forge carries `gleam` 1.19.0 and `erlang` 29.1.1. It also has the repo tooling (`just`, `prek`, `typos`, `lychee`, `taplo`, `markdownlint-cli2`, `actionlint`, `shellcheck`) and the cluster tooling (`kubernetes-kind` 0.33, `kubernetes-client`, `kustomize`, `tilt`). All of it can sit in one lockfile.

**What to build:** A decision record stating that pixi owns Gleam, OTP and every repo and cluster tool through one manifest and one lockfile. It gives the exact manifest content and pins, and the escape hatch for tools pixi cannot supply. It closes the five open questions below with evidence, so the foundation ticket can write the files without guessing.

**Non-goals:** Writing the Justfile, the gate or CI (03, 05). Choosing which gate checkers to carry over (02). Choosing a local cluster (10).

**Blocked by:** None (can start immediately)

**MVP critical path:** yes. Every build, test and image ticket rests on this pin set.

**Status:** ready-for-agent

- [ ] Each package above is confirmed with `pixi search` on a stated date, with the exact version to pin. Both `linux-64` and `osx-arm64` solve.
- [ ] **Verify 1, TLS:** conda-forge's Erlang `ssl`/`crypto` completes a `verify_peer` handshake with an explicit `cacertfile` and a hostname check, and it rejects a server signed by a different CA. Record the evidence, because S1 (14) builds on it.
- [ ] **Verify 2, OTP major:** one place owns the OTP major. The record says how pixi, CI and both Dockerfile stages (build and runtime) read that owner or are checked against it.
- [ ] **Verify 3, rebar3:** decide where `rebar3` comes from (it is not on conda-forge), pinned by version and checksum. Prove it by fetching and compiling one Erlang hex dependency that needs rebar3, such as `prometheus`.
- [ ] **Verify 4, missing tools:** decide a source for each of `kubeconform`, `hadolint`, `helm`, `ripsecrets` and `editorconfig-checker`: a SHA-pinned prek hook, a checksum-pinned release download into a gitignored tool directory, or dropped with a reason. Record that the conda `k3d` package is an unrelated Python package.
- [ ] **Verify 5, manifest.toml:** find out whether `gleam` can fail rather than rewrite `manifest.toml` when the manifest and `gleam.toml` disagree. If it cannot, name the workaround the read-only gate will use, such as a before-and-after comparison by the snapshot runner.
- [ ] The record says how recipes reach the environment (a `PATH` export or `pixi run`) and why. It names the `pixi` commands for install, the lock check (never rewriting the lock) and the update.
- [ ] The pixi version is pinned for local use and for CI.
- [ ] A decision record is written. Follow-ups for 02 and 03 are drafted in the hand-back notes.
