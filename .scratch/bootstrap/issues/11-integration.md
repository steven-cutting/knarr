# 11: Integration

**Context:** This adapts libpawdoku's T11. The setup lanes (04–09) are each green on their own branch. This ticket proves that together they deliver what 03 promised, on a fresh machine and in CI.

**What to build:** A fresh clone reaches a green `just check` with one `just initialize`. CI is green on `main`, branch protection is verified, and every claim the lanes left unverified is either closed or turned into a ticket.

**Non-goals:** New tooling or new validators. A gap becomes a follow-up ticket, not a fix inside this one, unless it is a one-line correction.

**Blocked by:** 04, 05, 06, 07, 08, 09

**MVP critical path:** no. It consolidates the setup lanes, and no MVP ticket waits on it.

**Status:** verified

- [x] In a new directory, a fresh clone runs `just initialize` and then `just check`. Both are timed and the times recorded. `just check` then passes again with the network off. See the cache limitation below.
- [x] A linked worktree runs `just check` green without installing hooks.
- [x] CI is green on `main`.
- [x] A read-only `gh api` call confirms branch protection on `main`, with `check` as the only required status check.
- [x] Every claim marked unverified in the hand-backs from 01–09 is closed with evidence or drafted as a follow-up.

## Hand-back notes

The [evidence and claim inventory](../evidence/11/README.md) record verification on 2026-10-08 at `4f0eca5c342493c7830cf6be77791f2207956115`, which was both this branch's starting commit and GitHub's current `main`.

- **Fresh clone:** one `just initialize` took 14.950 seconds; `just check` took 91.067 seconds and passed again in 69.711 seconds under a network-denying macOS sandbox. The clone remained clean. The pixi cache was empty and isolated; Gleam's existing user cache was reused. This is not the fully cold timing 03 deferred: [35](35-bootstrap-verification-gaps.md) retains that claim.
- **Linked gate:** `just check` passed in 93.423 seconds with 13 Gleam tests and 285 checker tests, ending with "All checks passed and the worktree is unchanged." The gate preserved the in-progress evidence diff; a clean final commit is verified separately.
- **Linked initialization:** printed the hook-skip notice; all 15 shared hook-file hashes were unchanged. No hook was installed from this worktree.
- **CI:** [run 37745546445](https://github.com/steven-cutting/knarr/actions/runs/37745546445) passed the repository gate and aggregate `check` at the audited SHA, including 13 Gleam tests and 285 checker tests on native Linux.
- **Branch protection:** the audit found the required-check list empty and prepared [an exact minimal request and payload](../evidence/11/README.md#prepared-branch-protection-change). The maintainer then applied the setting through GitHub's settings page; the prepared request was never run. A [read-only read-back](../evidence/11/README.md#branch-protection-read-back) at 2026-10-09T03:19Z confirms `check` from GitHub Actions app `15368` is the only required status check, with every other protection setting unchanged and no rulesets. `state.sh check` exited 0. Administrators remain exempt by 04's decision, so `check` binds pull requests but not the owner's direct pushes. [CI run 37877497805](https://github.com/steven-cutting/knarr/actions/runs/37877497805) passed on `main` at `c96e106`.
- **Remaining claims:** [35](35-bootstrap-verification-gaps.md) owns fully cold timing, native TLS/rebar3 probes, the primary hook, the unidentified intermittent test, hosted audit execution, unexercised snapshot commands, version-fixture provenance and Copilot discovery. No new tooling or validators were added.
- **Adversarial review:** Claude Code's latest-Opus alias resolved to Opus 5.5, invoked at medium effort with read-only tools. It reported two medium and five low findings, no high findings. The [review and dispositions](../evidence/11/README.md#adversarial-review) record the corrections, including follow-up discoverability, retained observations and the stricter agent-sandbox limitation now tracked by 35. Final validation includes all new files after staging.

### For later tickets

- **05:** its required-check box is closed by the [read-back](../evidence/11/README.md#branch-protection-read-back). Binding administrators, if a later lane wants `check` unbypassable, is the authorized call 04 names.
- **12:** the fresh-clone workflow is proven with the explicit Gleam-cache limitation. Link existing setup and testing documentation rather than copying this audit's commands into another owner page.
- **13 and 14:** a native Linux green gate does not prove the standalone TLS or rebar3 probes. Coordinate those results with 35 before relying on them.
- **35:** every open verification item has a source ticket and acceptance criteria; keep claims open until the named behaviour is actually observed.
