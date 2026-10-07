#!/bin/sh
# Ticket 10 evidence: does Cluster Autoscaler's kwok cloud provider exist at
# the pinned version, and does it run? "Runs" means one observed scale-up: a
# pod that fits no node stays Pending until CA adds a node to a kwok nodegroup,
# and the pod is then scheduled there.
#
# 1. Read the provider's README at the pinned tag and print the prerequisites
#    it states, so the setup below follows the source rather than memory.
# 2. A kwokctl cluster (cluster.sh). Pods do not run in kwok, so CA cannot run
#    as a pod; it runs as a container from the pinned image on the cluster's
#    docker network, with kwokctl's in-network kubeconfig and
#    KWOK_PROVIDER_MODE=local (the README's "run CA locally" path).
# 3. kwok-provider-config and kwok-provider-templates ConfigMaps in
#    POD_NAMESPACE: one nodegroup "ng-a" (label kwok-nodegroup, 0 to 3 nodes,
#    2 CPU, 4Gi). The provider taints its nodes kwok-provider=true:NoSchedule
#    by default (README gotcha 1); the pod tolerates it.
# 4. A Deployment whose pod selects kwok-nodegroup=ng-a, which no node has.
# Needs docker and gh.
# Usage: sh ca-kwok.sh <tools-dir> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: ca-kwok.sh <tools-dir> <empty-work-dir>'
tools=$(cd "${1:?$usage}" && pwd); work=${2:?$usage}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
PATH=$tools/bin:$tools/.pixi/envs/cluster/bin:$PATH; export PATH
tag=cluster-autoscaler-1.35.2
ca_image=registry.k8s.io/autoscaling/cluster-autoscaler:v1.35.2@sha256:aac369dc283927a623deb1af54696efcc722ae79255aa07788422e495bab887d
n=$(sh "$here/name.sh" "$work" name)
KUBECONFIG=$(sh "$here/name.sh" "$work" kubeconfig); export KUBECONFIG
ca=$n-cluster-autoscaler
fail() { printf 'FAIL: %s\n' "$*"; docker logs "$ca" 2>&1 | tail -30 || true; kubectl get nodes,pods -o wide 2>&1 || true; exit 1; }
cleanup() {
  docker rm -f "$ca" > /dev/null 2>&1 || true
  sh "$here/cluster.sh" "$tools" kwokctl down "$work" > /dev/null 2>&1 || true
}
trap cleanup EXIT
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"

echo; echo "== 1. the kwok provider at $tag"
src=repos/kubernetes/autoscaler/contents/cluster-autoscaler/cloudprovider/kwok
gh api "$src?ref=$tag" --jq '.[] | .name' | tr '\n' ' '; echo
gh api "$src/README.md?ref=$tag" --jq .content | base64 -d > "$work/README.md"
printf 'README.md sha256 %s\n' "$(shasum -a 256 "$work/README.md" | cut -d' ' -f1)"
echo 'prerequisites it states:'
# shellcheck disable=SC2016  # the backticks are literal Markdown
grep -E 'Install `kwok` controller|Create `kwok-provider-(config|templates)` ConfigMap|Set `POD_NAMESPACE`|Set `--cloud-provider=kwok`|KWOK_PROVIDER_MODE=local|taints the template nodes|fromNodeLabelKey`/`fromNodeAnnotationKey` in the kwok provider config is actually present' \
  "$work/README.md" | sed 's/^ */  /' | cut -c1-160
[ "$(grep -c 'KWOK_PROVIDER_MODE=local' "$work/README.md")" -ge 1 ] || fail 'README no longer documents local mode'

echo; echo '== 2. kwokctl cluster'
sh "$here/cluster.sh" "$tools" kwokctl up "$work"
kubectl version | sed -n 's/^Server Version: /server: /p'
kubectl get nodes --no-headers

echo; echo '== 3. kwok provider ConfigMaps (namespace default = POD_NAMESPACE)'
kubectl apply -f - > /dev/null <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: kwok-provider-config, namespace: default}
data:
  config: |
    apiVersion: v1alpha1
    readNodesFrom: configmap
    nodegroups:
      fromNodeLabelKey: kwok-nodegroup
    configmap:
      name: kwok-provider-templates
---
apiVersion: v1
kind: ConfigMap
metadata: {name: kwok-provider-templates, namespace: default}
data:
  templates: |
    apiVersion: v1
    kind: List
    items:
    - apiVersion: v1
      kind: Node
      metadata:
        name: ng-a-template
        labels: {kwok-nodegroup: ng-a, kubernetes.io/os: linux, kubernetes.io/arch: amd64}
        annotations:
          cluster-autoscaler.kwok.nodegroup/min-count: "0"
          cluster-autoscaler.kwok.nodegroup/max-count: "3"
      status:
        allocatable: {cpu: "2", memory: 4Gi, pods: "110"}
        capacity: {cpu: "2", memory: 4Gi, pods: "110"}
EOF
echo 'applied: nodegroup ng-a, 0..3 nodes, 2 CPU / 4Gi, provider taint kept'

echo; echo "== 4. CA $tag as a container on the cluster's network"
docker pull -q "$ca_image" > /dev/null
cfg=$(sh "$here/name.sh" "$work" kwok-workdir)/clusters/$n
docker run -d --name "$ca" --network "kwok-$n" --user "$(id -u):$(id -g)" \
  -v "$cfg/kubeconfig:/kubeconfig:ro" -v "$cfg/pki:/etc/kubernetes/pki:ro" \
  -e KUBECONFIG=/kubeconfig -e POD_NAMESPACE=default -e KWOK_PROVIDER_MODE=local \
  "$ca_image" /cluster-autoscaler --cloud-provider=kwok --kubeconfig=/kubeconfig \
  --namespace=default --leader-elect=false --scan-interval=5s --v=4 --logtostderr > /dev/null
printf 'image: %s\n' "$ca_image"
i=0; until docker logs "$ca" 2>&1 | grep -q 'Starting main loop'; do
  [ "$(docker inspect -f '{{.State.Running}}' "$ca")" = true ] || fail 'CA exited'
  i=$((i + 1)); [ "$i" -lt 120 ] || fail 'CA never started its main loop'; sleep 0.5
done
docker logs "$ca" 2>&1 | grep -m1 -E 'Cluster Autoscaler [0-9.]+' | sed 's/^.*\] /ca: /' || true
docker logs "$ca" 2>&1 | grep -m3 -iE 'kwok' | sed 's/^.*\] /ca: /' | cut -c1-160 || true

echo; echo '== 5. a pod that fits no node'
t0=$(perl -MTime::HiRes=time -e 'printf "%.1f\n", time')
kubectl apply -f - > /dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: needs-ng-a}
spec:
  replicas: 1
  selector: {matchLabels: {app: needs-ng-a}}
  template:
    metadata: {labels: {app: needs-ng-a}}
    spec:
      nodeSelector: {kwok-nodegroup: ng-a}
      tolerations: [{key: kwok-provider, operator: Equal, value: "true", effect: NoSchedule}]
      containers:
        - name: pause
          image: "registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a"
          resources: {requests: {cpu: "1", memory: 1Gi}}
EOF
i=0; until [ "$(kubectl get pods -l app=needs-ng-a -o jsonpath='{.items[0].status.conditions[?(@.type=="PodScheduled")].reason}' 2> /dev/null)" = Unschedulable ]; do
  i=$((i + 1)); [ "$i" -lt 120 ] || fail 'pod never became Unschedulable'; sleep 0.5
done
echo 'pod is Pending, PodScheduled=False reason Unschedulable'

echo; echo '== 6. one scale-up'
i=0; until [ -n "$(kubectl get nodes -l kwok-nodegroup=ng-a -o name 2> /dev/null)" ]; do
  i=$((i + 1)); [ "$i" -lt 240 ] || fail 'CA added no node within 120s'; sleep 0.5
done
kubectl wait --for=condition=Ready pod -l app=needs-ng-a --timeout 120s > /dev/null || fail 'pod not Ready on the new node'
t=$(perl -e 'printf "%.1f\n", $ARGV[1] - $ARGV[0]' "$t0" "$(perl -MTime::HiRes=time -e 'printf "%.1f\n", time')")
node=$(kubectl get pods -l app=needs-ng-a -o jsonpath='{.items[0].spec.nodeName}')
kubectl get node "$node" -o custom-columns='NODE:.metadata.name,NODEGROUP:.metadata.annotations.cluster-autoscaler\.kwok\.nodegroup/name,PROVIDER-ID:.spec.providerID,KWOK:.metadata.annotations.kwok\.x-k8s\.io/node,TAINTS:.spec.taints[*].key'
[ "$(kubectl get node "$node" -o jsonpath='{.metadata.annotations.cluster-autoscaler\.kwok\.nodegroup/name}')" = ng-a ] || fail "$node is not in ng-a"
echo 'CA log:'
docker logs "$ca" 2>&1 | grep -E 'Final scale-up plan|Scale-up: setting group' | head -4 | sed 's/^.*\] /  /' | cut -c1-200
docker logs "$ca" 2>&1 | grep -qE 'Final scale-up plan|Scale-up: setting group' || fail 'no scale-up line in the CA log'
echo "ok   one scale-up: pod Pending -> CA added $node to ng-a -> pod Ready, ${t}s after the pod was created"
echo
echo "verdict: the kwok provider exists at $tag and scales up a kwokctl cluster, with CA as a container"
