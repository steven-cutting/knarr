# Ticket 10 evidence

Evidence for [Decision 0007: Local cluster and test tiers](../../../../docs/decisions/0007-local-cluster.md). Gathered on 2026-10-07 on an Apple M5 Pro (Darwin arm64) with pixi 0.81.0 and OrbStack 2.2.3, whose Docker engine is 29.4 (linux/arm64). Every timing here is a Mac number on a warm image cache. CI runners are linux/amd64 and will differ.

Each script exits non-zero on an unexpected result, and each `.txt` file is the transcript of the script with the same name. `deletion-cost.sh` has one transcript per runner. Every script writes only to the work directory it is given, apart from the Docker objects it creates and deletes, and OrbStack's `k8s.enable`, which `orbstack.sh` restores to `false`.

## Rerun everything

```sh
sh .scratch/bootstrap/evidence/10/run-all.sh "$(mktemp -d)"
```

This needs network, pixi 0.81.0, curl, perl, openssl, an authenticated `gh` and Docker. `orbstack.sh` needs OrbStack, and it turns OrbStack's Kubernetes on and then off. The run takes about 15 minutes and rewrites every transcript here. It stops at the first script that fails. At the end it checks that no kind, k3d or kwok container is left and that `k8s.enable` is `false`.

setup-envtest leaves its asset directory read-only, so remove a work root with `chmod -R u+w <root> && rm -rf <root>`.

## Scripts

| Script | Transcript | What it shows |
| --- | --- | --- |
| [fetch.sh](fetch.sh) `<dir>` | [fetch.txt](fetch.txt) | 0003's `cluster` environment, locked and installed from [01's manifest](../01/pixi.toml.proposed) (kind 0.33.0, kubectl 1.34.3, helm, shellcheck; 836 MB). kwok, kwokctl, k3d and setup-envtest are downloaded and kept only if they match the sha256 pin lines copied from [01's tools.txt](../01/tools.txt), and a tampered copy is refused. setup-envtest then installs the envtest 1.35.0 assets (etcd and kube-apiserver) |
| [name.sh](name.sh) | [name_test.txt](name_test.txt) from [name_test.sh](name_test.sh) | The per-worktree naming seam, built test-first: `<basename>-<8 hex>`, at most 32 characters (k3d's limit), DNS-1123 characters, and a hash of the lower-cased physical path, so a symlink or another letter case names the same cluster. State lives under `<worktree>/.cluster/` |
| [cluster.sh](cluster.sh) `<tools> <runner> up\|down\|load <worktree>` | (used by the scripts below) | One cluster per worktree for kind, k3d, kwokctl and envtest. It is the draft of 13's `cluster-up`, `cluster-down` and `image-load` recipes |
| [pins.sh](pins.sh) `<tools>` | [pins.txt](pins.txt) | Registry digests, and linux/amd64 and linux/arm64 platforms, for the kind node image (matched against the kind v0.33.0 release notes), kwok's cluster and component images, k3s, k3d-tools, pause, and CA 1.35.2 (matched against 0003) |
| [deletion-cost.sh](deletion-cost.sh) `<tools> kwokctl\|kind <dir>` | [deletion-cost-kwokctl.txt](deletion-cost-kwokctl.txt), [deletion-cost-kind.txt](deletion-cost-kind.txt) | A ReplicaSet scale-down from 3 to 1 keeps the pod with `pod-deletion-cost` 1000. Reversing the costs then removes the oldest pod, which shows that cost overrides age |
| [timing.sh](timing.sh) `<tools> <dir>` | [timing.txt](timing.txt) | Create-to-ready, image load (a 256 MB stand-in) and delete for kind, k3d, kwokctl and envtest. Three runs each, with the median |
| [worktree.sh](worktree.sh) `<tools> <dir>` | [worktree.txt](worktree.txt) | Three worktrees per runner, created concurrently: two that share a basename and one with a name at the 32-character cap. Each gets its own port, each kubeconfig reaches only its own cluster, loads go into all three, and nothing is left after delete. `~/.kube/config`, `~/.kwok` and the k3d config dirs are unchanged. A control shows kwokctl's default port colliding |
| [orbstack.sh](orbstack.sh) `<tools> <dir>` | [orbstack.txt](orbstack.txt) | OrbStack's Kubernetes: start-to-ready time, a local image used with no load step, pod-IP and ClusterIP reach from the Mac, and one fixed cluster per machine. `k8s.enable` is restored to `false` by a trap |
| [ca-kwok.sh](ca-kwok.sh) `<tools> <dir>` | [ca-kwok.txt](ca-kwok.txt) | CA's kwok provider README at `cluster-autoscaler-1.35.2`, followed to the letter: CA 1.35.2 runs as a container on a kwokctl cluster's network and makes one scale-up for a pending pod |
| [run-all.sh](run-all.sh) `<root>` | | All of the above, in order, then the leftover check |

`<tools>` is the directory `fetch.sh` was given.

## Notes

- **OrbStack's starting state.** When this work began, `k8s.enable` was already `true`, on an empty cluster that someone had started a few minutes earlier. The first run of `orbstack.sh` recorded that and turned it off. The committed transcript, from a later run, finds `false`. The script always leaves `false`, as agreed for this spike.
- **No git worktrees.** The worktrees in `worktree.sh` are plain directories, because a `git worktree add` in the shared repository would disturb other live sessions. `name.sh` only needs a directory path.
- **envtest is a stand-in.** controller-runtime's envtest is a Go library. `cluster.sh` starts the same two binaries, etcd and kube-apiserver from setup-envtest's 1.35.0 assets, with a static token and `insecure-skip-tls-verify`, to measure what the library would cost. 1.35.0 is setup-envtest's newest 1.35 build. The apiserver is 1.35.5 elsewhere.
