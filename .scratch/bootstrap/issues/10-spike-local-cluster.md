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

**Status:** done. See [Decision 0007](../../../docs/decisions/0007-local-cluster.md) and its [evidence](../evidence/10/README.md).

- [x] kind, k3d, OrbStack, kwok and envtest are compared on four criteria:
  - real kube-controller-manager behaviour
  - the same runner locally and in CI
  - speed: create-to-ready time and image-load time, measured
  - fitness for many concurrent worktrees
- [x] Worktree fitness is shown, not asserted. Two worktrees run their own cluster or namespace at once without collision. The ticket covers naming derived from the worktree, a per-worktree `KUBECONFIG`, no fixed host ports, and image loading.
- [x] kwok is shown to honour `pod-deletion-cost` in ReplicaSet scale-down, or the gap is recorded.
- [x] The ticket records whether Cluster Autoscaler's kwok cloud provider exists and runs, and hands the answer to 15.
- [x] The kind node image and the kwok version are pinned. Tool sources follow 01.
- [x] The TestContainers, respx-equivalent and inline-snapshot-equivalent verdicts are recorded with reasons.
- [x] A tier table (unit / kwok / kind / GKE) says what each tier proves and where it runs.
- [x] A decision record is written. Follow-ups are drafted, including the cluster recipes 13 will add.

## Hand-back notes

These are corrections to the premise above, found while gathering the evidence on 2026-10-07:

- envtest is not a tier. kwok gives the "envtest equivalent or substitute" that OVERVIEW §9.16 asks for, with a real kube-controller-manager, about 1 s slower to start. envtest has none, and it is a Go library.
- OrbStack's apiserver is on a fixed port, 26443, with one cluster per machine. It fails the worktree criterion outright, and is not just "optional".
- kwokctl's default apiserver port is not random. It counts down from 32766, so concurrent creates collide.
- The Cluster Autoscaler kwok provider exists at 1.35.2 and works without patches.

### Follow-ups for 13

- Port [`name.sh`](../evidence/10/name.sh) and [`name_test.sh`](../evidence/10/name_test.sh) into the repository, for example as `scripts/cluster-name.sh` with its test in `just check`. Keep the behaviour: `<basename>-<8 hex>`, at most 32 characters, a hash of the lower-cased physical path, and the path fields under `<worktree>/.cluster/`. Gitignore `.cluster/` before the first `cluster-up`, because the kubeconfig holds an admin client key. The repository has no `.gitignore` yet (03 creates one).
- Add these `tools.txt` lines, copied from 0003 ([tools.txt](../evidence/01/tools.txt)). Do not add k3d or setup-envtest.

  ```text
  kwok 0.8.0 linux-64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwok-linux-amd64 f5a4385a2ae1b9dd7f8acae18e002a75c0ebba124ae9d7259aa8dadb50711f46 -
  kwok 0.8.0 osx-arm64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwok-darwin-arm64 69a064ec98d37844d9d742b5b28ff57825659a983ccc3e208daa6948b94d64ba -
  kwokctl 0.8.0 linux-64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwokctl-linux-amd64 d5743166c657283d6e827c7c4c20cacfd9009fd94830f06718ca7b2c7099461f -
  kwokctl 0.8.0 osx-arm64 https://github.com/kubernetes-sigs/kwok/releases/download/v0.8.0/kwokctl-darwin-arm64 9323a59adb9c27854bd2a76652ad00258bcbb68acc40aba0dc21e362b67b7d6a -
  ```

- Draft recipes. They follow [`cluster.sh`](../evidence/10/cluster.sh), which was run for kind and kwokctl. The Justfile's `PATH` export from 0003 supplies `kind`, `kubectl`, `kustomize` and `kwokctl`. Each recipe checks for the `cluster` environment first, as 0003 requires.

  ```just
  # Per-worktree local cluster (decision 0007). KNARR_CLUSTER=kind (default) or kwok.
  runner := env("KNARR_CLUSTER", "kind")
  cluster := `sh scripts/cluster-name.sh . name`
  kind_node := "kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0"
  export KUBECONFIG := justfile_directory() / ".cluster/kubeconfig"
  export KWOK_WORKDIR := justfile_directory() / ".cluster/kwok"

  cluster-up:
      #!/bin/sh
      set -eu
      mkdir -p .cluster
      case {{runner}} in
        kind) kind create cluster --name {{cluster}} --image {{kind_node}} --kubeconfig "$KUBECONFIG" --wait 180s;;
        kwok)
          # kwokctl's default port collides between worktrees; take one the OS says is
          # free. That narrows the race without closing it: on a bind failure, rerun.
          port=$(perl -MIO::Socket::INET -e 'print IO::Socket::INET->new(Listen=>1,LocalAddr=>"127.0.0.1",LocalPort=>0)->sockport')
          KWOK_KUBE_VERSION=v1.35.5 kwokctl create cluster --name {{cluster}} --runtime docker \
            --kubeconfig "$KUBECONFIG" --kube-apiserver-port "$port" --wait 180s
          kwokctl scale node --name {{cluster}} --replicas 1;;
        *) echo "KNARR_CLUSTER must be kind or kwok" >&2; exit 2;;
      esac
      # kubectl wait --all fails at once while no node exists, so wait for one first.
      i=0; until [ -n "$(kubectl get nodes -o name 2>/dev/null)" ]; do
        i=$((i + 1)); [ "$i" -lt 360 ] || { echo "no node registered" >&2; exit 1; }; sleep 0.5; done
      kubectl wait --for=condition=Ready node --all --timeout=180s
      i=0; until kubectl get serviceaccount default >/dev/null 2>&1; do
        i=$((i + 1)); [ "$i" -lt 120 ] || { echo "no default ServiceAccount" >&2; exit 1; }; sleep 0.5; done

  cluster-down:
      #!/bin/sh
      set -eu
      case {{runner}} in
        kind) kind delete cluster --name {{cluster}} --kubeconfig "$KUBECONFIG";;
        kwok) kwokctl delete cluster --name {{cluster}} --kubeconfig "$KUBECONFIG";;
      esac
      rm -rf .cluster

  # kwok pods never run a container, so there is nothing to load.
  image-load image:
      if [ {{runner}} = kind ]; then kind load docker-image {{image}} --name {{cluster}}; fi

  deploy image: (image-load image)
      kustomize build deploy/local | kubectl apply -f -
      kubectl set image deployment/knarr knarr={{image}}
      kubectl rollout status deployment/knarr --timeout 120s

  # kind only: the endpoints answer from inside the pod's network.
  smoke:
      #!/bin/sh
      set -eu
      kubectl port-forward deployment/knarr 18080:8080 >/dev/null & pf=$!
      trap 'kill $pf' EXIT
      i=0; until curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:18080/healthz 2>/dev/null; do
        i=$((i + 1)); [ "$i" -lt 60 ] || { echo "port-forward never answered" >&2; exit 1; }; sleep 0.5; done
      for p in healthz readyz metrics; do curl -fsS --max-time 5 "http://127.0.0.1:18080/$p" >/dev/null; echo "ok /$p"; done
  ```

  These are untested as a Justfile: the `deploy` overlay path, the container port and the image tag are 13's choice. The fixed port 18080 is local to the recipe's own `port-forward`, and two worktrees running `smoke` at once would collide on it. 13 picks a free port the same way `cluster-up` does. Pods must use `imagePullPolicy: Never` or `IfNotPresent` with a non-`latest` tag, so a loaded image is used.
- Pass kwokctl's component images by digest with `--kube-apiserver-image` and its siblings, using the digests in [pins.txt](../evidence/10/pins.txt). That path was not exercised here.
- Keep a cluster up across test runs and reset namespaces. Do not recreate the cluster, because kind takes about 25 s to start.

### Follow-ups for 15

- The kwok provider exists at `cluster-autoscaler-1.35.2` and makes one scale-up. Use [`ca-kwok.sh`](../evidence/10/ca-kwok.sh) as the starting setup:
  - a kwokctl cluster at `KWOK_KUBE_VERSION=v1.35.5`, from the recipe above. Its kwok controller runs with `--manage-all-nodes=true`, so it makes CA's nodes Ready.
  - two ConfigMaps in `POD_NAMESPACE` (`default`). `kwok-provider-config` sets `readNodesFrom: configmap`, `nodegroups.fromNodeLabelKey: kwok-nodegroup` and `configmap.name: kwok-provider-templates`. `kwok-provider-templates` has key `templates`, which holds a `List` of template Nodes, each labelled `kwok-nodegroup: <group>` and sized with the `cluster-autoscaler.kwok.nodegroup/min-count` and `max-count` annotations (defaults 0 and 200).
  - CA as a container: `docker run --network kwok-<name> --user <uid>:<gid>`, with `<kwok-workdir>/clusters/<name>/kubeconfig` mounted at `/kubeconfig` and its `pki/` at `/etc/kubernetes/pki`, and `-e KUBECONFIG=/kubeconfig -e POD_NAMESPACE=default -e KWOK_PROVIDER_MODE=local`, running the pinned image `/cluster-autoscaler --cloud-provider=kwok --kubeconfig=/kubeconfig --namespace=default --leader-elect=false --scan-interval=5s`. In local mode the provider reads `KUBECONFIG`, while CA's core reads `--kubeconfig`, so both are needed.
  - CA's nodes carry the `kwok-provider=true:NoSchedule` taint unless `nodes.skipTaint: true` is set, so the workload tolerates it. A `nodeSelector` on the group label forces a scale-up even when kwokctl's own node has room.
- Scale-up took about 5 s with `--scan-interval=5s`. The experiments need `--scale-down-unneeded-time` and `--scale-down-delay-after-add` set short, and recorded.
- The provider's `Cleanup` deletes its nodes when CA shuts down. Read the node list before stopping CA.

### Follow-ups for 08

- The testing reference lists four tiers, with what each proves and where it runs: unit (08's toolkit, in `just check`), kwok, kind and GKE. It links to [0007's tier table](../../../docs/decisions/0007-local-cluster.md#tiers) rather than restating it.
- Its verdicts match 0007: TestContainers is skipped, sans-IO with `send` injected replaces respx (`http_server_mock` only where a socket is needed), and birdie replaces inline-snapshot.

### Follow-ups for 05 and 13: the CI cluster jobs

- 13 adds both jobs, and neither is in the aggregate `check` job's `needs`. The kind job stays out of the required checks until it has been stable for the period 13 states. The kwok job is fast enough to run on every pull request once it has tests to run.

  ```yaml
  cluster-smoke:            # and cluster-kwok, with KNARR_CLUSTER: kwok and its own test recipe
    runs-on: ubuntu-24.04   # Docker preinstalled; kind and kwokctl need nothing else
    timeout-minutes: 15
    env: {KNARR_CLUSTER: kind}
    steps:
      - uses: actions/checkout@<sha>
      - uses: prefix-dev/setup-pixi@<sha>   # 05's pin, pixi-version v0.81.0, locked: true
        with: {environments: cluster}
      - run: just initialize                # tools.txt, including the kwok lines
      - run: just cluster-up
      - run: just image-build && just deploy knarr:ci && just smoke
      - if: always()
        run: just cluster-down
  ```

- On a runner, `name.sh` names the cluster from the checkout path, for example `knarr-<hash>`, and `.cluster/` sits in the workspace, so the recipes need no CI branch.
- The first run of this job is the first linux/amd64 confirmation of 0007. Nothing here ran on linux/amd64.
