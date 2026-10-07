# 15: Spike S2a: upstream Cluster Autoscaler and `safe-to-evict` flips on its kwok provider

**Context:** OVERVIEW §6 and §9.9 leave two questions open:

- Does Cluster Autoscaler re-check `safe-to-evict` just before evicting?
- Does a flip reset its per-node unneeded timer?

The core MVP mechanism (`pod-deletion-cost` with ReplicaSet scale-down) does not use CA at all, so these questions gate only the opt-in `safe-to-evict` policy. Not every GKE cluster uses CA: on GKE Standard it is opt-in per node pool. This half of S2 studies upstream CA locally through its kwok cloud provider, so an agent can do it. The provider's existence is unverified; 10 reports on it. S2b (16) confirms on GKE.

**What to build:** Reproducible local experiments showing how upstream CA treats `safe-to-evict` changes, backed by references to CA's source, and a recommended starting position for §9.9.

**Non-goals:** GKE (16). Writing §9.9 clauses (25).

**Blocked by:** 10

**MVP critical path:** yes, for the opt-in `safe-to-evict` feature only. The core mechanism ships without it.

**Status:** done. See [Decision 0008](../../../docs/decisions/0008-safe-to-evict-on-upstream-ca.md) and its [evidence](../evidence/15/README.md).

- [x] Upstream CA runs against a kwok-backed cluster with its kwok cloud provider. If that does not work, the ticket records why and proposes and uses the nearest alternative.
- [x] The CA version is pinned, and the record notes how it relates to the versions GKE currently runs, as far as public sources say.
- [x] Experiment 1: a pod with `safe-to-evict: "false"` on an otherwise removable node prevents removal.
- [x] Experiment 2: flipping the annotation after the node is marked unneeded but before eviction shows whether CA re-checks.
- [x] Experiment 3: removing or flipping the annotation shows whether the unneeded timer resets, measured against the configured unneeded time.
- [x] Each observed behaviour cites the CA source that explains it.
- [x] The recommendation for §9.9 covers the threshold, removing the annotation versus writing `"true"`, and how to avoid pinning nodes.
- [x] A decision record is written. Follow-ups are drafted for 25 and as a test plan for 16.

## Hand-back notes

These are corrections to the premise above, found while gathering the evidence on 2026-10-07:

- The kwok provider works for scale-down as well as scale-up, at `cluster-autoscaler-1.35.2`, with no patches. No alternative was needed.
- **A spell of `"false"` costs more than its own length.** A node CA finds blocked is not simulated again until `--unremovable-node-recheck-timeout` (R, 5m by default) has run from when CA found it blocked, whatever happens to the annotation meanwhile. So a node held `"false"` for F is out of the unneeded set for between max(F, R) and F + R, then needs a full unneeded time again: at least 15 minutes with upstream defaults. Leg C of [exp3](../evidence/15/exp3-timer.txt) shows it, and 0008 gives the source.
- The flag that sets the wait between tainting and draining is `--node-delete-delay-after-taint` (5s by default). CA re-checks the drain rules once, after that wait. It never re-reads them during eviction retries.
- `safe-to-evict: "on-completion"` (autoscaler PR #9355) first shipped in `cluster-autoscaler-1.36.0`. It is not in 1.35.2. [DEFERRED §8](../../../docs/DEFERRED.md#8-other-future-targets) now says so.
- OVERVIEW is unchanged by this ticket. §6 and §9.9 stay open until 16 and 25 settle them.

### Follow-ups for 25

Each point cites [Decision 0008](../../../docs/decisions/0008-safe-to-evict-on-upstream-ca.md) and its transcripts. The suggested clause shapes are starting points for the `elicit` session.

- **Threshold and hysteresis.** Every `"false"` → absent transition hides the node from scale-down for max(F, R) to F + R, then a full unneeded time ([exp3](../evidence/15/exp3-timer.txt), leg C). Shape: a rule that sets `"false"` only from the top band or bands, and a rule that removes it only after the cost has stayed below a lower edge for a minimum time, with that gap wider than one band.
- **Remove versus `"true"`.** Absent and `"true"` keep the unneeded timer alike (exp3 legs A and B), but `"true"` skips the PDB rule in simulation, so a PDB-covered pod's node is tainted and its drain attempted ([exp2](../evidence/15/exp2-recheck.txt) (c)). Shape: knarr only ever writes `"false"` or deletes the annotation, and an invariant that it never writes `"true"`.
- **Local-storage pods.** With CA's default `--skip-nodes-with-local-storage=true`, a disk-backed `emptyDir` blocks with the annotation absent, and `"true"` or `safe-to-evict-local-volumes` unblocks it ([exp4](../evidence/15/exp4-local-storage.txt)). Shape: knarr leaves `safe-to-evict-local-volumes` to the user and documents it, rather than writing `"true"`. GKE says local storage does not block on 1.22 or later, so 16 decides whether this matters there.
- **Exact value.** Only the exact strings `"true"` and `"false"` count; anything else is absent (`source.txt`, `drain.go`). Shape: the written value is the literal `"false"`.
- **Pinning.** CA does not cordon a node it keeps for a `"false"` pod, so new pods can still land there ([exp1](../evidence/15/exp1-false-blocks.txt): no taint). Shape: a cap on the share of a workload's pods marked at once, and a cap on how long one mark is held, with expiry left to 23.
- **Best-effort.** The mark is honoured through simulation and the one re-check after the taint delay ([exp2](../evidence/15/exp2-recheck.txt) (b)), and ignored once eviction has started ((c)). Shape: no clause may promise protection once a node is being drained.

### Follow-ups for 16

A test plan for GKE Standard. Every cloud action needs the maintainer's approval first.

- **Setup.** One GKE Standard cluster on the Regular channel's default (1.35 today), with one autoscaled node pool (min 0, max 3, a small machine type) and one fixed node pool of one node in no autoscaling, as the place pods move to. Record the cluster version, the node pool versions and the autoscaling profile (`balanced`, then optionally `optimize-utilization`).
- **The same experiments.** Port [exp1](../evidence/15/exp1-false-blocks.sh) to [exp4](../evidence/15/exp4-local-storage.sh), keeping 15's setup trap: place the pod on a new autoscaled node by cordoning the fixed pool during the scale-up, then uncordon it.
- **Observables in place of CA's log.** GKE's [cluster autoscaler visibility](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cluster-autoscaler-visibility) events in Cloud Logging: `noScaleDown` with `no.scale.down.node.pod.not.safe.to.evict.annotation` for Exp1 and Exp3, the local-storage reason for Exp4 (if any), and `scaleDown` decisions with their timestamps. Also node taints (`ToBeDeletedByClusterAutoscaler`, `DeletionCandidateOfClusterAutoscaler`), node events (`ScaleDownFailed`) and the apiserver's eviction responses. These events are best-effort, so record the node and pod state as well.
- **Timelines.** Assume a 10-minute unneeded time (GKE's documented balanced value) and an unknown recheck timeout R. Exp3 leg C then measures R: flip to `"false"`, flip back after one minute, and time the node's return to unneeded. Budget at least 30 minutes per leg. Exp2 (b) needs a flip inside GKE's taint-to-drain delay, which is undocumented; try it, and record if it cannot be hit.
- **Teardown.** Delete the cluster and confirm in the hand-back that no cluster, node pool or disk is left (`gcloud container clusters list`, `gcloud compute disks list`).
