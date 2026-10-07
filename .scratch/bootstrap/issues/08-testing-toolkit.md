# 08: Testing toolkit

**Context:** This adapts libpawdoku's T29. Gleam has no source-rewriting snapshot tool like inline-snapshot. `birdie` 2.x gives file snapshots in the style of insta, with review, accept and stale commands. There is no respx equivalent either, so effects sit behind sans-IO boundaries: pure request builders and decoders, plus an injected `send` function that a test replaces with a closure. `http_server_mock` (hex, young) is the fallback only where a real socket is needed. OVERVIEW §9.16 asks for unit tests of the mapping and banding.

**What to build:** A contributor can write unit, property and snapshot tests, run them in the read-only gate, and review snapshot changes deliberately. A worked sans-IO example shows the pattern every Kubernetes and worker-poll call will follow.

**Non-goals:** Coverage (26). Cluster test tiers (10). A real Kubernetes client (14).

**Blocked by:** 03, 06

**MVP critical path:** yes. The walking skeleton (13) and S1 (14) use this toolkit and pattern.

**Status:** ready-for-agent

- [ ] gleeunit, qcheck and birdie are pinned dependencies, each with one example test. glinter runs in `just check`.
- [ ] The snapshot recipes are:
  - a non-writing check, inside `just check`, that fails on a new or changed snapshot
  - stale, which lists unused snapshots
  - review and accept, both outside the gate
- [ ] The ticket verifies how birdie behaves in check mode and records it.
- [ ] The rule "a snapshot proves no clause" is written down. A spec obligation needs a named assertion, not a snapshot.
- [ ] A worked sans-IO example: a pure request builder, a pure decoder, and a function that takes `send`. A closure fake exercises it, and the outgoing request is snapshotted.
- [ ] A testing reference page, registered in the docs manifest, covers the tiers known so far, the snapshot workflow and the sans-IO pattern. It links to 10 for cluster tiers.
- [ ] `just check` is green and the worktree is clean.
