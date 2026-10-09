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

**Status:** ready-for-agent

- [ ] Renovate (or a stated alternative) covers hex `manifest.toml`, the pixi lock, action SHAs, prek hook SHAs, the base-image digest and the kind node image. Each one is shown proposing an update, or its gap is recorded.
- [ ] A source of hex advisories is chosen and runs in the audit workflow.
- [ ] An image scan runs on the built image in the audit workflow. It is not required.
- [ ] **Authorization required:** installing any GitHub App or changing any repository setting.
- [ ] A decision record is written, and follow-ups are drafted.
