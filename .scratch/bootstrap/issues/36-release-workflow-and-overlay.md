# 36: Release workflow and the digest-pinned release overlay

**Context:** [Decision 0011](../../../docs/decisions/0011-release-and-packaging.md) settles the route: SemVer with `gleam.toml` as the source of truth, a hand-written Keep a Changelog, the maintainer tags and CI publishes to `ghcr.io/steven-cutting/knarr` behind a `release` environment, consumers pin by digest, and §9.15 is kustomize only with a release overlay over `deploy/base`. Ticket 28 drafted the workflow, the guards and the overlay under [evidence/28](../evidence/28/README.md) and dry-ran them against a throwaway registry; none of it is live. This ticket makes it live, without running it.

**What to build:** `release.yml` under `.github/workflows/` from [the draft](../evidence/28/release.yml); the guards it sources in `scripts/release/lib.sh` from [28's lib.sh](../evidence/28/lib.sh), with their tests moved beside them in the shape the checker tests use; `deploy/release/` from [the overlay design](../evidence/28/overlay/kustomization.yaml); and the recipes and checker tests that keep base and overlay in step.

**Non-goals:** Running the workflow (37). Attestations, SBOM, provenance and arm64 (38). The install guide (34). `CHANGELOG.md` itself (12). The Role's verbs and the RoleBinding (14).

**Blocked by:** 12, 28

**From 28:** [Decision 0011](../../../docs/decisions/0011-release-and-packaging.md); the hand-back notes in [ticket 28](28-spike-release-and-packaging.md#hand-back-notes).

**MVP critical path:** yes. Nothing reaches GKE without a published image.

**Status:** ready-for-agent, round 2

- [ ] **Authorization required:** before the pull request merges, the `release` environment exists with the maintainer as its required reviewer and "Prevent self-review" off, and the hand-back records it as `gh api repos/steven-cutting/knarr/environments/release` shows it. GitHub creates a referenced environment with no protection rules otherwise, so a `v*` tag pushed before 37 would publish with no approval.
- [ ] **Authorization required:** `release.yml` is live once merged. The pull request says so, and the maintainer merges it knowingly. It runs on `v*` tag pushes only, keeps `permissions: {}` at the top, `contents: read` on `verify`, and `contents: read` plus `packages: write` on `publish` behind `environment: release`. Every action is pinned to a full commit SHA. `just lint` runs actionlint on it.
- [ ] `scripts/release/lib.sh` carries `version_of_tag`, `tags_for`, `toml_version`, `tag_matches_version`, `changelog_has_version`, the digest readers, `tag_exists_verdict`, `probe_tag` and `ancestor_verdict` from 28's `lib.sh`, and 28's `lib_test.sh` runs against it from `just test-checkers` or a recipe in the `check` group. The existence guard still proceeds only on `absent`; `unknown` stops the run.
- [ ] `deploy/release/kustomization.yaml` renders `deploy/base` with the image renamed to `ghcr.io/steven-cutting/knarr`, pinned by digest, and `imagePullPolicy: IfNotPresent`, and changes nothing else; a checker test renders both and asserts the two-line difference, as [overlay-render.sh](../evidence/28/overlay-render.sh) does. `just deployment-check` validates the overlay's render as well as the base's.
- [ ] A recipe, outside `check`, replaces the overlay's digest with a given `sha256:…` and prints the rendered image reference, for 37 to use after the first push.
- [ ] `just check` ends with "All checks passed and the worktree is unchanged." The hand-back names the workflow's first live trigger (37's tag) and what 37 must still set up before pushing it: the `v*` tag ruleset.
