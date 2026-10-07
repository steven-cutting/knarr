# 07: Allium gate

**Context:** This adapts libpawdoku's T24. knarr's behaviour will be specified in Allium before it is built (OVERVIEW §9 lists the open questions the specs settle). The Allium binary's exit code cannot be trusted, so the runner reads its JSON output, as 02 records.

**What to build:** `just check` fails on any Allium diagnostic or analysis finding, against a project-managed Allium binary pinned by checksum. A root spec skeleton passes. `plan-spec` reports the obligation count, so later tickets can hand it back.

**Non-goals:** Writing any behaviour clauses (17–25). Vendoring the Allium agent skills (09).

**Blocked by:** 03

**From 02:** [Decision 0004](../../../docs/decisions/0004-gate-checkers.md) settles 02. The installer is dropped: allium is two `tools.txt` lines, installed by 0003's recipe, so the first box below is met by adding those lines. This ticket copies `run_allium.py`, with the specs path in `checks.toml` `[allium]` and its version check reading `tools.txt`. See [02's hand-back notes](02-gate-checkers-decision.md#follow-ups-for-07).

**MVP critical path:** yes. Every elicitation ticket writes clauses that must pass this gate.

**Status:** ready-for-agent

- [ ] An installer downloads a pinned allium-tools version, checks it by SHA-256 for `linux-64` and `osx-arm64`, and installs it into the gitignored tool directory. It is part of `just initialize`.
- [ ] `check-specs` fails when the JSON diagnostics are not empty, whatever the exit code.
- [ ] `analyse-specs` fails when the findings are not empty.
- [ ] Both run inside `just check`, and a deliberately broken spec fails the gate (shown in the hand-back notes, not committed).
- [ ] `plan-spec` prints the obligation count for a module. It is not part of the gate.
- [ ] A root spec skeleton exists, and the checker and the analyser both accept it.
