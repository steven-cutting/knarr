# 28: Spike: release and packaging

**Context:** This takes the shape of libpawdoku's S02. The MVP bar is running a real production workload on GKE Standard (OVERVIEW §1), so the image must be published somewhere GKE can pull from. §9.15 leaves deployment packaging open: kustomize, Helm, or both, plus a namespaced Role. The walking skeleton (13) has a kustomize base.

**What to build:** A decision on how knarr is versioned, built, published and installed, and a dry run of the first release.

**Non-goals:** Publishing a real release. Running it is round 2, after the MVP clauses are built.

**Blocked by:** 13

**MVP critical path:** yes for image publishing and the §9.15 packaging decision. Multi-arch, cosign, SBOM and provenance are not on it.

**Status:** ready-for-agent

- [ ] The ticket decides a versioning scheme and a changelog workflow.
- [ ] An image publishing route to GHCR is designed and dry-run, with tags, digest pinning and immutability. Every push is marked **authorization required**.
- [ ] Multi-arch builds (amd64 and arm64) are evaluated against build time.
- [ ] §9.15 is decided: kustomize, Helm, or both, with the namespaced Role.
- [ ] cosign signing, SBOM and build provenance are evaluated, and each is adopted or deferred with a reason.
- [ ] A decision record is written, and follow-ups are drafted for the release workflow.
