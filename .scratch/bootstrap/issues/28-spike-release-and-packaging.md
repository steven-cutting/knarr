# 28: Spike: release and packaging

**Context:** This takes the shape of libpawdoku's S02. The MVP bar is running a real production workload on GKE Standard (OVERVIEW §1), so the image must be published somewhere GKE can pull from. §9.15 leaves deployment packaging open: kustomize, Helm, or both, plus a namespaced Role. The walking skeleton (13) has a kustomize base.

**What to build:** A decision on how knarr is versioned, built, published and installed, and a dry run of the first release.

**Non-goals:** Publishing a real release. Running it is round 2, after the MVP clauses are built.

**Blocked by:** 13

**MVP critical path:** yes for image publishing and the §9.15 packaging decision. Multi-arch, cosign, SBOM and provenance are not on it.

**Status:** done. See [Decision 0011](../../../docs/decisions/0011-release-and-packaging.md) and its [evidence](../evidence/28/README.md).

- [x] The ticket decides a versioning scheme and a changelog workflow.
- [x] An image publishing route to GHCR is designed and dry-run, with tags, digest pinning and immutability. Every push is marked **authorization required**.
- [x] Multi-arch builds (amd64 and arm64) are evaluated against build time.
- [x] §9.15 is decided: kustomize, Helm, or both, with the namespaced Role.
- [x] cosign signing, SBOM and build provenance are evaluated, and each is adopted or deferred with a reason.
- [x] A decision record is written, and follow-ups are drafted for the release workflow.
- [x] A round-2 follow-up is drafted for the production rollout and acceptance on GKE Standard (OVERVIEW §1). It is marked needs-human and MVP critical path: yes. It is blocked by the spec-then-build follow-ups and the release run, plus GKE Standard access (external). It marks every cloud action **authorization required**. Its acceptance needs evidence that a real production workload ran on a published knarr release, with the GKE version, the release digest and the teardown or handover recorded.

## Hand-back notes

Settled on 2026-10-09 (UTC). The maintainer chose kustomize only, "the maintainer tags and CI publishes", and amd64 only in the planning session on 2026-10-08; the evidence tests the route, not the choices.

### What changed

- [Decision 0011](../../../docs/decisions/0011-release-and-packaging.md): SemVer with `gleam.toml` as the source of truth, a hand-written Keep a Changelog, `ghcr.io/steven-cutting/knarr` pushed by `release.yml` on a `v*` tag behind a `release` environment, tags `X.Y.Z`, `X.Y`, `X` (major above 0) and `sha-<7>` and never `latest`, immutability from digest pins plus a fail-closed pre-push guard plus a `v*` tag ruleset, kustomize only with a release overlay pinned by digest and the Role in the base, amd64 only, attestations later, cosign deferred. OVERVIEW §9.15 and its summary table say Decided; DEFERRED §8 carries Helm, arm64, and cosign, SBOM and provenance with the reasons. The decisions index also gained the missing line for 0010.
- [Evidence](../evidence/28/README.md): a tested helper library, read-only probes of ghcr.io and the repository, the CI build durations, the dry run against a throwaway `registry:2`, the designed overlay rendered and validated, the emulated amd64 and arm64 probes, the vendor sources with their phrases, and the drafted `release.yml` under actionlint. `run-all.sh` reran all of it in 44 s and left nothing behind.
- Tickets [36](36-release-workflow-and-overlay.md), [37](37-first-release-v0-1-0.md), [38](38-attestations-sbom-arm64.md) and [39](39-gke-production-rollout.md) are drafted; 27, 33 and 34 point at them; the [bootstrap README](../README.md) graph and waves include them.

### What was verified, and what was not

- Verified here: every guard and verdict on canned real output (77 tests); the guard's `present`, `absent` and `unknown` against the real ghcr.io with a public package; three digest readings agreeing on a pushed image; a tag moving while its first digest still pulls; the overlay rendering to a two-line difference from the base with all three resources valid; `release.yml` clean under actionlint with shellcheck.
- Not verified, by design: no push to ghcr.io, no `docker login`, no tag, no environment, ruleset or visibility change. The authenticated existence guard against ghcr.io for a package that does not exist yet is 0011's one open behaviour; 37 records what it answers.
- Two corrections to the plan's premise. The real image cannot be built on this host: under amd64 emulation the BEAM fails to start in `prim_tty` at the first rebar3 dependency compile, as 13 saw at runtime, so the dry run pushes a labelled stand-in image (`FROM scratch`) with the same buildx command, and the only native build numbers are CI's (19 to 24 s, median 20 s). With the containerd image store, `--provenance=mode=min` on the docker driver pushes an OCI index rather than being refused, which is why the workflow sets `--provenance=false --sbom=false` explicitly and 38 pins the index digest when it turns them on.
- Anonymous ghcr.io reads cannot tell an absent package from a private one (403 `denied` for both), so the guard runs after login and the anonymous answer is `unknown`.

### What each later ticket needs

- **36:** the draft [release.yml](../evidence/28/release.yml) moves under `.github/workflows/` as is, apart from sourcing `scripts/release/lib.sh`, which is [lib.sh](../evidence/28/lib.sh) moved with [lib_test.sh](../evidence/28/lib_test.sh). The overlay is [overlay/](../evidence/28/overlay/kustomization.yaml) with `resources: [../base]`. [overlay-render.sh](../evidence/28/overlay-render.sh) is the shape of the checker test. The `release` environment, with the maintainer as required reviewer and "Prevent self-review" off, must exist before 36 merges: GitHub creates a referenced environment with no protection rules otherwise. Merging 36 then makes the workflow live on the next `v*` tag: **authorization required**, and the pull request must say so.
- **37:** the settings as of 2026-10-09 are in [ghcr-probe.txt](../evidence/28/ghcr-probe.txt): one environment (`copilot`), no ruleset, no tag. Confirm the `release` environment 36 created, then create the ruleset. Record the existence guard's answer for the package that does not exist yet, the digest, and an anonymous pull after the package is public.
- **38:** [registry.txt](../evidence/28/registry.txt) part 2 shows the index an attested push produces and its `unknown/unknown` attestation manifest; the overlay then pins the index digest. [arm64-probe.txt](../evidence/28/arm64-probe.txt) has the arm64 cost; the re-lock is 27's process.
- **39:** install from the overlay with 37's digest; every cloud action **authorization required**; the acceptance evidence is listed in the ticket.
- **34:** the install guide follows the overlay (now in 34's boxes, blocked by 28): `kubectl apply -k` at the release tag with the digest from the run's summary.
- **27:** the base-image digest pins and any re-lock, including `linux-aarch64`, are 27's; 28 did not touch the Dockerfile or the lock.
- **14:** the Role's verbs and the RoleBinding go in `deploy/base`, where the overlay inherits them.
- **12:** `CHANGELOG.md` with `## [Unreleased]` at the top is a release input: the workflow refuses a tag whose version has no `## [X.Y.Z]` heading.
