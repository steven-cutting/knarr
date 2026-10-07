# 16: Spike S2b: confirm on GKE Standard's managed CA

**Context:** The MVP target platform is GKE Standard (OVERVIEW §1, MVP at a glance). GKE runs a managed Cluster Autoscaler whose version and profile may behave differently from upstream. This ticket repeats S2a's experiments (15) there. It is blocked until GKE access exists. Everything else, including the GKE deploy itself, proceeds without it.

**What to build:** Evidence that GKE's managed CA treats `safe-to-evict` flips the way S2a found, or a clear statement of how it differs, fed back into the §9.9 policy.

**Non-goals:** Production rollout. A GKE CI tier.

**Blocked by:** 15, plus GKE Standard access (external)

**MVP critical path:** yes, for the opt-in `safe-to-evict` feature only. The core mechanism and the GKE deploy proceed without it.

**Status:** needs-human

- [ ] **Authorization required:** every cloud action (cluster and node-pool creation, image push, teardown) is approved by the maintainer before it runs.
- [ ] S2a's three experiments run on a GKE Standard node pool with autoscaling on. The GKE version and the autoscaling profile are recorded.
- [ ] Any difference from S2a is recorded, with evidence.
- [ ] The §9.9 clauses from 25 are confirmed, or an amendment is drafted.
- [ ] All cloud resources are torn down, and the hand-back notes show it.
- [ ] A decision record is written or amended, and follow-ups are drafted.
