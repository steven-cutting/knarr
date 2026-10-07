# 10: Spike: local cluster, test tiers and the worktree-friendly loop

**Context:** OVERVIEW §9.16 asks for unit tests, kind end-to-end tests with a fake worker, and an envtest equivalent or substitute. The starting position, which this spike confirms or overturns:

- **kind** is the canonical cluster for CI and e2e: real pods, a real SA token, real cluster TLS. S1 and the KEDA e2e need it.
- **kwok** is the fast integration tier. It runs a real apiserver plus kube-controller-manager, so ReplicaSet victim ranking with `pod-deletion-cost` should work in seconds, but its pods have no network.
- **envtest** is apiserver and etcd only, with no controllers.
- **OrbStack** Kubernetes is an optional local loop. Local images and pod IPs are reachable from the Mac, but it does not run in CI and its k3s basis is undocumented.
- **TestContainers** is skipped. The only Gleam option wraps the Elixir library, and it cannot exercise the in-pod TLS and token path.

**What to build:** A decision on which cluster serves which test tier, locally and in CI. The setup must hold up under an agent-heavy workflow with many git worktrees running at once.

**Non-goals:** Deploying knarr (13). Cluster Autoscaler experiments (15).

**Blocked by:** 01

**MVP critical path:** yes. The walking skeleton (13), the e2e tier and the CA spike (15) run on what this decides.

**Status:** ready-for-agent

- [ ] kind, k3d, OrbStack, kwok and envtest are compared on four criteria:
  - real kube-controller-manager behaviour
  - the same runner locally and in CI
  - speed: create-to-ready time and image-load time, measured
  - fitness for many concurrent worktrees
- [ ] Worktree fitness is shown, not asserted. Two worktrees run their own cluster or namespace at once without collision. The ticket covers naming derived from the worktree, a per-worktree `KUBECONFIG`, no fixed host ports, and image loading.
- [ ] kwok is shown to honour `pod-deletion-cost` in ReplicaSet scale-down, or the gap is recorded.
- [ ] The ticket records whether Cluster Autoscaler's kwok cloud provider exists and runs, and hands the answer to 15.
- [ ] The kind node image and the kwok version are pinned. Tool sources follow 01.
- [ ] The TestContainers, respx-equivalent and inline-snapshot-equivalent verdicts are recorded with reasons.
- [ ] A tier table (unit / kwok / kind / GKE) says what each tier proves and where it runs.
- [ ] A decision record is written. Follow-ups are drafted, including the cluster recipes 13 will add.
