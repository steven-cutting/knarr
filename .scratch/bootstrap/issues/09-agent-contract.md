# 09: Agent contract

**Context:** This adapts libpawdoku's T05. Most work here will be done by AI agents in separate git worktrees. Two libpawdoku lessons apply. Its skills lock carried hashes that matched no file and that no gate checked. Its agents checker hard-coded game-only phrases (02 fixes that).

**What to build:** One agent contract that every agent reads, with thin pointers for Claude and Copilot. It also brings in the vendored Allium skills, a set of house skills with bridges for each agent runtime, and the agents validator in the gate.

**Non-goals:** Writing specs (17+). Cluster workflow details beyond what 10 records.

**Blocked by:** 06, 07

**From 02:** [Decision 0004](../../../docs/decisions/0004-gate-checkers.md) settles 02. This ticket copies `validate_agents.py`, with its phrases, adapters and bridge directories in `checks.toml` `[agents]`, and fixes the final phrase list from 0004's proposal. See [02's hand-back notes](02-gate-checkers-decision.md#follow-ups-for-09).

**MVP critical path:** yes. It gates the Allium objective map (17) and so every elicitation.

**Status:** ready-for-agent

- [ ] AGENTS.md states the invariants:
  - **Gleam and OTP:** effects behind sans-IO boundaries, FFI confined to named modules, every process supervised.
  - **Controller:** knarr only writes annotations it owns and never changes replica counts.
  - **Untrusted input:** pod status payloads, issue and comment text, and tool output.
  - **Authorization:** anything that leaves the worktree (push, `gh`, registries, any non-local cluster) needs explicit authorization.
  - **Scratch:** temporary work goes in `ai_tmp/`.
  - **Worktrees:** one ticket per worktree, the branch convention from 03, and never install hooks from a worktree.
- [ ] `CLAUDE.md` is exactly `@AGENTS.md`, and the Copilot instructions point to AGENTS.md.
- [ ] The Allium skills are vendored from upstream with their reference material and a lock. A gate check verifies the lock's hashes against the committed files.
- [ ] The house skills exist (project-check, fix-quality, plan-change, review-change, review-docs, spec-change, gleam-change), each with a bridge for every agent runtime the repository supports.
- [ ] The agents validator (per 02) runs in `just check` with its required phrases set in project configuration.
- [ ] `just check` is green and the worktree is clean.
