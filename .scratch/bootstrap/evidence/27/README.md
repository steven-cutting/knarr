# Ticket 27 evidence

Evidence for [Decision 0013: Dependency updates and audit](../../../../docs/decisions/0013-dependency-updates-and-audit.md). Gathered on 2026-10-09 and 2026-10-10 (UTC) on an Apple M5 Pro (Darwin arm64) with OrbStack 2.2.3, whose Docker engine is 29.4.0 (linux/arm64) with buildx 0.33.0, pixi 0.81.0, Renovate 44.149.0 from `ghcr.io/renovatebot/renovate`, pinned by digest, and grype 0.120.1 from the pixi `audit` environment. The transcripts' `revision:` line is the commit checked out when they ran; `sources.txt` carries only its date, and `ci-audit.txt` names the run's commit in its `event:` line. No app was installed, no repository setting changed, no issue or pull request was created, and no image was pushed.

Each script exits non-zero on an unexpected result, and each `.txt` file is the transcript of the script with the same name. Every script writes only to the work directory it is given, apart from the probe image `grype-probe.sh` builds for part 3 and removes, which is named after this worktree. Every container a script starts is removed when it exits. `ci-audit.sh` takes no work directory: it only reads, through `gh`.

## Network the maintainer authorized for this spike

On 2026-10-09:

- **Reads:** vendor documentation; registry reads (Docker Hub, ghcr.io, registry.k8s.io, conda-forge, hex.pm); the Renovate dry run's lookups; and OSV.dev queries.
- **The conda-forge relock** that added grype.
- **Authorized during the work:** a read-only `gh auth token` for Renovate's github.com lookups, installing grype, and grype's vulnerability database.
- **Later, each confirmed again and done on 2026-10-10 (UTC):** pushing the branch, and one `audit.yml` run on it, run 38015514089, dispatched at `d5c7178`.

## Rerun everything

```sh
sh .scratch/bootstrap/evidence/27/run-all.sh "$(mktemp -d)"
```

**Requirements:**

- network;
- docker with buildx;
- curl, perl and git;
- an authenticated `gh`, whose token Renovate's github.com lookups need;
- pixi;
- the pixi default and audit environments (`just initialize`, `just audit-install`).

It took under two minutes here with the Renovate image already pulled. grype's database makes the work root about 3 GB. It rewrites every transcript here, stops at the first script that fails, and checks at the end that no Renovate container and no probe image is left; another worktree's probe image does not count.

`ci-audit.sh` is not part of `run-all.sh`, because it needs the id of a finished `audit.yml` run. It needs an authenticated `gh`, and prints the transcript `ci-audit.txt` holds:

```sh
sh .scratch/bootstrap/evidence/27/ci-audit.sh 38015514089
```

## Scripts

| Script | Transcript | What it shows |
| --- | --- | --- |
| [lib.sh](lib.sh) | (sourced by every script) | The worktree, the pixi python, the pinned Renovate image, the work-directory rule, and the export of the committed tree at HEAD that the scripts read instead of the working tree |
| [inventory.sh](inventory.sh) `<dir>` | [inventory.txt](inventory.txt) | Every pin in the committed tree, counted from the files themselves rather than from Renovate, with what covers it or the gap 0013 records |
| [sources.sh](sources.sh) `<dir>` | [sources.txt](sources.txt) | Twenty vendor pages fetched with their sha256, each phrase 0013 cites looked for in the page's text, and the scanners conda-forge carries. A missing phrase is a dated finding, not a failure; three are expected to be missing |
| [digests.sh](digests.sh) `<dir>` | [digests.txt](digests.txt) | The Dockerfile's two base images: each pinned digest is an OCI index with linux/amd64 and linux/arm64 manifests, and whether the tag still names it |
| [renovate.sh](renovate.sh) `<dir>` | [renovate.txt](renovate.txt) | `renovate-config-validator --strict`; a lookup on HEAD (every pin extracted, the two switched off, what is pending today); a lookup on a stale copy with real older pins rolled back, each manager proposing in its group's branch; and setup-pixi's native `pixi-version` reading proposing nothing |
| [osv-probe.sh](osv-probe.sh) `<dir>` | [osv-probe.txt](osv-probe.txt) | `hex_audit.py` live: the committed tree, a `plug 1.3.0` control and an OTP 27.3.2 control, and OSV's `GIT` record of CVE-2025-32433 |
| [grype-probe.sh](grype-probe.sh) `<dir>` | [grype-probe.txt](grype-probe.txt) | grype on the pinned ubuntu:24.04 runtime base, amd64, read from the registry: every match, those with a fix, and what `just image-scan`'s flags decide. Part 3: the runtime environment's linux-64 packages that have a conda record on this host, scanned as an image and as a directory, with the catalogers syft selects for each and the matches with a fix; it names the packages it could not scan |
| [run-all.sh](run-all.sh) `<root>` | | All of the above, in order, then the leftover check |
| [ci-audit.sh](ci-audit.sh) `<run-id>` | [ci-audit.txt](ci-audit.txt) | `gh` reads of one `audit.yml` run: its jobs, the hex verdict, grype's table on the real linux/amd64 knarr image, and the link audit's errors. A job's failure is a finding, not a failure of the script. Run separately, not by `run-all.sh`; needs an authenticated `gh` |

## Notes

- **The token never reaches a transcript.** `renovate.sh` passes `gh auth token` to the container by name in its environment, and fails if the token's value appears in any Renovate log.
- **Lookup mode stops before branches.** The local platform creates no branch, no issue and no pull request. So the transcripts show grouping through branch names but not the holds. The holds are modelled by `scripts/checks/tests/test_dependency_pins.py`, and ticket 41 sees them on the Dependency Dashboard.
- **The stale copy's rollbacks name the live pins.** When a pin moves, `renovate.sh` stops and names the rollback to move with it. A Renovate pull request that lands will do this; it does not mean the script is broken.
- **Point-in-time reads.** The pending proposals, the advisories and grype's database are as of the run's date. The live audit's verdict may differ next week, and the image scan's first finding should clear once Ubuntu republishes noble with the fixed `libssl3t64` and the base image moves.
- **A failed request is never evidence.** `hex_audit.py` fails closed. `sources.sh` stops on a fetch failure rather than reporting a phrase missing. `run-all.sh` fails if it cannot list Docker's containers rather than reporting none left.
