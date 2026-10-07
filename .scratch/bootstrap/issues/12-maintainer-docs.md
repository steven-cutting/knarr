# 12: Maintainer docs

**Context:** This adapts libpawdoku's T10. The README is a stub today. Contributors will mostly be agents working from local tickets in separate worktrees.

**What to build:** A visitor learns what knarr is and where it stands. A security reporter knows how to report privately. A contributor, human or agent, knows how to pick up a ticket, work in a worktree, and get a change merged.

**Non-goals:** User-facing install or KEDA pairing guides (round 2). API reference.

**Blocked by:** 11

**MVP critical path:** no. These are project hygiene docs, and nothing in the MVP chain reads them.

**Status:** ready-for-agent

- [ ] The README says what knarr is, its status (pre-MVP), and the quickstart (`just initialize`, `just check`), and links to OVERVIEW and the docs index.
- [ ] The CHANGELOG follows Keep a Changelog and has an Unreleased section.
- [ ] SECURITY points to GitHub private vulnerability reporting and states the supported versions.
- [ ] CONTRIBUTING covers:
  - the ticket workflow (frontier, statuses, hand-back notes)
  - one worktree per ticket and the branch convention
  - the first-run network grant
  - no hook installs from worktrees
  - which actions need explicit authorization
- [ ] Every new page is registered in the docs manifest, and `just check` is green.
