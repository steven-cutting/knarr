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

**Status:** done. See [Decision 0014](../../../docs/decisions/0014-dependency-updates-and-audit.md) and its [evidence](../evidence/27/README.md).

- [x] Renovate (or a stated alternative) covers hex `manifest.toml`, the pixi lock, action SHAs, prek hook SHAs, the base-image digest and the kind node image. Each one is shown proposing an update, or its gap is recorded.
- [x] A source of hex advisories is chosen and runs in the audit workflow. OSV.dev, through `just hex-audit`; the branch's run passed ([ci-audit.txt](../evidence/27/ci-audit.txt)).
- [x] An image scan runs on the built image in the audit workflow. It is not required. grype, through `just image-scan`; the branch's run scanned the real linux/amd64 image and failed on the base image's `libssl3t64` finding ([ci-audit.txt](../evidence/27/ci-audit.txt)). It reads the image's OS packages only, and ticket 45 scans the runtime environment.
- [x] **Authorization required:** installing any GitHub App or changing any repository setting. Nothing was installed and no setting changed; ticket 44 asks for both.
- [x] A decision record is written, and follow-ups are drafted.

## Hand-back notes

Settled on 2026-10-09 (UTC), with the branch's `audit.yml` run on 2026-10-10. The maintainer chose the held landing, proved by a local lookup-only Renovate run with the app left to a follow-up, in the planning session the same day. The evidence tests the route, not that choice.

### What changed

- **[Decision 0014](../../../docs/decisions/0014-dependency-updates-and-audit.md).** Renovate through the Mend-hosted app, not Dependabot, with every pin's coverage or gap. It records the held landing and the holds that outlive it, the manual routines for the gaps, and OSV.dev for hex and OTP. It records grype for the image, the conda records it does not read, and why not Trivy, and the re-lock route 38's arm64 lane takes. 0003 carries "Amended by ticket 27" notes: the audit environment on PATH, the pixi version in five places, and the base-image digests.
- **[`.github/renovate.json`](../../../.github/renovate.json),** held by `:dependencyDashboardApproval`, with no automerge. It has two regex managers: one for the six images in `scripts/checks/cluster.py`, and one for the four pixi versions outside the Dockerfile. The four groups are hex packages, GitHub Actions, pixi and local cluster. Conda pins, the pixi group and the local-cluster group keep their own hold. The Kubernetes images are capped at 1.35 and etcd at 3.6, and the kwok controller image is switched off, to move by hand with kwokctl. setup-pixi's native `pixi-version` reading is switched off, because it proposed nothing.
- **Shape changes so the managers read every pin.** `gleam.toml`'s dev table is `[dev-dependencies]`, the only spelling the gleam manager reads; with the other spelling it saw 6 of 11 packages. Both base images are pinned by OCI index digest. [`test_dependency_pins.py`](../../../scripts/checks/tests/test_dependency_pins.py) holds every shape in the gate.
- **The audit.** [`hex_audit.py`](../../../scripts/checks/hex_audit.py) (`just hex-audit`) asks OSV.dev about every locked hex package and the OTP pin, and fails closed. grype 0.120.1 is in a pixi `audit` environment (`just audit-install`, `just image-scan`), and the relock added only its records. The setup action gained an `audit` input. `audit.yml` gained the `hex-advisories` and `image-scan` jobs, neither of them required.
- **Removed pins (13's hand-back).** `env-check` reports a tool whose `tools.txt` lines are gone, and `install-tools.sh` removes it with its record, leaving a binary it never installed alone.
- **The surrounding docs.** `AGENTS.md` and `CONTRIBUTING.md` list the new network recipes. The README describes the audit and Renovate's role in moving pins, and `CHANGELOG.md` has the entries.
- **Tickets.** Tickets [44](44-renovate-activation.md) and [45](45-scan-image-runtime-environment.md) are drafted, the [bootstrap README](../README.md) graph and waves include them, and [38](38-attestations-sbom-arm64.md) points at 0014's re-lock route.

### What was verified, and what was not

- **Verified here:**
  - the configuration validates with `--strict`;
  - HEAD extracts 57 dependencies across five managers, and skips only the two switched off, setup-pixi's input and the kwok image;
  - a stale copy, with real older pins rolled back, shows every covered kind of pin proposing in its group's branch ([renovate.txt](../evidence/27/renovate.txt));
  - `hex_audit.py` passes the committed tree and fails both controls ([osv-probe.txt](../evidence/27/osv-probe.txt));
  - grype runs from the audit environment, and reads conda records from a directory but not from an image ([grype-probe.txt](../evidence/27/grype-probe.txt));
  - the branch's `audit.yml` run, 38015514089, dispatched at `d5c7178` on 2026-10-10: the hex advisories job passed, and the image scan failed with exit 2 on the real linux/amd64 knarr image, on the base image's six `libssl3t64` rows ([ci-audit.txt](../evidence/27/ci-audit.txt));
  - the gate tests came first, and `just check` passes.
- **Not verified, by design.** These are 44's:
  - installing the app, a real pull request and the Dependency Dashboard;
  - the holds as Renovate applies them, since lookup mode stops before branches and the gate test models them instead;
  - the hosted relock of `pixi.lock` and rewrite of `manifest.toml`;
  - Renovate's OSV and Dependabot alerts.
- **Three corrections to the plan's premises:**
  - Renovate's gleam manager skips `[dev_dependencies]`.
  - Its native reading of setup-pixi's `pixi-version` proposes nothing (renovate.txt, part 4).
  - Dependabot does list a Conda ecosystem, but without lock-file updates, so the choice of Renovate stands for that reason.
- **The image scan's first finding.** The pinned ubuntu:24.04 base already carries CVE-2026-84782 (High) in Ubuntu's `libssl3t64`, fixed in 3.0.13-0ubuntu3.16, and the CI scan of the real image shows exactly that finding. The BEAM links conda-forge's openssl, not this one. No digest update exists yet: the `ubuntu:24.04` tag still names the pinned index ([digests.txt](../evidence/27/digests.txt)), and Renovate proposes only the 24.04 → 26.04 major ([renovate.txt](../evidence/27/renovate.txt)). The `image-scan` job stays red until Ubuntu republishes noble with `libssl3t64` 3.0.13-0ubuntu3.16 or later. Then Renovate proposes the digest once 43 activates it, or the maintainer moves the `FROM` line by hand (0014's manual routine). While it is red, the job's table still lists every finding.
- **The conda gap.** grype does not read conda records in an image. syft, which grype runs to catalogue packages, selects 34 package catalogers for an image and 57 for a directory, and `conda-meta-cataloger` runs only on a directory. The runtime environment's records give 0 conda matches as an image, and 7 conda matches, 4 with a fix, as a directory ([grype-probe.txt](../evidence/27/grype-probe.txt), part 3). grype 0.120.1 has no flag or configuration setting that selects catalogers. So `just image-scan` covers the image's OS packages only, and no job yet scans the runtime environment the image ships: erlang, the conda-forge openssl the BEAM links, perl 5.32.1 and zlib. All four matches with a fix are in conda-forge's perl 5.32.1, through NVD CPEs, CVE-2022-48522 (Critical) among them, and erlang's build pins that perl. The probe scanned the 8 of the 13 linux-64 packages that have a record on this host; 44 scans the whole linux-64 environment. The maintainer chose to record the gap and draft [45](45-scan-image-runtime-environment.md).

### What each later ticket needs

- **44:** install the app on knarr only (**authorization required**). Expect the dashboard and, if the app insists, an onboarding pull request. Approve one proposal per manager. No ubuntu digest update exists yet; one appears once Ubuntu republishes noble with the fixed `libssl3t64`, and it clears the image scan. Record whether the app rewrites `manifest.toml` and relocks `pixi.lock`; relocking by hand on the bot's branch is the passing path. Then remove `:dependencyDashboardApproval` (**authorization required**). A vulnerability-fix pull request may open without approval, by Renovate's default, and still never merges itself.
- **45:** scan the linux-64 runtime environment as a directory with `--only-fixed --fail-on high`, copied out of the built image in CI or installed from the lock, and run it in `audit.yml` even when the OS-package scan fails. Fail the scan when it catalogues no conda package, so a wrong path cannot pass. Decide perl: prune it from the runtime image and rerun 0003's TLS check, or accept it with a dated, documented grype ignore. erlang's conda-forge build pins perl 5.32.1 (build string `pl5321`), so perl cannot move on its own. The evidence is [grype-probe.txt](../evidence/27/grype-probe.txt), part 3, and [ci-audit.txt](../evidence/27/ci-audit.txt).
- **38:** the arm64 re-lock is an ordinary pull request: add `linux-aarch64` to `platforms`, run `pixi lock`, read the diff, then run `just lock-check`, `just env-check` and the gate (0014, "Re-locks"). Both base-image digests are indexes with an arm64 manifest already ([digests.txt](../evidence/27/digests.txt)).
- **Any ticket that adds a pin:** keep it in a shape `test_dependency_pins.py` accepts, or extend a manager and that test together. A remote prek hook reopens 0014.
