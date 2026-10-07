#!/bin/sh
# Ticket 15 evidence, experiment 2: does CA 1.35.2 re-check safe-to-evict
# between marking a node for removal and evicting its pods?
#
#   (a) a flip while the node is only unneeded: experiment 3, leg C
#   (b) a flip inside --node-delete-delay-after-taint (30 s here). Once the
#       node has the ToBeDeletedByClusterAutoscaler taint, the pod is annotated
#       "false". CA re-runs its drain rules on a fresh pod list after the delay,
#       so it should abort: "couldn't delete node ... failed to get pods to
#       move ... not safe to evict", a ScaleDownFailed event, the taint and
#       cordon removed, the pod not evicted and the node kept.
#       Control: the same with no flip, and the node is removed.
#   (c) a flip during eviction retries. The pod is "true", which skips the PDB
#       rule in simulation, and a PDB with maxUnavailable 0 makes the Eviction
#       API answer 429, so CA retries every 10 s for --max-pod-eviction-time
#       (60 s here). The pod is flipped to "false" between retries, then the
#       PDB is deleted. If CA does not re-read the annotation while retrying,
#       the next retry evicts the pod and the node is removed.
#       The apiserver's request counter for pods/eviction shows the 429s.
#
# Each leg gets a fresh CA container. Setup and flags: lib.sh and README.md.
# Needs docker.
# Usage: sh exp2-recheck.sh <tools-dir> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: exp2-recheck.sh <tools-dir> <empty-work-dir>'
# shellcheck source=lib.sh disable=SC1091  # the gate runs without -x
. "$here/lib.sh"
ca_init "${1:?$usage}" "${2:?$usage}"
ste='"cluster-autoscaler.kubernetes.io/safe-to-evict"'
ste_key=cluster-autoscaler.kubernetes.io/safe-to-evict
# evictions <code>: the apiserver's count of pods/eviction requests that
# returned <code>, 0 if none yet.
evictions() {
  kubectl get --raw /metrics | perl -ne 'if (/^apiserver_request_total\{.*code="'"$1"'".*subresource="eviction"/ && /(\S+)$/) { $s += $1 } END { print $s + 0, "\n" }'
}
node_state() { kubectl get node "$1" -o custom-columns='NODE:.metadata.name,UNSCHEDULABLE:.spec.unschedulable,TAINTS:.spec.taints[*].key'; }
# cleared <node>: true only when the node is read without error and has
# neither the deletion taint nor the cordon. A failed read is not cleared.
cleared() {
  cl=0; has_taint "$1" ToBeDeletedByClusterAutoscaler || cl=$?
  [ "$cl" -eq 1 ] || return 1
  cordon=$(kubectl get node "$1" -o jsonpath='{.spec.unschedulable}' --request-timeout=5s 2> /dev/null) || return 1
  [ -z "$cordon" ]
}

echo; echo '== cluster'
ca_cluster_up

echo; echo '== (a) a flip while the node is only unneeded: see exp3-timer.txt, leg C'

echo; echo '== (b) control: no flip, --node-delete-delay-after-taint=30s'
ca_start --node-delete-delay-after-taint=30s
node=$(place_on_new_node exp2-control '')
pod=$(pod_of exp2-control)
echo "pod $pod is on new node $node"
wait_taint "$node" ToBeDeletedByClusterAutoscaler 90 || fail "$node never tainted for deletion"
echo "$node has ToBeDeletedByClusterAutoscaler"
wait_pod_gone "$pod" 90 || fail "$pod not evicted"
wait_node_gone "$node" 60 || fail "$node not deleted"
show_log "Scale-down: removing node $node|Scale-down: waiting 30s|All pods removed from $node" 3
no_other_reason "$node"
echo "ok   (b) control: after the 30 s delay $pod was evicted and $node deleted"
ca_stop; kubectl delete deployment exp2-control --wait=true > /dev/null

echo; echo '== (b) case: flip to "false" inside the 30 s taint delay'
ca_start --node-delete-delay-after-taint=30s
node=$(place_on_new_node exp2-flip '')
pod=$(pod_of exp2-flip)
echo "pod $pod is on new node $node"
wait_taint "$node" ToBeDeletedByClusterAutoscaler 90 || fail "$node never tainted for deletion"
kubectl annotate pod "$pod" "$ste_key=false" > /dev/null
echo "$node has ToBeDeletedByClusterAutoscaler; $pod annotated \"false\" at once"
show_log "Scale-down: removing node $node|Scale-down: waiting 30s" 2
wait_log "couldn't delete node \"$node\"" 60 || fail 'CA did not abort the deletion'
show_log "couldn't delete node \"$node\"" 1
ca_log | grep "couldn't delete node \"$node\"" | grep -q 'failed to get pods to move' || fail 'abort was not from the pod re-check'
ca_log | grep "couldn't delete node \"$node\"" | grep -q "pod annotated as not safe to evict present: $pod" || fail 'abort did not name the annotation'
i=0; until [ -n "$(kubectl get events -A --field-selector "involvedObject.name=$node,reason=ScaleDownFailed" -o name 2> /dev/null)" ]; do
  i=$((i + 1)); [ "$i" -lt 40 ] || fail 'no ScaleDownFailed event'; sleep 0.5
done
kubectl get events -A --field-selector "involvedObject.name=$node,reason=ScaleDownFailed" -o custom-columns='TYPE:.type,REASON:.reason,OBJECT:.involvedObject.name,MESSAGE:.message' | cut -c1-220
i=0; until cleared "$node"; do
  rc=0; exists node "$node" || rc=$?
  [ "$rc" -ne 1 ] || fail "$node was removed"
  i=$((i + 1)); [ "$i" -lt 40 ] || fail 'taint or cordon not removed'; sleep 0.5
done
# One more recheck period: the node stays, now blocked in simulation.
wait_log "Node $node cannot be removed: pod annotated as not safe to evict present: $pod" 40 || fail 'node not blocked after the abort'
kubectl get node "$node" > /dev/null 2>&1 || fail "$node was removed"
[ "$(pod_of exp2-flip)" = "$pod" ] || fail "$pod was evicted"
node_state "$node"
no_other_reason "$node"
echo "ok   (b) case: CA re-checked after the taint delay, aborted, untainted and uncordoned $node; $pod not evicted"
ca_stop; kubectl delete deployment exp2-flip --wait=true > /dev/null

echo; echo '== (c) flip during eviction retries: "true", PDB maxUnavailable 0, --max-pod-eviction-time=60s'
ca_start --max-pod-eviction-time=60s
node=$(place_on_new_node exp2-retry "$ste: \"true\"")
pod=$(pod_of exp2-retry)
kubectl apply -f - > /dev/null <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: exp2-retry}
spec:
  maxUnavailable: 0
  selector: {matchLabels: {app: exp2-retry}}
EOF
echo "pod $pod (\"true\") is on new node $node; PDB exp2-retry maxUnavailable 0"
r0=$(evictions 429); e0=$(evictions 201)
wait_taint "$node" ToBeDeletedByClusterAutoscaler 90 || fail "$node never tainted for deletion"
echo "$node has ToBeDeletedByClusterAutoscaler (a risky node is sorted last, not skipped)"
i=0; until [ "$(evictions 429)" -gt "$r0" ]; do
  i=$((i + 1)); [ "$i" -lt 60 ] || fail 'no eviction was refused: kwok gave no retries'; sleep 0.5
done
r1=$(evictions 429)
kubectl annotate pod "$pod" "$ste_key=false" --overwrite > /dev/null
echo "eviction refused $((r1 - r0)) time(s) (429); $pod flipped to \"false\" while CA retries"
i=0; until [ "$(evictions 429)" -gt "$r1" ]; do
  i=$((i + 1)); [ "$i" -lt 30 ] || fail 'CA stopped retrying after the flip'; sleep 0.5
done
r2=$(evictions 429); e2=$(evictions 201)
kubectl delete pdb exp2-retry > /dev/null
echo "eviction refused again after the flip ($((r2 - r1)) more 429); PDB deleted"
wait_pod_gone "$pod" 40 || fail "$pod not evicted after the PDB was deleted"
[ "$(evictions 201)" -gt "$e2" ] || fail 'the pod went without an eviction'
wait_node_gone "$node" 60 || fail "$node not deleted"
show_log "Scale-down: removing node $node|All pods removed from $node" 2
! ca_log | grep -q "couldn't delete node \"$node\"" || fail 'CA aborted the deletion'
printf 'pods/eviction requests in (c): %s refused (429), %s accepted (201)\n' "$(($(evictions 429) - r0))" "$(($(evictions 201) - e0))"
echo "ok   (c) $pod, annotated \"false\" during retries, was evicted once the PDB allowed it; $node deleted"
ca_stop

echo
echo 'verdict: CA re-checks safe-to-evict once, after the taint delay and before the first eviction; once eviction starts it does not re-read the annotation'
