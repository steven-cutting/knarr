# 12: Maintainer docs

**Context:** This adapts libpawdoku's T10. The README is a stub today. Contributors will mostly be agents working from local tickets in separate worktrees.

**What to build:** A visitor learns what knarr is and where it stands. A security reporter knows how to report privately. A contributor, human or agent, knows how to pick up a ticket, work in a worktree, and get a change merged.

**Non-goals:** User-facing install or KEDA pairing guides (round 2). API reference.

**Blocked by:** 11

**MVP critical path:** no. These are project hygiene docs, and nothing in the MVP chain reads them.

**Status:** done. See [the hand-back notes](#hand-back-notes).

- [x] The README says what knarr is, its status (pre-MVP), and the quickstart (`just initialize`, `just check`), and links to OVERVIEW and the docs index.
- [x] The CHANGELOG follows Keep a Changelog and has an Unreleased section.
- [x] SECURITY points to GitHub private vulnerability reporting and states the supported versions.
- [x] CONTRIBUTING covers:
  - the ticket workflow (frontier, statuses, hand-back notes)
  - one worktree per ticket and the branch convention
  - the first-run network grant
  - no hook installs from worktrees
  - which actions need explicit authorization
- [x] Every new page is registered in the docs manifest, and `just check` is green. The new root maintainer documents are excluded from the handbook manifest by the documentation contract.

## Hand-back notes

### What changed

- The [README](../../../README.md) states pre-MVP status and distinguishes the implemented walking skeleton from future worker polling and annotation behaviour. Setup instructions and existing heading anchors remain available, with links to the handbook and the new maintainer documents.
- [CONTRIBUTING.md](../../../CONTRIBUTING.md) explains the frontier, existing statuses, blocker evidence, ticket branches and worktrees, first-run network authorization, shared hooks, verification, hand-back notes and the separately authorized push, pull request and merge workflow. It links the existing setup, testing and documentation owners.
- [SECURITY.md](../../../SECURITY.md) points to the private reporting form ticket 04 enabled. The maintainer chose security support for current `main` only; no published releases are supported yet. No response-time promise or release-support window was introduced.
- [CHANGELOG.md](../../../CHANGELOG.md) follows Keep a Changelog with an Unreleased section describing the existing bootstrap capabilities and maintainer documentation. Release versioning and automation remain ticket 28's decisions.
- The [docs index](../../../docs/README.md#maintainer-documents) links every root maintainer document. No handbook page was added: the [documentation contract](../../../docs/reference/documentation-contract.md#manifest-and-metadata) excludes root maintainer documents, so the manifest and its metadata are unchanged.

### Verification and review

- `just docs-check` validates 23 handbook pages and 26 canonical topics, including links to the new root documents. `just lint` checks the staged new documents with all read-only hooks, including typos, Markdown formatting and offline links.
- The full offline `just check` is the closing gate for this change. The baseline passed with 21 Gleam tests and 312 checker tests. No code, specification, dependency, tool pin or snapshot changed, so no new behavioural test was needed.
- The sandbox denied the OTP application's loopback listener during the baseline gate and prek's cache log during the documentation lint run. The affected read-only recipes passed with execution permission outside the sandbox. No check was weakened or hook installed.
- The requested `code-review` skill is unavailable. Review used the repository's `review-change` procedure on the complete staged diff, checking the controller-status claims, authorization rules, documentation ownership, link navigation and scope. No findings remained.
- External links were checked offline only. The private-reporting setting and CI protection policy come from tickets 04 and 11's recorded evidence; no new GitHub request, online audit, push or cluster operation was made.

### For later tickets

- **28:** establish release versioning, the changelog workflow and supported release versions. Replace the development-only support policy when a released-version policy is decided; do not treat the package version as a released support commitment.
- **34:** add user-facing worker, KEDA and operations guides only after their owning elicitation tickets settle the behaviour. Keep the contributor setup and ticket workflow linked to their existing owners; register new handbook pages in the manifest and link them from the docs index.
