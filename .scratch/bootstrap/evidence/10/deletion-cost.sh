#!/bin/sh
# Ticket 10 evidence: does the runner's kube-controller-manager honour
# controller.kubernetes.io/pod-deletion-cost when a ReplicaSet scales down?
# This is knarr's core mechanism (OVERVIEW §6).
#
# A Deployment runs 3 replicas, all Ready (the ReplicaSet ranks readiness
# before cost, so a not-yet-Ready pod would be deleted first and prove nothing).
#   Round 1: one pod costs 1000, the other two -1000. Scale to 1: the 1000 pod
#            must be the one left.
#   Round 2: scale back to 3, then reverse: the round-1 survivor, now the
#            oldest pod, costs -1000, one new pod 1000, the other -1000. Scale
#            to 1: the new 1000 pod must be left. Without costs the ReplicaSet
#            keeps the pod Ready longest, so this round also shows cost
#            overriding age.
# envtest is not a runner here: it has no kube-controller-manager, so no
# ReplicaSet controller ever acts on the scale.
# Usage: sh deletion-cost.sh <tools-dir> kwokctl|kind <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: deletion-cost.sh <tools-dir> kwokctl|kind <empty-work-dir>'
tools=$(cd "${1:?$usage}" && pwd); runner=${2:?$usage}; work=${3:?$usage}
case $runner in kwokctl|kind) ;; *) echo "$usage" >&2; exit 2;; esac
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
PATH=$tools/bin:$tools/.pixi/envs/cluster/bin:$PATH; export PATH
KUBECONFIG=$(sh "$here/name.sh" "$work" kubeconfig); export KUBECONFIG
fail() { printf 'FAIL: %s\n' "$*"; kubectl get pods -o wide 2>&1 || true; exit 1; }
cluster() { sh "$here/cluster.sh" "$tools" "$runner" "$1" "$work"; }
trap 'cluster down > /dev/null 2>&1 || true' EXIT

printf 'date: %s\nrunner: %s\n%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$runner" "$(kubectl version --client | head -1)"
cluster up
printf '%s\n' "$(kubectl version | sed -n 's/^Server Version: /Server Version: /p')"
kubectl get nodes -o custom-columns=NODE:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion --no-headers

kubectl apply -f - > /dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: victim}
spec:
  replicas: 3
  selector: {matchLabels: {app: victim}}
  template:
    metadata: {labels: {app: victim}}
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - {name: pause, image: "registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a"}
EOF

live() { # pods of the Deployment not being deleted, oldest first
  kubectl get pods -l app=victim --sort-by=.metadata.creationTimestamp \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}'
}
pods() { kubectl get pods -l app=victim --no-headers 2> /dev/null | wc -l | tr -d ' '; }
settle() { # replicas: wait until exactly that many pods, none terminating, all Ready
  kubectl scale deployment victim --replicas "$1" > /dev/null
  i=0; until [ "$(live | wc -l | tr -d ' ')" -eq "$1" ] && [ "$(pods)" -eq "$1" ]; do
    i=$((i + 1)); [ "$i" -lt 240 ] || fail "never reached $1 pods"; sleep 0.5
  done
  # shellcheck disable=SC2046  # one argument per pod name
  kubectl wait --for=condition=Ready --timeout=120s $(live | sed 's|^|pod/|') > /dev/null
}
cost() { kubectl annotate pod "$1" --overwrite "controller.kubernetes.io/pod-deletion-cost=$2" > /dev/null; }
show() { kubectl get pods -l app=victim --sort-by=.metadata.creationTimestamp --no-headers \
  -o custom-columns='POD:.metadata.name,COST:.metadata.annotations.controller\.kubernetes\.io/pod-deletion-cost,READY:.status.conditions[?(@.type=="Ready")].status,CREATED:.metadata.creationTimestamp' | sed 's/^/    /'; }
round() { # label, the pod that must survive
  printf '  before scale to 1:\n'; show
  settle 1
  left=$(live)
  printf '  after:  %s\n' "$left"
  [ "$left" = "$2" ] || fail "$1: expected $2 to survive, $left survived"
  printf 'ok   %s: the cost-1000 pod is the only survivor\n' "$1"
}

settle 3
# shellcheck disable=SC2046  # pod names never contain spaces
set -- $(live)
echo; echo '== round 1: one pod at 1000, two at -1000, scale 3 -> 1'
cost "$1" 1000; cost "$2" -1000; cost "$3" -1000
round 'round 1' "$1"
first=$1

echo; echo '== round 2 (reversed): the survivor, now oldest, at -1000; a new pod at 1000'
settle 3
# shellcheck disable=SC2046  # pod names never contain spaces
set -- $(live)
[ "$1" = "$first" ] || fail "expected $first to be the oldest pod"
cost "$1" -1000; cost "$2" 1000; cost "$3" -1000
round 'round 2' "$2"

echo; echo "verdict: $runner's ReplicaSet scale-down honours pod-deletion-cost"
