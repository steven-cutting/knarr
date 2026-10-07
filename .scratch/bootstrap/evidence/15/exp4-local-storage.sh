#!/bin/sh
# Ticket 15 evidence, experiment 4, for §9.9's "remove the annotation versus
# write "true"": a pod with a disk-backed emptyDir on an otherwise removable
# node, under CA 1.35.2's default --skip-nodes-with-local-storage=true.
#
#   absent                    CA logs "Node <n> cannot be removed: pod with
#                             local storage present: <pod>" and keeps the node
#                             past 2 x the unneeded time
#   "true"                    the node is removed
#   safe-to-evict-local-volumes: scratch (the emptyDir's name)
#                             the node is removed
#
# Each leg gets a fresh CA container. Setup and flags: lib.sh and README.md.
# Needs docker.
# Usage: sh exp4-local-storage.sh <tools-dir> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: exp4-local-storage.sh <tools-dir> <empty-work-dir>'
# shellcheck source=lib.sh disable=SC1091  # the gate runs without -x
. "$here/lib.sh"
ca_init "${1:?$usage}" "${2:?$usage}"

removed() { # app, annotations, label
  ca_start
  node=$(place_on_new_node "$1" "$2" emptydir)
  pod=$(pod_of "$1")
  echo "pod $pod (emptyDir scratch, $3) is on new node $node"
  wait_taint "$node" ToBeDeletedByClusterAutoscaler 90 || fail "$node never tainted for deletion"
  wait_pod_gone "$pod" 60 || fail "$pod not evicted"
  wait_node_gone "$node" 60 || fail "$node not deleted"
  show_log "Scale-down: removing node $node" 1
  ! ca_log | grep -q "Node $node cannot be removed" || fail "$node was blocked at some point"
  no_other_reason "$node"
  echo "ok   $3: $pod evicted, $node deleted"
  ca_stop; kubectl delete deployment "$1" --wait=true > /dev/null
}

echo; echo '== cluster'
ca_cluster_up

echo; echo '== no annotation'
ca_start
node=$(place_on_new_node exp4-absent '' emptydir)
pod=$(pod_of exp4-absent)
echo "pod $pod (emptyDir scratch, no annotation) is on new node $node"
wait_log "Node $node cannot be removed: pod with local storage present: $pod" 30 || fail 'no local-storage line'
show_log "Node $node cannot be removed" 1
t0=$(first_log_epoch "Node $node cannot be removed")
i=0; while [ "$(perl -e 'print int($ARGV[1] - $ARGV[0])' "$t0" "$(ca_now)")" -lt 80 ]; do
  ! has_taint "$node" ToBeDeletedByClusterAutoscaler || fail "$node tainted for deletion"
  i=$((i + 1)); [ "$i" -lt 200 ] || fail 'CA log stopped advancing'; sleep 0.5
done
kubectl get node "$node" > /dev/null 2>&1 || fail "$node was removed"
[ -z "$(ca_log | since_of "$node")" ] || fail "$node was listed as unneeded"
no_other_reason "$node"
echo "ok   no annotation: $node kept for 80 s (2 x the unneeded time), blocked by local storage"
ca_stop; kubectl delete deployment exp4-absent --wait=true > /dev/null

echo; echo '== safe-to-evict "true"'
removed exp4-true '"cluster-autoscaler.kubernetes.io/safe-to-evict": "true"' 'safe-to-evict "true"'

echo; echo '== safe-to-evict-local-volumes: scratch'
removed exp4-volumes '"cluster-autoscaler.kubernetes.io/safe-to-evict-local-volumes": "scratch"' 'safe-to-evict-local-volumes "scratch"'

echo
echo 'verdict: with the default --skip-nodes-with-local-storage, a disk-backed emptyDir blocks scale-down unless the pod has safe-to-evict "true" or names the volume in safe-to-evict-local-volumes; removing the annotation is not enough for such a pod'
