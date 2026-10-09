# 35: Close the remaining bootstrap verification gaps

**Context:** [Ticket 11's audit](../evidence/11/README.md) distinguishes evidence from the claims tickets 01–09 left unverified. The integrated gate is exercised locally and in native Linux CI, but that does not exercise every probe or agent runtime those tickets discussed.

**What to build:** Evidence for the remaining claims below. Record commands, platform, pins, commit, exit status and limitations. Each item can be closed independently.

**Non-goals:** New validators, dependencies, controller behaviour, or changing branch-protection policy. Do not weaken a check to obtain evidence. A substantive defect gets its own ticket.

**Blocked by:** 11

**MVP critical path:** no. The native TLS evidence should be available to 14 before its client relies on it.

**Status:** ready-for-agent

- [ ] **03, fully cold initialization:** On a disposable machine or account with empty pixi and Gleam package caches, time one `just initialize`, then `just check`, then the gate with network denied. Record how cache emptiness and the network denial were established. Ticket 11 isolated pixi's cache, but Gleam reused the macOS user cache; do not report its time as fully cold. Do not clear or relocate another session's shared cache.
- [ ] **01, native Linux TLS and rebar3:** Run the existing TLS probes in both locked default and runtime environments on native linux-64 without the Rosetta flag. Record all six TLS outcomes, matching OTP majors, and the rebar3 dependency compilation and missing-rebar3 negative control. Reuse `evidence/01/tls/run.sh` and `evidence/01/rebar3/run.sh`; ordinary CI does not run these probes. Coordinate the evidence with 13 and 14 rather than introducing a new required CI job here.
- [ ] **03, maintainer's primary hook:** With authorization for that checkout, verify its installed pre-commit hook invokes the intended checkout's environment and rejects an unformatted staged file in a disposable probe. Ticket 03 proved the hook in a throwaway clone; ticket 11 proves the linked worktree leaves shared hooks untouched. Neither claims to have installed or exercised the maintainer's primary hook.
- [ ] **04, intermittent checker test:** Identify the test behind the historical `1 failed, 86 passed` run. Recover an old log if available; otherwise repeat the current checker suite with durable failure output and record the bounded attempt count. A run of green tests alone does not identify or fix it. Once identified, preserve a reproducer and open a focused repair ticket if more than a one-line correction is needed.
- [ ] **06, hosted audit:** Observe a scheduled run of `audit.yml`, or request authorization for one manual dispatch. Record the run URL, commit and result; investigate any failed external links separately. The API reported zero runs during ticket 11. The audit remains outside the required `check` aggregate.
- [ ] **05/06, restricted agent sandbox:** Reproduce and classify the macOS Taplo system-configuration failure under the agent sandbox, recording the supported invocation and required local access. Ticket 11's `toml-check` passes under a network-denying profile and with local escalation; neither proves compatibility with the stricter agent sandbox. Any repair beyond documentation or a one-line correction is a separate ticket, not grounds to weaken the gate or sandbox.
- [ ] **08, snapshot commands:** In a disposable clone, exercise `just snapshots-review` through its interactive review step on a real pending change, `just birdie reject` on a pending change, and `just birdie stale delete` on an orphan. Assert the expected accepted-file bytes, pending-file removal, orphan removal and worktree isolation. The earlier `just -n` output is not runtime evidence.
- [ ] **08, version fixture:** Capture `/version` from the local kind version chosen by 10 and compare the relevant field types with the hand-written example. Verify the managed-cluster `minor` suffix claim from an authoritative versioned source or an explicitly authorized cluster; a local reply alone does not establish it. Hand any fixture correction to 14 with provenance.
- [ ] **09, Copilot discovery:** Exercise native discovery of `.agents/skills/` in an actual Copilot session. Record the runtime version and a harmless skill invocation. Reading GitHub documentation, or discovering the skills in Codex, does not demonstrate Copilot execution.

## Hand-back requirements

Link each result from ticket 11's inventory. Keep raw working material under `ai_tmp/` and durable, reviewed evidence under `.scratch/bootstrap/evidence/35/`. Request authorization separately for network use, hosted dispatch, or access outside the ticket worktree. Record any remaining item as open rather than inferring success from an unrelated green gate.
