# Ticket 28 evidence

Evidence for [Decision 0012: Release and packaging](../../../../docs/decisions/0012-release-and-packaging.md). Gathered on 2026-10-09 (UTC) on an Apple M5 Pro (Darwin arm64) with OrbStack 2.2.3, whose Docker engine is 29.4.0 (linux/arm64) with buildx 0.33.0, BuildKit 0.29.0 and the containerd image store, pixi 0.81.0, and the repository at `579555e`. The release is dry-run against a throwaway `registry:2` on loopback; ghcr.io is read anonymously and never written. Nothing here logs in to a registry, pushes to ghcr.io, creates a git tag, or changes a repository setting.

Each script exits non-zero on an unexpected result, and each `.txt` file is the transcript of the script with the same name. Every script writes only to the work directory it is given, apart from the Docker objects it creates and removes, which are named after this worktree.

## Network the maintainer authorized for this spike

Read-only, on 2026-10-08: Docker builds and pulls (conda packages, hex packages, rebar3, `ubuntu:24.04`, `registry:2`, the arm64 variants of the base images), `gh` read-only API calls, and web fetches of vendor documentation. No push, no `docker login`, no `gh` write.

## Rerun everything

```sh
sh .scratch/bootstrap/evidence/28/run-all.sh "$(mktemp -d)"
```

This needs network, docker (buildx with the docker driver), curl, perl, an authenticated `gh`, the pixi default and cluster environments (`just initialize`, `just cluster-install`) and kubeconform from `.tools/bin`. It took 44 s here with the Docker layer cache warm, rewrites every transcript here, and stops at the first script that fails. At the end it checks that the run left no registry container or probe image behind; another worktree's objects do not count. The transcripts' `revision` label and `sha-<7>` tag are the commit checked out at the time.

## Scripts

| Script | Transcript | What it shows |
| --- | --- | --- |
| [lib.sh](lib.sh) | (sourced by every script) | The guards and verdicts: `version_of_tag`, `tags_for`, `toml_version`, `tag_matches_version`, `changelog_has_version`, the three digest readers, `tag_exists_verdict` (only 404 is absent; 200 is present; everything else is unknown and stops), `probe_tag`, `tag_moved_verdict`, `ancestor_verdict`, and the timing arithmetic |
| [lib_test.sh](lib_test.sh) | [lib_test.txt](lib_test.txt) | Ninety-one tests of those helpers on inputs copied from real output, built first and watched failing (the first seventy-seven against an empty `lib.sh`, the twelve rejections the review added against the earlier grammar and heading match); ancestry through a stub `git` and on a throwaway repository |
| [ghcr-probe.sh](ghcr-probe.sh) | [ghcr-probe.txt](ghcr-probe.txt) | Anonymous ghcr.io reads of the knarr package that does not exist yet (401, then 403 `denied`, the same as for a private package); the guard's three verdicts against the real ghcr.io with a public package as the control; the repository's visibility, environments, rulesets, branch protection, tags and releases through `gh` |
| [ci-durations.sh](ci-durations.sh) `<dir>` | [ci-durations.txt](ci-durations.txt) | The last twelve `ci.yml` runs: the kind-smoke job and its `just image-build` step on `ubuntu-24.04`, with the median over the steps that succeeded; an unfinished run shows `-`, never a number. The only native amd64 build numbers there are |
| [sources.sh](sources.sh) `<dir>` | [sources.txt](sources.txt) | Fourteen vendor pages fetched with their sha256, and each phrase 0012 cites looked for in the page's text; a missing phrase is a dated finding, not a failure. `immutable` is expected not to be on the GHCR page |
| [registry.sh](registry.sh) `<dir>` | [registry.txt](registry.txt) | The dry run: the release guards on this checkout, `buildx build --push` of a stand-in image with knarr's labels and the three tags, the digest read three ways, every tag resolving to it, the guard against this registry, a second push moving the tag while the first digest still pulls, and a real pull by tag. Also what `--provenance=mode=min` pushes on the containerd image store |
| [overlay/](overlay/kustomization.yaml) | | The designed release overlay: `deploy/base` plus an image pinned by digest and `imagePullPolicy: IfNotPresent`. Ticket 36 moves it to `deploy/release/` |
| [overlay-render.sh](overlay-render.sh) `<dir> <digest>` | [overlay-render.txt](overlay-render.txt) | The overlay rendered as committed and with the dry run's digest, validated against the vendored schemas (3 of 3 each time), the Role's rules still `[]`, no token mounted, and the two-line diff against the base render |
| [amd64-probe.sh](amd64-probe.sh) `<dir>` | [amd64-probe.txt](amd64-probe.txt) | The real Dockerfile under amd64 emulation on this host: it fails at the first step that starts the BEAM (`prim_tty`), so the image is built natively in CI only |
| [arm64-probe.sh](arm64-probe.sh) `<dir>` | [arm64-probe.txt](arm64-probe.txt) | `pixi.lock` has no `linux-aarch64` entry, so the arm64 build stage fails at `pixi install --locked` at once, with pixi's message; both base images have arm64 variants |
| [release.yml](release.yml) | | The drafted release workflow, kept out of `.github/workflows/` so it cannot run. Ticket 36 moves it there |
| [actionlint.sh](actionlint.sh) | [actionlint.txt](actionlint.txt) | `release.yml` under actionlint with shellcheck, by explicit path |
| [run-all.sh](run-all.sh) `<root>` | | All of the above, in order, then the leftover check |

## Notes

- **The dry run's image is a stand-in.** The real image cannot be built on this host (`amd64-probe.txt`), and ticket 13 had already found the amd64 runtime failing under emulation. `registry.sh` builds `FROM scratch` with one file and knarr's OCI labels, with the same buildx command, platform and tags the workflow uses. None of what the transcript shows (tags, digests, the guard, a moved tag, a pull by digest) depends on what is in the image.
- **Anonymous ghcr.io reads cannot tell absent from private.** The token endpoint answers 403 `denied` for both, so the existence guard runs after `docker login` in the workflow, and anonymously says `unknown`. The guard's three outcomes are shown against a public package instead, and against `registry:2`.
- **Timings are labelled.** Emulated amd64 on an arm64 host is not a CI number; `ci-durations.txt` has the native ones. Arm64 is native here and emulated nowhere in CI yet.
- **Point-in-time reads.** The `gh` answers (environments, rulesets, protection, tags) and the vendor pages are as of the run's date. Ticket 37 changes the first three on purpose.
- **A failed request is never evidence.** The existence verdict fails closed; `run-all.sh` fails if it cannot list Docker's objects rather than reporting none left; `sources.sh` stops on a fetch failure rather than reporting a phrase missing.
- **Build logs stay in the work directory.** The transcripts keep one line per build and the path of the full log; evidence holds text only.
