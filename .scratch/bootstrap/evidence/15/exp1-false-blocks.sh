#!/bin/sh
# Ticket 15 evidence, experiment 1: a pod annotated
# cluster-autoscaler.kubernetes.io/safe-to-evict: "false" on an otherwise
# removable node keeps CA 1.35.2 from removing the node.
#
#   control  no annotation: the node is unneeded, then tainted, drained and
#            deleted about 40 s (--scale-down-unneeded-time) later
#   case     "false": CA logs "Node <n> cannot be removed: pod annotated as not
#            safe to evict present: <pod>", the node never gets the
#            DeletionCandidateOfClusterAutoscaler soft taint or the
#            ToBeDeletedByClusterAutoscaler taint, and it is still there at 4
#            times the unneeded time
#
# Each leg gets a fresh CA container. Setup and flags: lib.sh and README.md.
# Needs docker.
# Usage: sh exp1-false-blocks.sh <tools-dir> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: exp1-false-blocks.sh <tools-dir> <empty-work-dir>'
# shellcheck source=lib.sh disable=SC1091  # the gate runs without -x
. "$here/lib.sh"
ca_init "${1:?$usage}" "${2:?$usage}"
ste='"cluster-autoscaler.kubernetes.io/safe-to-evict"'

echo; echo '== cluster'
ca_cluster_up

echo; echo '== control: no annotation'
ca_start
node=$(place_on_new_node exp1-control '')
pod=$(pod_of exp1-control)
echo "pod $pod is on new node $node; node-000000 is uncordoned"
wait_taint "$node" ToBeDeletedByClusterAutoscaler 90 || fail "$node never tainted for deletion"
since=$(ca_log | since_of "$node")
removal=$(first_log_epoch "Scale-down: removing node $node,")
show_log "$node is unneeded since" 1
show_log "Successfully added (DeletionCandidate|ToBeDeleted)ByClusterAutoscaler on node $node|Scale-down: removing node $node" 3
wait_pod_gone "$pod" 60 || fail "$pod not evicted"
wait_node_gone "$node" 60 || fail "$node not deleted"
no_other_reason "$node"
printf 'ok   control: unneeded since %s, tainted for deletion %.1f s later; %s evicted, %s deleted\n' \
  "$(ca_log | grep -m1 "$node is unneeded since" | sed 's/.* since \([0-9-]* [0-9:.]*\).*/\1/' | cut -c1-23)" \
  "$(perl -e 'print $ARGV[1] - $ARGV[0]' "$since" "$removal")" "$pod" "$node"
ca_stop; kubectl delete deployment exp1-control --wait=true > /dev/null

echo; echo '== case: safe-to-evict "false"'
ca_start
node=$(place_on_new_node exp1-false "$ste: \"false\"")
pod=$(pod_of exp1-false)
echo "pod $pod is on new node $node, annotated $(kubectl get pod "$pod" -o jsonpath='{.metadata.annotations.cluster-autoscaler\.kubernetes\.io/safe-to-evict}')"
wait_log "Node $node cannot be removed: pod annotated as not safe to evict present: $pod" 30 || fail 'no not-safe-to-evict line'
show_log "Node $node cannot be removed" 1
# 4 x 40 s, counted from the first loop that saw the node blocked.
t0=$(first_log_epoch "Node $node cannot be removed")
i=0; while [ "$(perl -e 'print int($ARGV[1] - $ARGV[0])' "$t0" "$(ca_now)")" -lt 160 ]; do
  for k in DeletionCandidateOfClusterAutoscaler ToBeDeletedByClusterAutoscaler; do
    ! has_taint "$node" "$k" || fail "$node got $k"
  done
  i=$((i + 1)); [ "$i" -lt 400 ] || fail 'CA log stopped advancing'; sleep 0.5
done
kubectl get node "$node" > /dev/null 2>&1 || fail "$node was removed"
[ "$(pod_of exp1-false)" = "$pod" ] || fail "$pod was evicted"
[ -z "$(ca_log | since_of "$node")" ] || fail "$node was listed as unneeded"
no_other_reason "$node"
blocked=$(ca_log | grep -c "Node $node cannot be removed: pod annotated as not safe to evict present") || true
printf 'CA log over 160 s: %s "cannot be removed" lines, %s "is unneeded since" lines, %s "removing node" lines for %s\n' \
  "$blocked" "$(ca_log | grep -c "$node is unneeded since" || true)" "$(ca_log | grep -c "removing node $node" || true)" "$node"
kubectl get node "$node" -o custom-columns='NODE:.metadata.name,UNSCHEDULABLE:.spec.unschedulable,TAINTS:.spec.taints[*].key'
echo "ok   case: $node kept for 160 s (4 x the unneeded time), never a deletion candidate, $pod not evicted"
ca_stop

echo
echo 'verdict: safe-to-evict "false" keeps CA from removing an otherwise removable node; with no annotation the same node is removed after the unneeded time'
