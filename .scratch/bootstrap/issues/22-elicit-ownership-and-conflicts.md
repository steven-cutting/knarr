# 22: Elicit: ownership marker, write mode and conflicts (§9.10)

**Context:** OVERVIEW §8 proposes a knarr marker annotation that holds the last-written value and a timestamp. §9.10 leaves open:

- the marker's design
- the write mode: an unconditional merge patch, a `resourceVersion` precondition, or a JSON Patch `test`
- emitting an Event and backing off when another writer changes the value
- the LIST-to-PATCH window: S1's probe decides `NoPatchWhileTerminating` from the last LIST and patches unconditionally, so a `deletionTimestamp` set between the two is not seen. A `resourceVersion` precondition or a JSON Patch `test` is what closes it (raised in the review of pull request #15)

Other writers include user-set values, the lablabs and zepellin controllers, and Karpenter with `PodDeletionCostManagement` enabled. The goal is that the other writer wins.

**What to build:** Allium clauses for ownership and conflict handling, settled with the maintainer, that the patcher and the cleanup rules (23) can rely on.

**Non-goals:** Freshness and restart semantics (23). Rate limits (24).

**Blocked by:** 17

**MVP critical path:** yes. Every patch knarr writes depends on the marker and the write mode.

**Status:** needs-human

- [ ] The `elicit` skill is run with the maintainer in a live session.
- [ ] Every open point above is settled and recorded before any clause is written. What the chosen write mode needs from the client (patch content types, preconditions) is recorded in the hand-back. S1 (14) will normally have landed with a plain merge patch by then, so the client module's spec-then-build follow-up drafted by 14 is amended to carry these requirements.
- [ ] The clauses cover the marker, the write mode, conflict detection, the Event and the back-off. `check-specs` and `analyse-specs` report nothing.
- [ ] The hand-back gives the `plan-spec` obligation count and drafts the spec-then-build follow-up ticket.
