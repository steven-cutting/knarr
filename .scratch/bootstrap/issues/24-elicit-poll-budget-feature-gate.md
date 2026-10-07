# 24: Elicit: poll interval, concurrency, write budget and feature-gate check (§9.8, §9.11)

**Context:** OVERVIEW §9.8 leaves open:

- numeric defaults
- a v1 scale target (pods, Deployments, interval)
- the LIST cadence
- limits per Deployment and per cluster
- the expected API write rate

The §8 failure-mode table adds API throttling (APF, 429) and poll fan-out. §9.11 offers three ways to handle the `PodDeletionCost` feature-gate prerequisite:

- (i) document only
- (ii) a startup self-test
- (iii) a periodic check

A §3 success criterion requires that the patch rate stays within the configured write budget.

**What to build:** Allium clauses for polling, concurrency, the write budget, back-off and the feature-gate check, settled with the maintainer.

**Non-goals:** Metric names and Events in general (§9.14, round 2).

**Blocked by:** 17

**MVP critical path:** yes. The write budget is an MVP success criterion.

**Status:** needs-human

- [ ] The `elicit` skill is run with the maintainer in a live session.
- [ ] Every open point above is settled and recorded before any clause is written, including the write-budget threshold handed to §9.16.
- [ ] The clauses cover the poll schedule, bounded concurrency with jitter, no overlapping polls, the per-pod and global write limits, APF and 429 back-off, and the chosen feature-gate check. `check-specs` and `analyse-specs` report nothing.
- [ ] The hand-back gives the `plan-spec` obligation count and drafts the spec-then-build follow-up ticket.
