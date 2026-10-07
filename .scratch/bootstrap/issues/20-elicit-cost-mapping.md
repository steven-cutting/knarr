# 20: Elicit: cost mapping, bands, hysteresis and sign convention (§9.5)

**Context:** OVERVIEW §6 explains how `pod-deletion-cost` biases ReplicaSet victim ranking, and the explainer illustrates bands and the sign convention. §9.5 leaves open:

- the sign convention
- the knarr-owned range
- the number of bands and their edges
- hysteresis
- reserved bands
- how `cost` and `accepting` combine (§5 drain states)

The sign convention also fixes what removing an annotation means, which §9.12 depends on (23).

**What to build:** Allium clauses for the reconciler's clamp → band → hysteresis → decide-patch path (OVERVIEW §8), settled with the maintainer.

**Non-goals:** Unknown and unreachable handling (21). Write budgets (24).

**Blocked by:** 18

**MVP critical path:** yes. This is the core MVP mechanism.

**Status:** needs-human

- [ ] The `elicit` skill is run with the maintainer in a live session.
- [ ] Every open point above is settled and recorded before any clause is written, including what an absent annotation means.
- [ ] The clauses cover clamping, banding, hysteresis, reserved bands and the cost-accepting combination. `check-specs` and `analyse-specs` report nothing.
- [ ] Any open question 19 left on the default or valid range of a band or hysteresis override is closed.
- [ ] The hand-back gives the `plan-spec` obligation count and drafts the spec-then-build follow-up ticket.
