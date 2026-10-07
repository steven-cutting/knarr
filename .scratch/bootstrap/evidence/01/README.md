# Ticket 01 evidence

Evidence for [Decision 0003: Tool manager](../../../../docs/decisions/0003-tool-manager.md). Gathered on 2026-10-07 on an Apple-silicon Mac (Darwin arm64) with pixi 0.81.0. The linux-64 runs used Docker 29.4 with `ghcr.io/prefix-dev/pixi:0.81.0` (`sha256:788ae451641666e2d1f79d3dbe35392dfc7e9b394b16a3acb75c347f3badb2ab`) forced to `linux/amd64`, so they ran under Rosetta.

Each script exits non-zero on an unexpected result, and each `.txt` file is the transcript of the script with the same name. Every script writes only to the work directory it is given, never to this directory.

## Rerun everything

```sh
sh .scratch/bootstrap/evidence/01/run-all.sh "$(mktemp -d)"
```

This needs network, pixi 0.81.0, curl, an authenticated `gh` (for asset digests and the rebar3 Sigstore check), and Docker (for `linux.sh` and the autoscaler digests). It rewrites every transcript here. A changed transcript is either a new upstream release or a finding. `run-all.sh` stops at the first script that fails. `search.sh` is meant to fail (`DIFFERS`) once conda-forge publishes a newer version of a pinned package. That failure means the pins in 0003 need a deliberate move. It does not mean the script is broken.

## Scripts

| Script | Transcript | What it shows |
|---|---|---|
| [search.sh](search.sh) | [search.txt](search.txt) | Every conda-forge package at its pinned version on both platforms, the tools absent from conda-forge, and that conda-forge's `k3d` is a Python package |
| [solve.sh](solve.sh) `<dir>` | [solve.txt](solve.txt) | [pixi.toml.proposed](pixi.toml.proposed) solves and installs on both platforms; one erlang and openssl build per platform; no activation scripts; tools run from a `PATH` export; which pixi commands rewrite `pixi.lock` on drift |
| [tls/run.sh](tls/run.sh) `<env> <dir>` | [tls.txt](tls.txt) | Verify 1: [tls_check.escript](tls/tls_check.escript) with certificates from [gen-certs.sh](tls/gen-certs.sh). Six cases: right CA by name and by IP SAN, wrong CA, wrong name, missing IP SAN |
| [rebar3/fetch.sh](rebar3/fetch.sh) `<bin>` and [rebar3/run.sh](rebar3/run.sh) `<env> <bin> <dir>` | [rebar3.txt](rebar3.txt) | Verify 3: the sha256-pinned and Sigstore-verified rebar3 builds the [probe](rebar3/probe/)'s `prometheus` dependency, and the build fails without rebar3 |
| [manifest/run.sh](manifest/run.sh) `<env> <bin> <dir>` | [manifest.txt](manifest.txt) | Verify 5: gleam has no lock flag and rewrites `manifest.toml` on every disagreement. The backstop (`git diff --exit-code`) catches a rewrite, and the pre-check ([requirements_check.escript](manifest/requirements_check.escript)) refuses one without writing |
| [tools.sh](tools.sh) `<dir>` | [tools.txt](tools.txt) | Verify 4: each missing tool's release assets for both platforms are hashed and matched against upstream digests and checksum files. The output ends with the pin list and the autoscaler image digests |
| [linux.sh](linux.sh) `<solve-dir>` | [linux.txt](linux.txt) | Verify 1, 2 and 3 on linux-64 from the lock `solve.sh` produced. TLS runs in both the `default` and the `runtime` environment. The output includes the runtime environment's size and the Rosetta control |

`<env>` is an installed pixi environment, for example `<solve-dir>/.pixi/envs/default`.

## Rosetta

Under Rosetta, the BEAM JIT's dual-mapped code memory fails, and every Erlang node dies at boot in `prim_tty`. The official `erlang:29` image fails in the same way. `linux.sh` records that control. It then sets `ERL_FLAGS="+JMsingle true"`, but only when `/proc/cpuinfo` names the Rosetta CPU. Native linux-64 needs no flag. The first native run is 05's CI.
