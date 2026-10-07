---
title: "Decision 0007: Local cluster and test tiers"
kind: "decision"
audience: [maintainer, agent]
canonical_for: [decision_local_cluster, test_tiers]
requires: [decision_tool_manager]
---

# Decision 0007: Local cluster and test tiers

## Context

OVERVIEW §9.16 asks for unit tests, end-to-end tests on kind with a fake worker, and "an envtest equivalent or substitute". The walking skeleton (13), the in-cluster client spike (14), the Cluster Autoscaler spike (15) and the e2e tier all need a local cluster. That cluster must hold up under an agent-heavy workflow, where many git worktrees each run their own cluster at the same time.

Five runners were candidates: kind, k3d, OrbStack's built-in Kubernetes, kwok (through `kwokctl`) and envtest. They were compared on four criteria:

1. real kube-controller-manager behaviour, because knarr's core mechanism is the ReplicaSet controller ranking victims by `controller.kubernetes.io/pod-deletion-cost` (OVERVIEW §6)
2. the same runner locally and in CI
3. speed: create-to-ready time and image-load time
4. fitness for many concurrent worktrees

[Decision 0003](0003-tool-manager.md) had already fixed the cluster minor at 1.35. It is the one minor that kind 0.33, kwok 0.8, CA and conda-forge's kubectl 1.34.3 all support. 0003 also fixed where each tool comes from: kind and kubectl from pixi's `cluster` environment, and kwok, kwokctl, k3d and setup-envtest as sha256-pinned downloads.

All evidence was gathered on 2026-10-07 on an Apple M5 Pro (Darwin arm64), with OrbStack 2.2.3 and its Docker engine 29.4. The scripts and transcripts are in [`.scratch/bootstrap/evidence/10/`](../../.scratch/bootstrap/evidence/10/README.md). Every timing is a Mac number on a warm image cache.

## Decision

**kind is the canonical cluster** for the e2e tier, 13's smoke test and S1 (14), locally and in CI. **kwok, through kwokctl's docker runtime, is the fast integration tier.** It has a real apiserver, kube-controller-manager and scheduler, with simulated nodes and pods. It is knarr's "envtest equivalent or substitute". envtest, k3d and OrbStack are not tiers.

Every local cluster belongs to one worktree. Its name comes from the worktree path, and its kubeconfig and state live under the worktree. No host port is fixed.

### Tiers

| Tier | Runner | What it proves | What it cannot prove | Where it runs |
|---|---|---|---|---|
| unit | gleeunit, qcheck, birdie (08) | Mapping, banding and every pure function. Request builders and decoders through the sans-IO pattern, with `send` injected | Anything about a real apiserver | `just check`: locally and in CI, on every change |
| kwok | kwokctl 0.8.0, Kubernetes 1.35.5 | Real API semantics: RBAC, `resourceVersion` conflicts, watch and list, patch shapes. Real controllers, including ReplicaSet scale-down honouring `pod-deletion-cost`, and Deployment rollouts. Cluster Autoscaler's kwok provider (15). Up in about 6 s | Anything that needs a pod to run: in-pod TLS, the ServiceAccount token, pod networking, polling a worker. kwok pods never start a container | Locally and in CI, as its own job, outside the read-only gate |
| kind | kind 0.33.0, node v1.35.8 | Everything kwok proves, plus real pods: the in-cluster client with cluster TLS and token reload (S1), knarr's image, the fake worker, KEDA. Up in about 25 s, plus image load | Managed-cloud behaviour: GKE's CA, node pools, Autopilot | Locally, and in CI as 13's smoke job, then the e2e job |
| GKE | a real cluster (16) | GKE's managed CA, and the versions and policies GKE actually runs | | By hand, against a short-lived cluster. Never per change |

### Comparison

Measured with [timing.sh](../../.scratch/bootstrap/evidence/10/timing.txt), [orbstack.sh](../../.scratch/bootstrap/evidence/10/orbstack.txt), [worktree.sh](../../.scratch/bootstrap/evidence/10/worktree.txt) and [deletion-cost.sh](../../.scratch/bootstrap/evidence/10/deletion-cost-kwokctl.txt). Times are medians of three, in seconds. "Load" is a 256 MB stand-in image, about the size of 0003's runtime environment.

| Runner | Real kube-controller-manager | Same runner locally and in CI | Up | Load | Delete | Concurrent worktrees |
|---|---|---|---|---|---|---|
| kind | Yes, upstream kubeadm. `pod-deletion-cost` honoured | Yes. Docker only, and the node image is pinned for amd64 and arm64 | 24.9 | 3.5 | 0.6 | Yes. Three at once, each on its own random `127.0.0.1` port |
| k3d | k3s embeds the upstream controllers in one binary | Possible, but it is a third tool next to kind and kwokctl | 9.9 | 5.5 | 0.4 | Yes, with two workarounds: names of 32 characters or fewer, and `--api-port 127.0.0.1:0` writes `:0` into the kubeconfig. Every new cluster pulls its sandbox image from Docker Hub |
| OrbStack | k3s-based (`v1.35.6+orb1`) | No: macOS only | 2.5 (start) | none needed | | No. One cluster per machine, on the fixed port 26443 |
| kwok | Yes: upstream kube-controller-manager and scheduler, with simulated kubelets. `pod-deletion-cost` honoured | Yes. Docker only, and every image is published for amd64 and arm64 | 5.7 | n/a | 0.8 | Yes, if the apiserver port is passed (see below) |
| envtest | No. etcd and the apiserver only, so a scale to 1 never deletes a pod | Yes, but it is a Go library, and knarr is Gleam | 3.1 | n/a | 1.3 | Yes, on free ports |

Why each one sits where it does:

- **kind** is the only runner that is real enough for S1 and the e2e tier and also standard in CI. Its 25 s start is paid once per worktree session, not per test.
- **kwok** keeps the part of kind that knarr's mechanism depends on, which is the controllers, for under a quarter of the start time. It takes no image load, because no container runs. It also hosts CA's kwok provider, which 15 needs.
- **envtest is dropped.** It saves under 3 s over kwok and loses the kube-controller-manager, which is the thing under test. There is also no Gleam binding, and a shell harness like the one in [cluster.sh](../../.scratch/bootstrap/evidence/10/cluster.sh) is one more thing to maintain. setup-envtest gets no `tools.txt` line.
- **k3d is not adopted.** It starts 2.5 times faster than kind, but it is a different distribution from the one CI and S1 use, and it needs two workarounds. It also leaked a network and a volume when a create failed. Its node image preloads nothing, so every new cluster pulls `rancher/mirrored-pause:3.6` from Docker Hub before its first pod starts. In an earlier run of `timing.sh`, before its pod timeout was raised to 180 s, that pull kept a stand-in pod from starting within 60 s. kind's node image ships with pause. It gets no `tools.txt` line, and it is the first candidate if kind's start time becomes the bottleneck.
- **OrbStack is a personal convenience, not a tier.** It is the fastest to start, a local image runs with no load step, and pod IPs and ClusterIPs answer from the Mac. But there is one cluster per machine on a fixed port, it does not exist in CI, and its k3s basis is not upstream kubeadm. Anyone who uses it isolates by namespace and accepts that every worktree shares it.

### The worktree recipe

[`name.sh`](../../.scratch/bootstrap/evidence/10/name.sh) is the naming seam. Its behaviour is specified by [`name_test.sh`](../../.scratch/bootstrap/evidence/10/name_test.sh) and checked against the real tools in [worktree.txt](../../.scratch/bootstrap/evidence/10/worktree.txt). [`cluster.sh`](../../.scratch/bootstrap/evidence/10/cluster.sh) is the recipe draft.

- **Name.** The name is `<basename>-<8 hex>`. The basename is lower-cased, every run of other characters becomes one dash, and it is cut to 23 characters with no dash at either end, falling back to `wt` if nothing usable is left. The hash is the first 8 hex digits of the sha256 of the physical absolute path. So two worktrees named `knarr` get different clusters, and a symlinked path gets the same one. The cap is 32 characters, k3d's limit and the tightest of the three tools. kind and kwokctl add prefixes and suffixes to their container names, and both fit.
- **State.** Everything goes under `<worktree>/.cluster/`, which is gitignored: `kubeconfig`, and kwokctl's workdir at `.cluster/kwok`. kind gets `--kubeconfig`. kwokctl gets `--kubeconfig` and `KWOK_WORKDIR`, whose default is `~/.kwok`. Every recipe exports `KUBECONFIG=<worktree>/.cluster/kubeconfig`, and no recipe touches `~/.kube/config` or switches a global context. `worktree.sh` hashed `~/.kube/config`, `~/.kwok`, `~/.k3d` and `~/.config/k3d` before and after twelve concurrent clusters, and none of them changed.
- **Ports.** No port is fixed. kind publishes its apiserver on a random `127.0.0.1` port by default. kwokctl's default is not random. It takes the first free port counting down from 32766, chosen before any container binds it, so two clusters created at once both get 32766 and the second apiserver crash-loops (the control in [worktree.txt](../../.scratch/bootstrap/evidence/10/worktree.txt)). The recipe passes `--kube-apiserver-port` with a port the OS reports free. kwokctl publishes that port on `0.0.0.0`, not on localhost, and has no flag to change it.
- **Image loading.** kind uses `kind load docker-image <image> --name <name>`. A pod then uses the image with `imagePullPolicy: Never`, which proves it came from the load and not from a registry. Concurrent loads into three clusters worked. kwok needs no load, and its pods may name any image.
- **Teardown.** `kind delete cluster --name` or `kwokctl delete cluster --name`, then remove `.cluster/`. Concurrent deletes left no container, network, volume or state directory. All kind clusters share Docker's `kind` network by design. That network is not per worktree, and it outlives the clusters.

### Pins

These come from [pins.txt](../../.scratch/bootstrap/evidence/10/pins.txt). Each image publishes both linux/amd64 and linux/arm64.

| What | Pin |
|---|---|
| kind node image | `kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0`, the digest the kind v0.33.0 release notes publish, equal to the registry's |
| kwok, kwokctl | 0.8.0, the binaries 0003 pinned (`tools.txt` lines below) |
| kwok Kubernetes version | `KWOK_KUBE_VERSION=v1.35.5`. kwokctl then pulls `registry.k8s.io/kube-apiserver`, `kube-controller-manager` and `kube-scheduler` at `v1.35.5`, `etcd:3.6.10-0` and `kwok/kwok:v0.8.0`. Their digests are in pins.txt |
| kwok all-in-one cluster image | `registry.k8s.io/kwok/cluster:v0.8.0-k8s.v1.35.5@sha256:77483c585cf148b9689e9800b807e6e6e6cdc7a08363997ef144f0fde41df90a`, for a single-container kwok cluster when kwokctl is unavailable. Not used by the recipe |
| Cluster Autoscaler (for 15) | `registry.k8s.io/autoscaling/cluster-autoscaler:v1.35.2@sha256:aac369dc283927a623deb1af54696efcc722ae79255aa07788422e495bab887d`, re-resolved and unchanged from 0003 |
| kubectl | conda-forge 1.34.3 from the `cluster` environment, one minor behind the 1.35 servers, within kubectl's skew |

The kind node image is pinned by digest in the recipe. kwokctl takes its component images by tag through `KWOK_KUBE_VERSION`. Its `--kube-apiserver-image` flags and the like would take digests, but that path is not exercised here (follow-up for 13).

### Cluster Autoscaler's kwok provider

It exists, and it runs. At tag `cluster-autoscaler-1.35.2`, `cluster-autoscaler/cloudprovider/kwok/` holds the provider and its README. [ca-kwok.sh](../../.scratch/bootstrap/evidence/10/ca-kwok.sh) follows the README's local-mode path. CA 1.35.2 ran as a container from the pinned image on a kwokctl cluster's Docker network. It used kwokctl's in-network kubeconfig, with `KWOK_PROVIDER_MODE=local`, `POD_NAMESPACE=default` and `--cloud-provider=kwok`. The two ConfigMaps, `kwok-provider-config` and `kwok-provider-templates`, defined one nodegroup. A pod that only that nodegroup could hold went `Unschedulable`. CA logged `Final scale-up plan: [{ng-a 0->1 (max: 3)}]` and created node `ng-a-…` with the provider ID `kwok:…`, the `kwok.x-k8s.io/node: fake` annotation and the `kwok-provider` taint. kwokctl's controller, which runs with `--manage-all-nodes=true`, made that node Ready, and the pod was Ready on it about 5 s after it was created. No nearest alternative was needed. The exact setup is in 15's hand-back notes.

### TestContainers, respx and inline-snapshot

| Python habit | knarr's answer | Reason |
|---|---|---|
| TestContainers | Skipped | The only Gleam option wraps the Elixir library. A container started from a test cannot exercise what the cluster tiers exist for: in-pod TLS against the cluster CA and the projected ServiceAccount token. kind covers those, and kwok covers the API semantics without a container |
| respx (mocking an HTTP client) | Sans-IO, with `send` injected | Request builders and decoders are pure, and the function that performs I/O takes `send` as an argument, which a test replaces with a closure (08). `http_server_mock` (hex, young) is the fallback only where a test needs a real socket |
| inline-snapshot | birdie file snapshots | Gleam has no source-rewriting snapshot tool. birdie 2.x gives insta-style file snapshots with review, accept and stale commands (08). A snapshot proves no spec clause |

## Verification

Each script exits non-zero on an unexpected result. [README](../../.scratch/bootstrap/evidence/10/README.md) gives the command that reruns them all.

**Tools ([fetch.txt](../../.scratch/bootstrap/evidence/10/fetch.txt)).** The `cluster` environment installs from 01's manifest with `pixi install --locked -e cluster`, and kind, kubectl, helm and shellcheck print their pinned versions. kwok, kwokctl, k3d and setup-envtest each match their 0003 pin line, a copy with one byte appended is refused, and setup-envtest installs the 1.35.0 assets.

**Naming ([name_test.txt](../../.scratch/bootstrap/evidence/10/name_test.txt)).** Twelve tests cover the plain case, a shared basename, a symlink, odd characters, a long name cut to exactly 32 characters, a cut landing on a dash, a basename with nothing usable, the three paths with a space in the worktree path, and the two error exits.

**pod-deletion-cost ([kwok](../../.scratch/bootstrap/evidence/10/deletion-cost-kwokctl.txt), [kind](../../.scratch/bootstrap/evidence/10/deletion-cost-kind.txt)).** On both runners, a Deployment's 3 Ready pods are scaled to 1 and only the pod at cost 1000 is left. Then the round is reversed. The survivor, now the oldest pod and the one the ReplicaSet would keep without costs, is set to -1000, and a new pod to 1000. The scale to 1 then keeps the new pod.

```text
ok   round 1: the cost-1000 pod is the only survivor
ok   round 2: the cost-1000 pod is the only survivor
verdict: kwokctl's ReplicaSet scale-down honours pod-deletion-cost
```

**Speed ([timing.txt](../../.scratch/bootstrap/evidence/10/timing.txt), [orbstack.txt](../../.scratch/bootstrap/evidence/10/orbstack.txt)).** The figures are the ones in the comparison table. Each load is followed by a pod running the image with `imagePullPolicy: Never`. OrbStack's figure is start-to-ready of an existing cluster from stopped, since OrbStack keeps the cluster's state between starts.

**Worktrees ([worktree.txt](../../.scratch/bootstrap/evidence/10/worktree.txt)).** Each runner gets three clusters created at once: `one/knarr`, `two/knarr` and a 32-character name. Each has its own host port and one context per kubeconfig. A ConfigMap written through each kubeconfig names its own cluster when read back. On kind and k3d a local image loads into all three. Concurrent delete leaves nothing, and the files outside the worktrees are unchanged. The control shows kwokctl's default port colliding.

**OrbStack ([orbstack.txt](../../.scratch/bootstrap/evidence/10/orbstack.txt)).** The transcript shows it finding `k8s.enable: false` and leaving `false`. When this work began, the setting was `true`, on an empty cluster someone had started a few minutes earlier. The first run of `orbstack.sh` recorded that and turned it off. OrbStack also keeps the cluster's objects across a stop and start: a pod deleted without waiting just before a stop was still terminating at the next start. The script now uses per-run names and waits for deletes.

**Not run here: the CI half of "the same runner locally and in CI".** 04 and 05 have not landed, so no runner has executed on linux/amd64. That claim rests on the pins: every image above publishes linux/amd64, and kind, kubectl and the `.tools` binaries are pinned for linux-64 in 0003. 13's CI kind job is the first native confirmation, as 05's run is for 0003's Rosetta results.

## Consequences

- **Per-worktree cost.** Each worktree that runs a cluster installs the `cluster` environment (836 MB on osx-arm64, from [fetch.txt](../../.scratch/bootstrap/evidence/10/fetch.txt)) on top of `default`. A kind cluster adds one node container, and a kwok cluster adds five small ones. Their memory was not measured. On a laptop the practical limit is memory, not names or ports.
- **Two runners to maintain,** kind and kwokctl. Both are already pinned by 0003, so this decision adds no tool. setup-envtest and k3d stay in 0003's escape-hatch table, unused, until something reopens this record.
- **kwok tests cannot reach a pod.** Anything that polls a worker or reads a pod's own token moves up to the kind tier. The kwok tier tests knarr's API calls and the controllers' reaction to them.
- **kwokctl's published port is on `0.0.0.0`.** A kwok apiserver is reachable from the local network while it runs. Its client certificate stays under the worktree, so this matters only on an untrusted network. It is recorded in the recipe.
- **kind's start time is paid per worktree session.** Recipes should keep a cluster up across test runs and reset namespaces, not recreate the cluster.
- **CI runs both tiers as jobs outside the read-only gate.** The kwok job is fast enough to run on every pull request. The kind job is 13's smoke job, which per 13 does not block the aggregate `check` until it has been stable.

## What would reopen this

- **kind's start time becomes the bottleneck.** If the e2e loop is dominated by cluster creation, k3d (9.9 s versus 24.9 s) is re-measured against the same criteria.
- **kwokctl gains a bind address, or loses its port race.** Either one simplifies the recipe. It is not a new decision.
- **kwok stops honouring `pod-deletion-cost`, or CA's kwok provider breaks.** `deletion-cost.sh` and `ca-kwok.sh` rerun on every kwok or CA pin move.
- **The cluster minor moves.** A new minor needs a kind node image, a kwok cluster image, a CA release, and kubectl within skew, as 0003 required for 1.35.
- **A Gleam envtest binding appears,** one that starts the apiserver and the controller-manager. It would be weighed against kwok.
- **Native linux/amd64 disagrees.** If 13's CI kind job, or the first kwok job, behaves differently from the Mac results, this record is reopened.

## Related pages

- [Project overview](../OVERVIEW.md), §6 and §9.16
- [Decision 0003: Tool manager](0003-tool-manager.md), for the cluster minor and the tool sources
- [Evidence for this record](../../.scratch/bootstrap/evidence/10/README.md)
- CA's kwok provider [README at `cluster-autoscaler-1.35.2`](https://github.com/kubernetes/autoscaler/blob/cluster-autoscaler-1.35.2/cluster-autoscaler/cloudprovider/kwok/README.md)
