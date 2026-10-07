# Ticket 15 evidence

Evidence for [Decision 0008: safe-to-evict on upstream Cluster Autoscaler](../../../../docs/decisions/0008-safe-to-evict-on-upstream-ca.md). Gathered on 2026-10-07 on an Apple M5 Pro (Darwin arm64) with pixi 0.81.0 and OrbStack 2.2.3, whose Docker engine is 29.4 (linux/arm64). Every experiment runs upstream Cluster Autoscaler (CA) `cluster-autoscaler-1.35.2`, from the digest pinned in 0003, with its kwok cloud provider on a kwokctl cluster, as set up in [ticket 10's ca-kwok.sh](../10/ca-kwok.sh). This is upstream CA, not GKE's: see 0008's "Versions and GKE".

Each script exits non-zero on an unexpected result, and each `.txt` file is the transcript of the script with the same name. Every script writes only to the work directory it is given, apart from the Docker objects it creates and deletes.

## Rerun everything

```sh
sh .scratch/bootstrap/evidence/15/run-all.sh "$(mktemp -d)"
```

This needs network, pixi 0.81.0, curl, perl, openssl, an authenticated `gh` and Docker. It fetches the tools afresh with [10's fetch.sh](../10/fetch.sh), into `<root>/tools`, with its output in `<root>/fetch.log` rather than a transcript here. The run took 17 minutes here, with pixi's package cache warm, and rewrites every transcript here. It stops at the first script that fails. At the end it checks that the run left no kwok or CA container; another worktree's clusters do not count.

setup-envtest leaves its asset directory read-only, so remove a work root with `chmod -R u+w <root> && rm -rf <root>`.

## Scripts

| Script | Transcript | What it shows |
| --- | --- | --- |
| [lib.sh](lib.sh) | (sourced by the experiments) | One setup for every experiment: 10's kwokctl cluster and kwok provider ConfigMaps (one node group `ng-a`, 0 to 3 nodes, 2 CPU / 4Gi), a fresh CA container per leg with the flags below echoed into the transcript, the setup trap's way round (below), waits, and the log readers |
| [lib_test.sh](lib_test.sh) | [lib_test.txt](lib_test.txt) | The pure helpers the verdicts rest on, built test-first on log lines copied from a CA 1.35.2 run: `since_of` (a node's latest `is unneeded since`), `recheck_of` (CA's `will re-check them at`), `timer_verdict` (kept, reset or unclear) and `klog_epoch` |
| [source.sh](source.sh) `<dir>` | [source.txt](source.txt) | Each CA file 0008 cites, fetched at `cluster-autoscaler-1.35.2` with its sha256, and every cited excerpt asserted on its cited line range. Then which files differ at 1.36.1 and where each excerpt moved, the drain rule order at both tags, and which tags contain `safe-to-evict: "on-completion"` (autoscaler PR #9355) |
| [exp1-false-blocks.sh](exp1-false-blocks.sh) `<tools> <dir>` | [exp1-false-blocks.txt](exp1-false-blocks.txt) | `"false"` keeps an otherwise removable node: CA logs `cannot be removed: pod annotated as not safe to evict present`, and the node gets no soft or hard taint in 4 times the unneeded time. Control: with no annotation the node is removed |
| [exp2-recheck.sh](exp2-recheck.sh) `<tools> <dir>` | [exp2-recheck.txt](exp2-recheck.txt) | (b) a flip to `"false"` inside the taint delay: CA's one re-check after the delay aborts the deletion, emits `ScaleDownFailed`, and removes the taint and cordon. (c) a flip during eviction retries: not re-read. A `"true"` pod under a PDB with `maxUnavailable: 0` still gets its node tainted, and once the PDB is gone the next retry evicts it although it is now `"false"` |
| [exp3-timer.sh](exp3-timer.sh) `<tools> <dir>` | [exp3-timer.txt](exp3-timer.txt) | The per-node unneeded timer: absent → `"true"` and `"true"` → absent keep it; absent → `"false"` → absent drops the node, which comes back only at CA's recheck time, with a new timer |
| [exp4-local-storage.sh](exp4-local-storage.sh) `<tools> <dir>` | [exp4-local-storage.txt](exp4-local-storage.txt) | A disk-backed emptyDir with no annotation blocks (`pod with local storage present`); `"true"` or `safe-to-evict-local-volumes` naming the volume unblocks |
| [run-all.sh](run-all.sh) `<root>` | | All of the above, in order, then the leftover check |

`<tools>` is the directory 10's `fetch.sh` was given.

## CA flags

Every flag that differs from the upstream default, as `lib.sh` sets it. Each transcript prints the flags of each CA it starts. The defaults are cited in `source.txt` (`config/flags/flags.go`, `config/const.go`).

| Flag | Value here | Upstream default |
| --- | --- | --- |
| `--scan-interval` | 5s | 10s |
| `--scale-down-unneeded-time` | 40s | 10m |
| `--scale-down-delay-after-add` | 0s | 10m |
| `--scale-down-delay-after-delete` | 0s | 0s |
| `--scale-down-delay-after-failure` | 0s | 3m |
| `--unremovable-node-recheck-timeout` | 15s | 5m |
| `--node-delete-delay-after-taint` | 5s; 30s in exp2 (b) | 5s |
| `--max-pod-eviction-time` | 2m; 60s in exp2 (c) | 2m |

Also `--v=4` (the log lines read here are at V4 or below), `--write-status-configmap=true`, `--namespace=default`, `--leader-elect=false` and `--cloud-provider=kwok`. `--skip-nodes-with-local-storage` keeps its default, `true`.

## Notes

- **The setup trap.** A node is only removable if it is under the utilization threshold and its pod has somewhere to go. 10's `nodeSelector` on `ng-a` leaves the pod nowhere to go, and a 1-CPU request on a 2-CPU node sits exactly at the 0.5 threshold, not below it. So `place_on_new_node` cordons kwokctl's own node, creates a one-replica Deployment (100m / 128Mi, the provider toleration, no `nodeSelector`), lets CA scale `ng-a` from 0 to 1 for it, and uncordons. kwokctl's node is then where the pod can move, and it is in no node group, so CA never removes it. Every experiment fails if CA kept the node for another reason (`is not suitable for removal`, or `unremovable:`).
- **One clock.** `since`, the removal time and the loop times are all read from CA's own log, on the container's clock: klog's line prefix and the `is unneeded since` and `will re-check them at` values. The host clock is never compared with them. A flip is timed by the first loop that starts after it, delimited by `Starting main loop`. `Starting scale down` is logged after the loop's planning, so it cannot delimit loops (`static_autoscaler.go`, in `source.txt`).
- **Eviction counts.** The 201 and 429 counts in exp2 (c) are the apiserver's own `apiserver_request_total` for the `eviction` subresource, read from `/metrics`, not CA's log.
- **The provider deletes its nodes when CA stops.** The kwok provider removes the nodes it made when CA shuts down, so each leg records what it needs before `ca_stop`, which also deletes any `ng-a` node left behind.
- **Leg C's blackout.** The flip back to absent is made as soon as CA logs the block, so CA sees it two loops before its recheck time. The transcript shows each of those loops still skipping the node (`ignoring 1 nodes unremovable in the last 15s`), and the node coming back on the first loop at the recheck time CA logged, not when the annotation went. A node is re-simulated only when its timeout runs out, and a node blocked again then gets a new one (`unremovable/nodes.go`, `planner.go`, in `source.txt`). So with F the time spent `"false"` and R the recheck timeout, the node is out of the unneeded set for between max(F, R) and F + R, plus up to one scan interval, and then needs a full unneeded time. The run here covers F < R; F > R follows from the timeout being set again on each blocked recheck.
