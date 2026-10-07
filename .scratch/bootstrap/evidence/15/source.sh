#!/bin/sh
# Ticket 15 evidence: the CA source behind each observed behaviour, kept
# checkable. Every file decision 0008 cites is fetched at the pinned tag and its
# sha256 printed, and each cited excerpt is asserted to be on the cited line
# range. Then:
#   - whether each file differs at cluster-autoscaler-1.36.1, the newest 1.36
#     tag (GKE's Rapid default minor), and if so where each excerpt moved
#   - whether safe-to-evict "on-completion" (autoscaler PR #9355, DEFERRED §8)
#     is in 1.35.2, 1.36.0 or 1.36.1: is its merge commit an ancestor of the tag
# Needs gh (authenticated) and perl.
# Usage: sh source.sh <empty-work-dir>
set -eu
work=${1:?usage: source.sh <empty-work-dir>}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
tag=cluster-autoscaler-1.35.2
next=cluster-autoscaler-1.36.1
repo=kubernetes/autoscaler
sha() { if command -v sha256sum > /dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }
fetch() { # tag, path under cluster-autoscaler/; prints the local copy
  f=$work/$1/$2
  if [ ! -f "$f" ]; then
    mkdir -p "$(dirname "$f")"
    # Through temporary files, so a failed or empty fetch is never cached.
    gh api "repos/$repo/contents/cluster-autoscaler/$2?ref=$1" --jq .content > "$f.b64" &&
      base64 -d < "$f.b64" > "$f.tmp" && [ -s "$f.tmp" ] ||
      { echo "cannot fetch $2 at $1" >&2; exit 1; }
    mv "$f.tmp" "$f"; rm -f "$f.b64"
  fi
  printf '%s\n' "$f"
}
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
printf '%s is tag object %s, commit %s\n' "$tag" "$(gh api "repos/$repo/git/ref/tags/$tag" --jq .object.sha)" "$(gh api "repos/$repo/commits/$tag" --jq .sha)"
printf '%s is commit %s\n' "$next" "$(gh api "repos/$repo/commits/$next" --jq .sha)"

# path|first line|last line|fixed string that must be in that range|what it shows
citations='utils/drain/drain.go|144|147|PodSafeToEvictKey] == "true"|"true" is an exact string match
utils/drain/drain.go|149|153|PodSafeToEvictKey] == "false"|"false" is an exact string match; other values act as absent
utils/drain/drain.go|38|38|safe-to-evict-local-volumes|the local-volumes annotation key
utils/drain/drain.go|116|139|!isNonBlocking[volume.Name]|a local volume named in safe-to-evict-local-volumes does not block
utils/drain/drain.go|140|142|EmptyDir.Medium != apiv1.StorageMediumMemory|disk-backed emptyDir and hostPath are local storage
simulator/drainability/rules/rules.go|57|57|mirror.New()|rule order 1: mirror
simulator/drainability/rules/rules.go|62|62|daemonset.New()|rule order: daemonset
simulator/drainability/rules/rules.go|63|63|{rule: safetoevict.New()}|rule order: safetoevict ("true") before every blocking rule
simulator/drainability/rules/rules.go|64|64|terminal.New()|rule order: terminal
simulator/drainability/rules/rules.go|67|67|replicated.New(|rule order: replicated
simulator/drainability/rules/rules.go|68|68|system.New(|rule order: system
simulator/drainability/rules/rules.go|69|69|notsafetoevict.New()|rule order: notsafetoevict ("false")
simulator/drainability/rules/rules.go|70|70|localstorage.New()|rule order: localstorage, skipped if --skip-nodes-with-local-storage=false
simulator/drainability/rules/rules.go|71|71|pdbrule.New()|rule order: pdb, last
simulator/drainability/rules/rules.go|93|111|if status.Outcome != drainability.UndefinedOutcome|the first rule with a decision wins
simulator/drainability/rules/safetoevict/rule.go|40|44|return drainability.NewDrainableStatus()|"true" is a decision: drainable, so later rules (PDB included) are not asked
simulator/drainability/rules/notsafetoevict/rule.go|42|46|pod annotated as not safe to evict present|"false" blocks, with this message
simulator/drainability/rules/localstorage/rule.go|42|46|pod with local storage present|local storage blocks, with this message
simulator/drain.go|53|69|case drainability.BlockDrain:|GetPodsToMove stops at the first blocking pod
simulator/cluster.go|145|152|cannot be removed: %v|log line: "Node <n> cannot be removed: <reason>"
simulator/cluster.go|155|160|is not suitable for removal|log line when pods have no place to go (the setup trap)
core/scaledown/eligibility/eligibility.go|163|163|is above the scale-down utilization threshold|log line when utilization is too high (the setup trap)
core/scaledown/unneeded/nodes.go|132|150|since: val.since|since is kept only for a node still in the removable list of this loop
core/scaledown/unneeded/nodes.go|132|150|n.byName = updated|the unneeded set is rebuilt every loop, so a node that drops out loses its since
core/scaledown/unneeded/nodes.go|153|153|is unneeded since|log line read by since_of
core/scaledown/planner/planner.go|277|277|UnremovableNodeRecheckTimeout|a blocked node is not re-simulated until the recheck timeout
core/scaledown/planner/planner.go|315|318|AddTimeout(unremovable, unremovableTimeout)|a blocked node is recorded with that timeout
core/scaledown/eligibility/eligibility.go|83|88|RecentlyUnremovable|until then it is skipped as recently unremovable
core/scaledown/eligibility/eligibility.go|104|104|ignoring %v nodes unremovable in the last|log line for each loop that skips such nodes
core/scaledown/planner/planner.go|322|324|will re-check them at %v|log line with the recheck time, read by recheck_of
core/scaledown/planner/planner.go|281|281|p.unremovableNodes.Update(|each loop first drops the expired timeouts
core/scaledown/unremovable/nodes.go|62|65|if ttl.After(timestamp) {|a timeout is kept only while it is still in the future
core/scaledown/unremovable/nodes.go|109|112|_, found := n.ttls[nodeName]|IsRecent reads only the timeout, not the annotation
core/scaledown/planner/planner.go|283|285|p.unremovableNodes.Add(n)|a skipped node is added back with no new timeout
core/scaledown/unremovable/nodes.go|77|79|n.reasons[node.Node.Name] = node|Add sets a reason only, so skipping does not extend the timeout
core/scaledown/unremovable/nodes.go|83|86|n.ttls[node.Node.Name] = timeout|AddTimeout sets it: a node blocked again on its recheck gets a new one
core/static_autoscaler.go|289|289|Starting main loop|log line that opens a loop, used to delimit loops
core/static_autoscaler.go|620|620|scaleDownPlanner.UpdateClusterState(|the loop plans scale-down here
core/static_autoscaler.go|661|661|Starting scale down")|"Starting scale down" is logged after planning, so it does not open a loop
core/scaledown/planner/planner.go|303|306|removable.IsRisky = true|a node whose pods exceed a PDB is marked risky
core/scaledown/planner/planner.go|152|183|needDrainRemovableNodes = sortByRisk(needDrainRemovableNodes)|risky nodes are only sorted last, not dropped
core/scaledown/planner/planner.go|438|449|return append(okNodes, riskyNodes...)|sortByRisk keeps every node
core/scaledown/actuation/actuator.go|155|164|a.taintNodesSync(drainToDelete)|actuation taints (and cordons) first, then drains asynchronously
core/scaledown/actuation/actuator.go|269|269|Scale-down: removing node %s|log line used as the removal time
core/scaledown/actuation/actuator.go|295|298|time.Sleep(nodeDeleteDelayAfterTaint)|then sleeps --node-delete-delay-after-taint
core/scaledown/actuation/actuator.go|300|300|a.createSnapshot(nodes)|then builds a fresh snapshot
core/scaledown/actuation/actuator.go|400|403|a.autoscalingCtx.AllPodLister().List()|from the current pod list
core/scaledown/actuation/actuator.go|333|339|simulator.GetPodsToMove(nodeInfo, a.deleteOptions, a.drainabilityRules|and re-runs the same drain rules: the one re-check
core/scaledown/actuation/actuator.go|333|339|"failed to get pods to move on node"|a blocked re-check aborts the deletion of that node
core/scaledown/actuation/delete_in_batch.go|194|210|"ScaleDownFailed"|the abort emits a ScaleDownFailed event
core/scaledown/actuation/delete_in_batch.go|194|210|taints.CleanToBeDeleted(node|and removes the taint (and the cordon)
core/scaledown/actuation/drain.go|44|44|DefaultEvictionRetryTime = 10 * time.Second|eviction is retried every 10 s
core/scaledown/actuation/drain.go|239|256|Pods(podToEvict.Namespace).Evict(context.TODO(), eviction)|the retry loop calls the Eviction API with the pod it started with, and reads no annotation
simulator/fake/pod.go|25|35|FakePodAnnotationValue = "fakepod"|"fake" pods are those annotated podtype=fakepod; kwok pods are not
cloudprovider/kwok/kwok_nodegroups.go|100|125|Nodes().Delete(context.Background()|the kwok provider deletes the Node object
cloudprovider/kwok/kwok_nodegroups.go|229|233|return &defaults, nil|no per-group options: only global flags apply
config/flags/flags.go|162|162|"unremovable-node-recheck-timeout", 5*time.Minute|default recheck timeout 5m
config/flags/flags.go|180|180|"cordon-node-before-terminating", true|default: cordon before terminating
config/flags/flags.go|200|200|"skip-nodes-with-local-storage", true|default: local storage blocks
config/flags/flags.go|204|204|"node-delete-delay-after-taint", 5*time.Second|default taint delay 5s
config/flags/flags.go|129|129|"max-pod-eviction-time", 2*time.Minute|default eviction retry budget 2m
config/flags/flags.go|76|76|"scale-down-delay-after-add", 10*time.Minute|default delay after add 10m
config/flags/flags.go|80|80|"scale-down-delay-after-delete", 0,|default delay after delete 0
config/const.go|46|46|DefaultScaleDownUnneededTime = 10 * time.Minute|default unneeded time 10m
config/const.go|54|54|DefaultScaleDownDelayAfterFailure = 3 * time.Minute|default delay after failure 3m
config/const.go|56|56|DefaultScanInterval = 10 * time.Second|default scan interval 10s'

# Fetch every file at both tags first, at the top level, so a failed fetch
# stops the run here instead of inside a $(...) below.
for t in "$tag" "$next"; do
  printf '%s\n' "$citations" | cut -d'|' -f1 | sort -u | while read -r p; do fetch "$t" "$p" > /dev/null; done
done

echo; echo "== files at $tag"
printf '%s\n' "$citations" | cut -d'|' -f1 | sort -u | while read -r p; do
  printf '%s  %s\n' "$(sha < "$(fetch "$tag" "$p")")" "$p"
done

echo; echo "== cited excerpts at $tag"
bad=0
while IFS='|' read -r p a b s what; do
  f=$(fetch "$tag" "$p")
  if sed -n "${a},${b}p" "$f" | grep -qF -- "$s"; then printf 'ok   %s#L%s-L%s  %s\n' "$p" "$a" "$b" "$what"
  else printf 'FAIL %s#L%s-L%s  not found: %s\n' "$p" "$a" "$b" "$s"; bad=$((bad + 1)); fi
done <<EOF
$citations
EOF
[ "$bad" -eq 0 ] || { echo "$bad excerpts not on their cited lines"; exit 1; }

echo; echo "== the same files at $next"
printf '%s\n' "$citations" | cut -d'|' -f1 | sort -u | while read -r p; do
  if cmp -s "$(fetch "$tag" "$p")" "$(fetch "$next" "$p")"; then printf 'same     %s\n' "$p"
  else printf 'changed  %s\n' "$p"; fi
done
echo "excerpts in changed files, at $next:"
while IFS='|' read -r p a b s what; do
  cmp -s "$(fetch "$tag" "$p")" "$(fetch "$next" "$p")" && continue
  at=$(grep -nF -- "$s" "$(fetch "$next" "$p")" | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
  if [ -n "$at" ]; then printf '  %-58s found at L%s\n' "$p#L$a-L$b" "$at"
  else printf '  %-58s GONE: %s\n' "$p#L$a-L$b" "$s"; fi
done <<EOF
$citations
EOF
for t in "$tag" "$next"; do
  printf 'drain rule order at %s: %s\n' "$t" "$(sed -n 's/^[[:space:]]*{rule: \([a-z]*\)\.New.*/\1/p' "$(fetch "$t" simulator/drainability/rules/rules.go)" | tr '\n' ' ')"
done

echo; echo '== safe-to-evict "on-completion" (autoscaler PR #9355)'
merge=$(gh api "repos/$repo/pulls/9355" --jq '.merge_commit_sha')
printf 'PR #9355 "%s", merged %s as %s\n' "$(gh api "repos/$repo/pulls/9355" --jq .title)" "$(gh api "repos/$repo/pulls/9355" --jq .merged_at)" "$merge"
for t in "$tag" cluster-autoscaler-1.36.0 "$next"; do
  # compare <tag>...<merge>: "behind" or "identical" means the tag contains it.
  st=$(gh api "repos/$repo/compare/$t...$merge" --jq .status)
  if gh api "repos/$repo/contents/cluster-autoscaler/simulator/drainability/rules/oncompletion/rule.go?ref=$t" > /dev/null 2>&1; then rule=present; else rule=absent; fi
  case $st in behind|identical) in=yes;; *) in=no;; esac
  printf '%-26s contains the merge: %-3s (compare: %s); rules/oncompletion/rule.go: %s\n' "$t" "$in" "$st" "$rule"
done
