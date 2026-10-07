# 04: GitHub repository

**Context:** This adapts libpawdoku's T01. The repository is public: `steven-cutting/knarr`, Apache-2.0. Every step here leaves the worktree, so each one is **authorization required**. The agent prepares the exact command, shows it, and runs it only after the maintainer approves.

**What to build:** `steven-cutting/knarr` exists on GitHub with `main` pushed, hygiene settings applied, private vulnerability reporting on, and `main` protected. The required status check is added later by 05, once the `check` job exists.

**Non-goals:** CI workflows (05). Release settings and GHCR (28).

**Blocked by:** 03

**MVP critical path:** yes. CI (05) and image publishing (28) need the remote.

**Status:** ready-for-agent

- [ ] **Authorization required:** the public repository is created with a description, and GitHub detects the Apache-2.0 licence.
- [ ] **Authorization required:** `main` is pushed.
- [ ] **Authorization required:** hygiene settings are applied: merge methods, delete-branch-on-merge, and unused features (wiki, projects) off, as the maintainer chooses.
- [ ] **Authorization required:** private vulnerability reporting, secret scanning with push protection, and Dependabot alerts are on.
- [ ] **Authorization required:** `main` is protected: pull request required, no force pushes, no deletions.
- [ ] Every mutating `gh` command run is listed in the hand-back notes, with a read-only `gh api` call showing the resulting state.
