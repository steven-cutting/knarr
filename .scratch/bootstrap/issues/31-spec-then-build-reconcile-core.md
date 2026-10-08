# 31: Spec-then-build: discovery, the reconcile loop and the emitted cost

**Context:** OVERVIEW §4 and §6 decide the shape of knarr's loop, and no elicitation ticket's acceptance checks name those decided behaviours. [Decision 0009](../../../docs/decisions/0009-allium-objective-map.md) lists them and assigns them here, in the `config`, `reconcile` and `banding` modules, next to the clauses that 19, 20 and 21 elicit. Those tickets draft their own spec-then-build follow-ups; they amend this ticket rather than duplicate it.

**What to build:** Clauses for each decided behaviour below, written with the `tend` skill without a live session because OVERVIEW already decides them, then tests derived with `propagate` and the controller code that passes them, in the order the `gleam-change` skill sets.

**Non-goals:** Any open question 19, 20 or 21 owns. The ownership and lifecycle invariants (32). Rate limits and back-off (24).

**Blocked by:** 19, 20, 21

**From 17:** [Decision 0009](../../../docs/decisions/0009-allium-objective-map.md), map rows for §4, §5 and §6.

**MVP critical path:** yes. This is the loop the MVP runs.

**Status:** ready-for-agent, round 2

- [ ] Discovery is a periodic LIST scoped to knarr's namespace and the opt-in selector, on its own cadence and slower than polling, with one install per namespace (§4.1, §9.18).
- [ ] The per-poll timeout is shorter than the poll interval (§4.2).
- [ ] The desired annotation state is the cost band, the opt-in `safe-to-evict` value and the ownership marker, derived from a clamped cost combined with `accepting` (§4.3).
- [ ] A patch is made only when the desired state differs from the last applied state, which covers a band change, the first annotation, startup repair, cleanup and a `safe-to-evict` flip (§4.4).
- [ ] A throttled change stays pending and is not dropped (§4.4).
- [ ] No patch is made once a pod has `deletionTimestamp` set; polling it may continue (§4.5).
- [ ] The emitted `pod-deletion-cost` is a canonical signed decimal int32 string, never a form such as `"+5"` or `"007"` (§6).
- [ ] A pod that has just started stays unannotated until its first valid poll (§5).
- [ ] A Deployment rollout gets no special handling (§8 failure modes, §9.13).
- [ ] Each clause has a test that traces to it, `just check` passes, and the hand-back gives the `plan-spec` obligation count of each module touched.
