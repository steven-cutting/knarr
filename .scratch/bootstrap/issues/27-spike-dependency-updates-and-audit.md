# 27: Spike: dependency updates and security audit

**Context:** This takes the shape of libpawdoku's S01. knarr pins versions in several places:

- hex packages in `manifest.toml`
- the pixi lock
- GitHub Action SHAs
- prek hook SHAs
- the base-image digest
- the kind node image

Nothing updates these yet, and nothing audits them.

**What to build:** A decision and a working setup that propose updates for every pin and flag known vulnerabilities, without ever pushing to `main` unreviewed.

**Non-goals:** Release signing, SBOM and build provenance: [Decision 0012](../../../docs/decisions/0012-release-and-packaging.md) defers them, and 38 builds them. The arm64 re-lock 38 may need goes through the update process this ticket sets up.

**Blocked by:** 05, 13

**MVP critical path:** no. It is maintenance hygiene, and the MVP does not need it.

**Status:** in review. See [Decision 0013](../../../docs/decisions/0013-dependency-updates-and-audit.md) and its [evidence](../evidence/27/README.md). The two audit-workflow boxes are ticked once the branch's `audit.yml` run is recorded.

- [x] Renovate (or a stated alternative) covers hex `manifest.toml`, the pixi lock, action SHAs, prek hook SHAs, the base-image digest and the kind node image. Each one is shown proposing an update, or its gap is recorded.
- [ ] A source of hex advisories is chosen and runs in the audit workflow.
- [ ] An image scan runs on the built image in the audit workflow. It is not required.
- [x] **Authorization required:** installing any GitHub App or changing any repository setting. Nothing was installed and no setting changed; ticket 41 asks for both.
- [x] A decision record is written, and follow-ups are drafted.

## Hand-back notes

Settled on 2026-10-09 (UTC). The maintainer chose the held landing, proved by a local lookup-only Renovate run with the app left to a follow-up, in the planning session the same day. The evidence tests the route, not that choice.

### What changed

- **[Decision 0013](../../../docs/decisions/0013-dependency-updates-and-audit.md).** Renovate through the Mend-hosted app, not Dependabot, with every pin's coverage or gap. It records the held landing and the holds that outlive it, the manual routines for the gaps, and OSV.dev for hex and OTP. It records grype for the image and why not Trivy, and the re-lock route 38's arm64 lane takes. 0003 carries "Amended by ticket 27" notes: the audit environment on PATH, the pixi version in five places, and the base-image digests.
- **[`.github/renovate.json`](../../../.github/renovate.json),** held by `:dependencyDashboardApproval`, with no automerge. It has two regex managers: one for the six images in `scripts/checks/cluster.py`, and one for the four pixi versions outside the Dockerfile. The four groups are hex packages, GitHub Actions, pixi and local cluster. Conda pins, the pixi group and the local-cluster group keep their own hold. The Kubernetes images are capped at 1.35. setup-pixi's native `pixi-version` reading is switched off, because it proposed nothing.
- **Shape changes so the managers read every pin.** `gleam.toml`'s dev table is `[dev-dependencies]`, the only spelling the gleam manager reads; with the other spelling it saw 6 of 11 packages. Both base images are pinned by OCI index digest. [`test_dependency_pins.py`](../../../scripts/checks/tests/test_dependency_pins.py) holds every shape in the gate.
- **The audit.** [`hex_audit.py`](../../../scripts/checks/hex_audit.py) (`just hex-audit`) asks OSV.dev about every locked hex package and the OTP pin, and fails closed. grype 0.120.1 is in a pixi `audit` environment (`just audit-install`, `just image-scan`), and the relock added only its records. The setup action gained an `audit` input. `audit.yml` gained the `hex-advisories` and `image-scan` jobs, neither of them required.
- **Removed pins (13's hand-back).** `env-check` reports a tool whose `tools.txt` lines are gone, and `install-tools.sh` removes it with its record, leaving a binary it never installed alone.
- **The surrounding docs.** `AGENTS.md` and `CONTRIBUTING.md` list the new network recipes. The README describes the audit and Renovate's role in moving pins, and `CHANGELOG.md` has the entries.
- **Tickets.** [41](41-renovate-activation.md) is drafted, the [bootstrap README](../README.md) graph and waves include it, and [38](38-attestations-sbom-arm64.md) points at 0013's re-lock route.

### What was verified, and what was not

- **Verified here:**
  - the configuration validates with `--strict`;
  - HEAD extracts 57 dependencies across five managers;
  - a stale copy, with real older pins rolled back, shows every covered kind of pin proposing in its group's branch ([renovate.txt](../evidence/27/renovate.txt));
  - `hex_audit.py` passes the committed tree and fails both controls ([osv-probe.txt](../evidence/27/osv-probe.txt));
  - grype runs from the audit environment ([grype-probe.txt](../evidence/27/grype-probe.txt));
  - the gate tests came first, and `just check` passes.
- **Not verified, by design.** These are 41's:
  - installing the app, a real pull request and the Dependency Dashboard;
  - the holds as Renovate applies them, since lookup mode stops before branches and the gate test models them instead;
  - the hosted relock of `pixi.lock` and rewrite of `manifest.toml`;
  - Renovate's OSV and Dependabot alerts.
- **Three corrections to the plan's premises:**
  - Renovate's gleam manager skips `[dev_dependencies]`.
  - Its native reading of setup-pixi's `pixi-version` proposes nothing (renovate.txt, part 4).
  - Dependabot does list a Conda ecosystem, but without lock-file updates, so the choice of Renovate stands for that reason.
- **The image scan's first finding.** The pinned ubuntu:24.04 base already carries CVE-2026-84782 (High) in Ubuntu's `libssl3t64`, fixed in 3.0.13-0ubuntu3.16. The BEAM links conda-forge's openssl, not this one. The `image-scan` job is expected to stay red until the base image's digest moves.

### What each later ticket needs

- **41:** install the app on knarr only (**authorization required**). Expect the dashboard and, if the app insists, an onboarding pull request. Approve one proposal per manager. The ubuntu digest update clears the image scan. Record whether the app rewrites `manifest.toml` and relocks `pixi.lock`; relocking by hand on the bot's branch is the passing path. Then remove `:dependencyDashboardApproval` (**authorization required**). A vulnerability-fix pull request may open without approval, by Renovate's default, and still never merges itself.
- **38:** the arm64 re-lock is an ordinary pull request: add `linux-aarch64` to `platforms`, run `pixi lock`, read the diff, then run `just lock-check`, `just env-check` and the gate (0013, "Re-locks"). Both base-image digests are indexes with an arm64 manifest already ([digests.txt](../evidence/27/digests.txt)).
- **Any ticket that adds a pin:** keep it in a shape `test_dependency_pins.py` accepts, or extend a manager and that test together. A remote prek hook reopens 0013.
