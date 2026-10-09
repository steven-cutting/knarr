# 41: Renovate activation

**Context:** [Decision 0013](../../../docs/decisions/0013-dependency-updates-and-audit.md) chose Renovate, through the Mend-hosted app, to propose an update for every pin it can read. Ticket 27 landed [`.github/renovate.json`](../../../.github/renovate.json) held: every update waits for approval on the Dependency Dashboard, and nothing automerges. It proved each manager only with a local, lookup-only run ([renovate.txt](../evidence/27/renovate.txt)). That run creates no branch, no issue and no pull request. No app is installed yet.

**What to build:**

- the app installed on knarr;
- one approved pull request per manager, each merged through the normal review and recorded;
- the landing hold removed;
- the maintainer's how-to for reviewing a Renovate pull request.

**Non-goals:**

- Automerge of any kind.
- The manual routines 0013 records for `tools.txt`, the Kubernetes schemas and `skills-lock.json`.
- Self-hosting Renovate, which would need a token stored as a repository secret.

**Blocked by:** 27

**From 27:** [Decision 0013](../../../docs/decisions/0013-dependency-updates-and-audit.md); the hand-back notes in [ticket 27](27-spike-dependency-updates-and-audit.md#hand-back-notes).

**MVP critical path:** no. It is maintenance hygiene, and the MVP does not need it.

**Status:** needs-human, ready once 27 merges

- [ ] **Authorization required:** the maintainer installs the Mend Renovate app on `steven-cutting/knarr` only ("Only select repositories"). The hand-back records the permissions the installation screen asked for, compared with the app's [permissions page](https://docs.renovatebot.com/security-and-permissions/): read on Dependabot alerts, administration and metadata; read and write on checks, code, commit statuses, issues, pull requests and workflows.
- [ ] The first run opens the Dependency Dashboard issue with every update pending approval and no pull request. The ubuntu digest update should be among them; it clears the image scan's first finding (Decision 0013). If the app opens an onboarding pull request instead, as its docs say a selected-repositories install does, the hand-back records why, and nothing is merged from it.
- [ ] One approved pull request per manager, each through `check` and the maintainer's review, with its CI run recorded:
  - **gleam:** whether the app rewrites `manifest.toml` itself;
  - **pixi:** whether it relocks `pixi.lock`. That needs `pixi` in the hosted app's `allowedUnsafeExecutions`, which its docs do not mention. If it does not, relocking by hand on the bot's branch, with the lock diff read, is the passing path, and 0013's hold on conda pins stays;
  - **github-actions:** a SHA moved with its version comment;
  - **dockerfile:** a base-image digest update;
  - **the regex manager:** the local-cluster group (kind node and kwok images, kind, kubectl, kustomize) and the pixi group, all five places in one pull request.
- [ ] **Authorization required:** a pull request removes `:dependencyDashboardApproval` from `extends`. `scripts/checks/tests/test_dependency_pins.py` still proves that the conda pins, the pixi group and the local-cluster group keep their own hold.
- [ ] A how-to page, `docs/how-to/review-renovate-updates.md`, registered in `docs/manifest.yml` and linked from the docs index. It covers approving on the dashboard, reading the lock diff, relocking on the bot's branch, and moving the gaps by hand. A vulnerability-fix pull request may open without approval, since Renovate's `vulnerabilityAlerts` skips the dashboard by default, and still never merges itself.
- [ ] The hand-back states whether the hosted app relocks `pixi.lock`. If it does, the pixi manager's own hold goes, as 0013's "What would reopen this" says. It also records anything the hosted runs show that the local lookup did not.
