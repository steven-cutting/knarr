# 37: First release run: `v0.1.0`

**Context:** Ticket 36 makes the release route live. Nothing has run it. [Decision 0012](../../../docs/decisions/0012-release-and-packaging.md) leaves three things unverified that only a real run can settle: the authenticated existence guard's answer for a package that does not exist yet, the `release` environment's approval flow with one maintainer, and a pull of the published digest from a machine that never built the image. This run publishes `v0.1.0` of the walking skeleton as the first release: a rehearsal of the route on a pre-MVP image, so that [40](40-mvp-release.md) publishes the MVP through a route that has run once.

**What to build:** The repository settings the route needs, the release pull request, the tag, the approved run, the package made public, and a pull by digest, each recorded.

**Non-goals:** Changing the workflow beyond what the run shows is wrong (a fix goes through 36's shape and this ticket records it). Attestations (38). The GKE install (39).

**Blocked by:** 36

**From 28:** [Decision 0012](../../../docs/decisions/0012-release-and-packaging.md), "Not run here"; [ghcr-probe.txt](../evidence/28/ghcr-probe.txt) for the settings as they were on 2026-10-09.

**MVP critical path:** yes. The MVP installs a published release.

**Status:** needs-human, round 2. Every step below changes something outside the worktree and needs the maintainer's explicit approval, one action at a time.

- [ ] The `release` environment 36 created still has the maintainer as its required reviewer and "Prevent self-review" **off**; the hand-back records the settings as `gh api repos/steven-cutting/knarr/environments/release` shows them before the tag is pushed.
- [ ] **Authorization required:** a tag ruleset on `v*` restricts updates and deletions. The hand-back records it as `gh api repos/steven-cutting/knarr/rulesets` shows it.
- [ ] A release pull request moves `## [Unreleased]` into `## [0.1.0] - <date>` in `CHANGELOG.md`, leaves `gleam.toml` at `0.1.0`, and merges like any other.
- [ ] **Authorization required:** the maintainer tags the merge commit with an annotated `v0.1.0` and pushes the tag. The `verify` job passes its three guards.
- [ ] **Authorization required:** the maintainer approves the `release` deployment. The `publish` job logs in, finds `0.1.0` absent, pushes `0.1.0`, `0.1` and `sha-<7>` (no `latest`), and prints the digest in its summary. The hand-back records what the existence guard answered for the package that did not exist yet (0012 expects `absent`, HTTP 404) and the run's URL.
- [ ] **Authorization required:** the package is made public once, by hand. The hand-back records that an anonymous `curl -sI` of the manifest answers 200 with the same `Docker-Content-Digest`.
- [ ] From a machine that never built the image (a fresh kind node or a clean container), `docker pull ghcr.io/steven-cutting/knarr@sha256:<digest>` succeeds, and the labels show `org.opencontainers.image.version=0.1.0` and the tagged commit. The hand-back records the digest as the rehearsal's evidence; 39 installs 40's, not this one.
- [ ] A second push of the same tag is not attempted; instead the hand-back quotes the workflow's existence guard refusing in a dry reasoning line, or, if the maintainer wants it proven, a `workflow_dispatch` rerun that fails on `present` is recorded and the trigger removed again.
