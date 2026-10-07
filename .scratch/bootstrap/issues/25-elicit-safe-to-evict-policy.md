# 25: Elicit: `safe-to-evict` policy (§9.9)

**Context:** OVERVIEW §6 makes `cluster-autoscaler.kubernetes.io/safe-to-evict` opt-in per workload in the MVP. §9.9 leaves open:

- the threshold
- removing the annotation versus writing `"true"`, which matters for pods with emptyDir or hostPath storage
- how to avoid pinning nodes

S2a (15) supplies the upstream CA evidence. S2b (16) may amend the clauses once GKE access exists.

**What to build:** Allium clauses for when knarr sets, flips and removes `safe-to-evict`, settled with the maintainer, grounded in S2a's findings.

**Non-goals:** Expiry and cleanup of the annotation (23). GKE confirmation (16).

**Blocked by:** 15, 17

**MVP critical path:** yes, for the opt-in `safe-to-evict` feature only.

**Status:** needs-human

- [ ] The `elicit` skill is run with the maintainer in a live session.
- [ ] Every open point above is settled and recorded before any clause is written. Each one cites the S2a evidence it relies on, and S2b's (16) if that has landed.
- [ ] The clauses cover the threshold, the remove-versus-`"true"` rule, local-storage pods and node-pinning protection. `check-specs` and `analyse-specs` report nothing.
- [ ] The hand-back gives the `plan-spec` obligation count, drafts the spec-then-build follow-up ticket, and, if 16 has not landed, notes which clauses S2b must confirm.
