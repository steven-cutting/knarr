# 07: Allium gate

**Context:** This adapts libpawdoku's T24. knarr's behaviour will be specified in Allium before it is built (OVERVIEW §9 lists the open questions the specs settle). The Allium binary's exit code cannot be trusted, so the runner reads its JSON output, as 02 records.

**What to build:** `just check` fails on any Allium diagnostic or analysis finding, against a project-managed Allium binary pinned by checksum. A root spec skeleton passes. `plan-spec` reports the obligation count, so later tickets can hand it back.

**Non-goals:** Writing any behaviour clauses (17–25). Vendoring the Allium agent skills (09).

**Blocked by:** 03

**From 02:** [Decision 0004](../../../docs/decisions/0004-gate-checkers.md) settles 02. The installer is dropped: allium is two `tools.txt` lines, installed by 0003's recipe, so the first box below is met by adding those lines. This ticket copies `run_allium.py`, with the specs path in `checks.toml` `[allium]` and its version check reading `tools.txt`. See [02's hand-back notes](02-gate-checkers-decision.md#follow-ups-for-07).

**MVP critical path:** yes. Every elicitation ticket writes clauses that must pass this gate.

**Status:** done

- [x] An installer downloads a pinned allium-tools version, checks it by SHA-256 for `linux-64` and `osx-arm64`, and installs it into the gitignored tool directory. It is part of `just initialize`.
- [x] `check-specs` fails when the JSON diagnostics are not empty, whatever the exit code.
- [x] `analyse-specs` fails when the findings are not empty.
- [x] Both run inside `just check`, and a deliberately broken spec fails the gate (shown in the hand-back notes, not committed).
- [x] `plan-spec` prints the obligation count for a module. It is not part of the gate.
- [x] A root spec skeleton exists, and the checker and the analyser both accept it.

## Hand-back notes

- Allium 3.6.1 is pinned for linux-64 and osx-arm64 in `tools.txt`, using
  Decision 0004's archive checksums. The existing initializer installs it;
  no separate installer or runtime was added. The osx-arm64 download passed
  the installer's SHA-256 check during this ticket.
- The copied runner retains the upstream report checks and provenance. It
  reads `[allium] specs`, verifies the host pin against `.tools/bin/allium
  --version`, and never resolves Allium through `PATH`. Missing binaries or
  version drift direct the contributor to `just initialize`.
- Reports must cover every module recursively and contain both arrays. The
  runner additionally rejects null or non-array diagnostic/finding fields.
  Focused CLI tests cover diagnostics despite exit 0, findings, malformed or
  incomplete reports, omitted modules, back-to-back JSON, status 2, nonzero
  status with empty arrays, missing/wrong binaries, and planning counts.
- The root skeleton is `docs/specs/knarr.allium`, with language version 3 and
  no behaviour clauses. Both real-binary checks accept it, and
  `just plan-spec docs/specs/knarr.allium` reports **0 obligations**.
- Broken-spec proof (osx-arm64): temporarily appended `this is not valid
  Allium` at line 6 of the root skeleton, then ran `just check`. After
  lock-check, env-check and manifest-check passed, check-specs reported
  `1 diagnostic`, naming line 6 and `expected declaration`, and the gate
  exited 1. The broken clause was removed before committing.
- For 09: the specs directory to use in guidance and the phrase list is
  **`docs/specs/`**. Later elicitation tickets should hand back their module's
  `just plan-spec <module>` obligation count.
