# Ticket 15 evidence: helpers sourced by every experiment, so all of them use
# one setup. Not run on its own. The caller sets `here` (this directory) and
# calls ca_init first.
#
#   ca_init <tools> <work>   PATH, cluster name, KUBECONFIG, cleanup trap
#   ca_cluster_up            10's kwokctl cluster plus 10's kwok provider
#                            ConfigMaps: one group ng-a, 0 to 3 nodes, 2 CPU / 4Gi
#   ca_start [--flag=v ...]  a fresh CA container from the pinned digest; each
#                            argument replaces the default flag of that name
#   ca_stop                  stop CA and delete any ng-a node left behind
#   place_on_new_node <app> <annotations> [emptydir]
#                            the setup trap's way round (README): the pod lands
#                            on a new ng-a node, and kwokctl's own node is the
#                            place it can move to. Prints the node name
#   exists, refute_taint,    below; an apiserver error is never read as "gone",
#   evictions, wait_* and    "no taint" or a count (stubbed in lib_test.sh)
#   log helpers
#   since_of <node>          CA log on stdin: the latest "is unneeded since"
#                            for <node>, as epoch seconds (pure; lib_test.sh)
#   timer_verdict <since0> <since1> <removal> <unneeded>
#                            kept, reset or unclear (pure; lib_test.sh)
#   recheck_of               CA log on stdin: the latest "will re-check them
#                            at", as epoch seconds (pure; lib_test.sh)
#
# Times come from one clock, the container's: klog's line prefix and the
# `since` values CA prints. The host clock is never compared with them.

# This file is sourced, so it has no shebang. shellcheck 0.11.0 misreads a
# function called in an `until` condition as defined later (SC2218); every
# function here is defined before its use.
# shellcheck shell=sh disable=SC2218
tag=cluster-autoscaler-1.35.2
ca_image=registry.k8s.io/autoscaling/cluster-autoscaler:v1.35.2@sha256:aac369dc283927a623deb1af54696efcc722ae79255aa07788422e495bab887d
pause_image=registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a
# shellcheck disable=SC2154  # the sourcing script sets here
ev10=$here/../10
# Every flag that differs from the upstream default is here, with the
# scale-down delays set even where they match it, so each transcript records
# them all. Defaults are in README.md.
ca_default_flags='--cloud-provider=kwok
--kubeconfig=/kubeconfig
--namespace=default
--leader-elect=false
--write-status-configmap=true
--v=4
--logtostderr
--scan-interval=5s
--scale-down-unneeded-time=40s
--scale-down-delay-after-add=0s
--scale-down-delay-after-delete=0s
--scale-down-delay-after-failure=0s
--unremovable-node-recheck-timeout=15s
--node-delete-delay-after-taint=5s
--max-pod-eviction-time=2m'

ca_init() { # tools-dir, empty-work-dir
  tools=$(cd "$1" && pwd); work=$2
  mkdir -p "$work"; work=$(cd "$work" && pwd)
  [ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
  PATH=$tools/bin:$tools/.pixi/envs/cluster/bin:$PATH; export PATH
  n=$(sh "$ev10/name.sh" "$work" name)
  KUBECONFIG=$(sh "$ev10/name.sh" "$work" kubeconfig); export KUBECONFIG
  ca=$n-ca
  trap ca_cleanup EXIT
  printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
}

# fail writes to stderr, so a helper whose output is captured with $(...)
# still reports why it failed; run-all.sh puts stderr in the transcript.
fail() {
  {
    printf 'FAIL: %s\n' "$*"
    echo '-- CA log tail'; docker logs "$ca" 2>&1 | tail -40 | cut -c1-240 || true
    echo '-- nodes and pods'; kubectl get nodes,pods -o wide 2>&1 || true
  } >&2
  exit 1
}
ca_cleanup() {
  docker rm -f "$ca" > /dev/null 2>&1 || true
  sh "$ev10/cluster.sh" "$tools" kwokctl down "$work" > /dev/null 2>&1 || true
}

ca_cluster_up() {
  sh "$ev10/cluster.sh" "$tools" kwokctl up "$work"
  kubectl version | sed -n 's/^Server Version: /server: /p'
  # kwokctl's node is where pods move to, so it must have room and no taint.
  kubectl get node node-000000 -o custom-columns='NODE:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory,TAINTS:.spec.taints[*].key'
  [ -z "$(kubectl get node node-000000 -o jsonpath='{.spec.taints}')" ] || fail 'node-000000 is tainted'
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
  echo 'kwok provider ConfigMaps: nodegroup ng-a, 0..3 nodes, 2 CPU / 4Gi (as in 10)'
  docker pull -q "$ca_image" > /dev/null
}

# shellcheck disable=SC2120  # most callers want the defaults, and pass nothing
ca_start() { # [--flag=value ...]: each replaces the default of that name
  flags=$ca_default_flags
  for o in "$@"; do
    flags=$(printf '%s\n' "$flags" | grep -v -- "^${o%%=*}=")
    flags=$(printf '%s\n%s' "$flags" "$o")
  done
  docker rm -f "$ca" > /dev/null 2>&1 || true
  cfg=$(sh "$ev10/name.sh" "$work" kwok-workdir)/clusters/$n
  # shellcheck disable=SC2046  # one argument per line, none has a space
  docker run -d --name "$ca" --network "kwok-$n" --user "$(id -u):$(id -g)" \
    -v "$cfg/kubeconfig:/kubeconfig:ro" -v "$cfg/pki:/etc/kubernetes/pki:ro" \
    -e KUBECONFIG=/kubeconfig -e POD_NAMESPACE=default -e KWOK_PROVIDER_MODE=local \
    "$ca_image" /cluster-autoscaler $(printf '%s\n' "$flags") > /dev/null
  printf 'CA %s, flags: %s\n' "$tag" "$(printf '%s\n' "$flags" | grep -vE '^--(cloud-provider|kubeconfig|namespace|leader-elect|logtostderr)' | tr '\n' ' ')"
  i=0; until docker logs "$ca" 2>&1 | grep -q 'Starting main loop'; do
    [ "$(docker inspect -f '{{.State.Running}}' "$ca")" = true ] || fail 'CA exited'
    i=$((i + 1)); [ "$i" -lt 120 ] || fail 'CA never started its main loop'; sleep 0.5
  done
}
ca_stop() { # record nodes first: the provider deletes its nodes when CA stops
  docker stop -t 10 "$ca" > /dev/null 2>&1 || true
  docker rm -f "$ca" > /dev/null 2>&1 || true
  kubectl delete node -l kwok-nodegroup --wait=true > /dev/null 2>&1 || true
}
ca_log() { docker logs "$ca" 2>&1; }

# deploy <app> <annotations> [emptydir]: one replica, 100m / 128Mi, the provider
# toleration, no nodeSelector. <annotations> is a YAML flow map body, such as
# '"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"', or empty.
deploy() {
  vols=''; mounts=''
  if [ "${3:-}" = emptydir ]; then
    vols='volumes: [{name: scratch, emptyDir: {}}]'
    mounts='volumeMounts: [{name: scratch, mountPath: /scratch}]'
  fi
  kubectl apply -f - > /dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: $1}
spec:
  replicas: 1
  selector: {matchLabels: {app: $1}}
  template:
    metadata:
      labels: {app: $1}
      annotations: {$2}
    spec:
      terminationGracePeriodSeconds: 0
      tolerations: [{key: kwok-provider, operator: Equal, value: "true", effect: NoSchedule}]
      $vols
      containers:
        - name: pause
          image: "$pause_image"
          resources: {requests: {cpu: 100m, memory: 128Mi}}
          $mounts
EOF
}
pod_of() { kubectl get pods -l "app=$1" --field-selector=status.phase!=Failed -o jsonpath='{.items[0].metadata.name}' 2> /dev/null; }
node_of_pod() { kubectl get pod "$1" -o jsonpath='{.spec.nodeName}' 2> /dev/null; }

# The setup trap: a 1-CPU pod pinned to ng-a has nowhere to move. Instead the
# pod is small and unpinned, and kwokctl's node is cordoned only while CA
# scales ng-a from 0 to 1, so the pod lands on the new node and can move back.
place_on_new_node() { # app, annotations, [emptydir]; prints the node
  kubectl cordon node-000000 > /dev/null
  deploy "$@"
  i=0; until p=$(pod_of "$1") && [ -n "$p" ] && kubectl wait --for=condition=Ready "pod/$p" --timeout=1s > /dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 120 ] || fail "$1: pod not Ready on a new node"; sleep 0.5
  done
  kubectl uncordon node-000000 > /dev/null
  node=$(node_of_pod "$p")
  [ "$(kubectl get node "$node" -o jsonpath='{.metadata.labels.kwok-nodegroup}')" = ng-a ] || fail "$1: pod is on $node, not an ng-a node"
  printf '%s\n' "$node"
}

# The waits poll at 0.5 s; the timeouts are in seconds. A failed request is
# never read as the outcome under test: exists and has_taint return 2 for it,
# --ignore-not-found makes NotFound the only way to read "gone", and
# --request-timeout bounds a hung call. Callers take the status with
# `rc=0; f ... || rc=$?`, so set -e does not stop on 2; the helpers keep their
# own status in other names, so they never leave a value in a caller's rc.
# exists <kind> <name>: 0 if the apiserver shows the object, 1 if it says it
# is gone, 2 if the request failed.
exists() {
  obj=$(kubectl get "$1" "$2" --ignore-not-found -o name --request-timeout=5s 2> /dev/null) || return 2
  [ -n "$obj" ]
}
# has_taint <node> <key>: 0 if the node has the taint, 1 if not, 2 if the
# request failed, which includes a deleted node.
has_taint() {
  taints=$(kubectl get node "$1" -o jsonpath='{.spec.taints[*].key}' --request-timeout=5s 2> /dev/null) || return 2
  printf '%s\n' "$taints" | tr ' ' '\n' | grep -qx "$2"
}
# refute_taint <node> <key>: fail if the node has the taint, was removed, or
# its taints cannot be read. A failed read fails the run rather than being
# retried, since a skipped sample would weaken a "never tainted" claim.
refute_taint() {
  rt=0; has_taint "$1" "$2" || rt=$?
  [ "$rt" -ne 0 ] || fail "$1 got $2"
  [ "$rt" -ne 1 ] || return 0
  rt=0; exists node "$1" || rt=$?
  [ "$rt" -ne 1 ] || fail "$1 was removed"
  fail "could not read $1's taints"
}
wait_taint() { # node, key, timeout
  i=0; until has_taint "$1" "$2"; do
    kubectl get node "$1" > /dev/null 2>&1 || return 1
    i=$((i + 1)); [ "$i" -lt $(($3 * 2)) ] || return 1; sleep 0.5
  done
}
wait_gone() { # kind, name, timeout: 0 once the apiserver says it is gone
  i=0; while :; do
    wg=0; exists "$1" "$2" || wg=$?
    [ "$wg" -ne 1 ] || return 0
    i=$((i + 1)); [ "$i" -lt $(($3 * 2)) ] || return 1; sleep 0.5
  done
}
wait_node_gone() { wait_gone node "$1" "$2"; } # node, timeout
wait_pod_gone() { wait_gone pod "$1" "$2"; }   # pod, timeout
# evictions <code>: the apiserver's count of pods/eviction requests that
# returned <code>, 0 if none yet. A failed /metrics read, or one with no
# apiserver_request_total at all, prints nothing and returns 2, so it never
# supplies a count. Take it with `c=$(evictions 429) || fail ...`.
evictions() {
  ev=$(kubectl get --raw /metrics --request-timeout=5s 2> /dev/null) || return 2
  printf '%s\n' "$ev" | perl -ne '$seen = 1 if /^apiserver_request_total\{/; if (/^apiserver_request_total\{.*code="'"$1"'".*subresource="eviction"/ && /(\S+)$/) { $s += $1 } END { exit 2 unless $seen; print $s + 0, "\n" }'
}
# wait_evictions <code> <count> <timeout>: 0 once the count for <code> is above
# <count>. A failed read is polled through, never read as a count.
wait_evictions() {
  i=0; until we=$(evictions "$1") && [ "$we" -gt "$2" ]; do
    i=$((i + 1)); [ "$i" -lt $(($3 * 2)) ] || return 1; sleep 0.5
  done
}
wait_log() { # extended regex, timeout
  i=0; until ca_log | grep -qE -- "$1"; do
    i=$((i + 1)); [ "$i" -lt $(($2 * 2)) ] || return 1; sleep 0.5
  done
}
# show_log <regex> [max]: matching CA log lines, klog header cut to the time.
# Event lines are left out, from the event sink and from the recorder's own
# "Event(v1.ObjectReference..." lines: they repeat a message already logged.
show_log() { ca_log | klog_short "$1" "${2:-3}"; }
# show_log_after <mark> <regex> [max]: the same, for lines after ca_mark's mark.
show_log_after() { ca_log | tail -n +"$(($1 + 1))" | klog_short "$2" "${3:-3}"; }
klog_short() { # regex, max; CA log on stdin
  grep -vE 'event_sink_logging_wrapper|Event\(v1\.ObjectReference' | grep -E -- "$1" | head -"$2" | sed -E 's/^[IWE][0-9]{4} ([0-9:.]{15})[0-9]* +[0-9]+ [^]]*\] /  \1 /' | cut -c1-220
}
# no_other_reason <node>: fail if CA kept <node> for a reason other than the
# one under test: no place for its pods, or utilization above the threshold
# (simulator/cluster.go#L158, eligibility.go#L163 at 1.35.2).
no_other_reason() {
  if ca_log | grep -qE "Node $1 (is not suitable for removal|unremovable:)"; then
    show_log "Node $1 (is not suitable for removal|unremovable:)" 2
    fail "$1 was kept for a reason other than the one under test"
  fi
}
# klog_epoch: a klog line on stdin ("I1007 10:05:23.456789 ..."), its time as
# epoch seconds with millisecond precision. klog has no year; it is this year.
klog_epoch() {
  perl -MTime::Local=timegm -ne 'if (/^[IWEF](\d\d)(\d\d) (\d\d):(\d\d):(\d\d)\.(\d+)/) { my @t = gmtime; printf "%.3f\n", timegm($5, $4, $3, $2, $1 - 1, $t[5] + 1900) + "0.$6"; exit }'
}
# first_log_epoch <regex>: the time of the first CA log line matching <regex>.
first_log_epoch() { ca_log | grep -E -- "$1" | head -1 | klog_epoch; }
# ca_now: the time of CA's latest log line, which is at most one scan interval
# old while CA runs: the container clock, without a shell in the image.
ca_now() { ca_log | grep -E '^[IWEF][0-9]{4} ' | tail -1 | klog_epoch; }
# A pod annotation or deletion is visible to CA from the next loop, so a flip
# is timed by the first loop that starts after it: the next "Starting main
# loop" line after the host-side mark below. That line opens a loop
# (static_autoscaler.go#L289 at 1.35.2); "Starting scale down" comes after the
# loop's planning (#L620, #L661), so it cannot delimit loops. ca_mark writes
# nothing to CA; it remembers how many log lines there are, and loop_after
# reads after them.
ca_mark() { ca_log | wc -l | tr -d ' '; }
loop_after() { # mark: epoch of the first "Starting main loop" line after mark
  ca_log | tail -n +"$(($1 + 1))" | grep -E 'Starting main loop' | head -1 | klog_epoch
}

since_of() { # node; CA log on stdin
  perl -MTime::Local=timegm -ne '
    if (/\Q'"$1"'\E is unneeded since (\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)? \+0000 UTC/) {
      $s = sprintf "%.3f", timegm($6, $5, $4, $3, $2 - 1, $1) + ($7 || 0);
    }
    END { print "$s\n" if defined $s }'
}

# recheck_of: CA log on stdin; the latest "will re-check them at" time, when a
# node found blocked will next be simulated (planner.go#L322-L324), as epoch
# seconds. The line names no node; the experiments have one candidate.
recheck_of() {
  perl -MTime::Local=timegm -ne '
    if (/will re-check them at (\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)? \+0000 UTC/) {
      $s = sprintf "%.3f", timegm($6, $5, $4, $3, $2 - 1, $1) + ($7 || 0);
    }
    END { print "$s\n" if defined $s }'
}

# timer_verdict since0 since1 removal unneeded: since0 is the timer before a
# flip and since1 after it; removal is when CA tainted the node to delete it.
#   kept     since1 equals since0 (to 1 s), and removal is unneeded to
#            unneeded + 10 s after since0
#   reset    since1 is at least 10 s after since0, and removal is unneeded to
#            unneeded + 10 s after since1
#   unclear  anything else; exits 1
# 10 s is two 5 s scan intervals: removal comes on the first loop after the
# unneeded time, and the loop itself can take a moment.
timer_verdict() {
  perl -e '
    my ($s0, $s1, $r, $u) = @ARGV;
    my $in = sub { my $d = $r - $_[0]; $d >= $u && $d < $u + 10 };
    if (abs($s1 - $s0) < 1 && $in->($s0)) { print "kept\n"; exit 0 }
    if ($s1 - $s0 >= 10 && $in->($s1)) { print "reset\n"; exit 0 }
    print "unclear\n"; exit 1' "$@"
}
