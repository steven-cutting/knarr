# 15: Spike S2a: upstream Cluster Autoscaler and `safe-to-evict` flips on its kwok provider

**Context:** OVERVIEW §6 and §9.9 leave two questions open:

- Does Cluster Autoscaler re-check `safe-to-evict` just before evicting?
- Does a flip reset its per-node unneeded timer?

The core MVP mechanism (`pod-deletion-cost` with ReplicaSet scale-down) does not use CA at all, so these questions gate only the opt-in `safe-to-evict` policy. Not every GKE cluster uses CA: on GKE Standard it is opt-in per node pool. This half of S2 studies upstream CA locally through its kwok cloud provider, so an agent can do it. The provider's existence is unverified; 10 reports on it. S2b (16) confirms on GKE.

**What to build:** Reproducible local experiments showing how upstream CA treats `safe-to-evict` changes, backed by references to CA's source, and a recommended starting position for §9.9.

**Non-goals:** GKE (16). Writing §9.9 clauses (25).

**Blocked by:** 10

**MVP critical path:** yes, for the opt-in `safe-to-evict` feature only. The core mechanism ships without it.

**Status:** ready-for-agent

- [ ] Upstream CA runs against a kwok-backed cluster with its kwok cloud provider. If that does not work, the ticket records why and proposes and uses the nearest alternative.
- [ ] The CA version is pinned, and the record notes how it relates to the versions GKE currently runs, as far as public sources say.
- [ ] Experiment 1: a pod with `safe-to-evict: "false"` on an otherwise removable node prevents removal.
- [ ] Experiment 2: flipping the annotation after the node is marked unneeded but before eviction shows whether CA re-checks.
- [ ] Experiment 3: removing or flipping the annotation shows whether the unneeded timer resets, measured against the configured unneeded time.
- [ ] Each observed behaviour cites the CA source that explains it.
- [ ] The recommendation for §9.9 covers the threshold, removing the annotation versus writing `"true"`, and how to avoid pinning nodes.
- [ ] A decision record is written. Follow-ups are drafted for 25 and as a test plan for 16.
