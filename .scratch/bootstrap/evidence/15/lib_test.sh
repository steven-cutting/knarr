#!/bin/sh
# Ticket 15 evidence: tests for the helpers in lib.sh that the experiments'
# verdicts rest on, through the same command-line style as 10's name_test.sh.
# The log lines are copied from a CA 1.35.2 run on kwok.
#   since_of       the latest "is unneeded since" for a node, as epoch seconds
#   timer_verdict  kept, reset or unclear, from two since values, the removal
#                  time and the unneeded time
#   recheck_of     the latest "will re-check them at" time, as epoch seconds
#   exists, wait_gone, has_taint, refute_taint
#                  through a stub kubectl: a refused or Forbidden request is
#                  never read as "gone" or as "no taint"
# Usage: sh lib_test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091  # the gate runs without -x
. "$here/lib.sh"
trap - EXIT
pass=0; failed=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { failed=$((failed + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }
eq() { # description, actual, expected
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "got '$2', want '$3'"; fi
}

log='I1007 17:44:24.102279       1 static_autoscaler.go:656] Starting scale down: no scale down candidates. skipping...
I1007 17:44:34.724899       1 nodes.go:153] ng-a-29t9x is unneeded since 2026-10-07 17:44:34.724021851 +0000 UTC m=+15.782944353 duration 0s
I1007 17:44:34.724901       1 nodes.go:153] ng-a-zz9qq is unneeded since 2026-10-07 17:44:20.000000000 +0000 UTC m=+1.058922502 duration 14.724901s
I1007 17:44:39.751761       1 nodes.go:153] ng-a-29t9x is unneeded since 2026-10-07 17:44:34.724021851 +0000 UTC m=+15.782944353 duration 5.02671623s
I1007 17:45:01.100000       1 nodes.go:153] ng-a-29t9x is unneeded since 2026-10-07 17:45:01.099000000 +0000 UTC m=+42.157922502 duration 0s'
# 2026-10-07T17:44:34Z is 1791395074 seconds after the epoch.
eq 'since_of gives the latest since for the node, in epoch seconds' \
  "$(printf '%s\n' "$log" | since_of ng-a-29t9x)" 1791395101.099
eq 'since_of ignores lines for other nodes' \
  "$(printf '%s\n' "$log" | since_of ng-a-zz9qq)" 1791395060.000
eq 'since_of gives nothing for a node that was never unneeded' \
  "$(printf '%s\n' "$log" | since_of ng-a-absent)" ''
eq 'since_of does not match a node whose name is a prefix of another' \
  "$(printf '%s\n' "$log" | since_of ng-a-29t9)" ''
eq 'since_of reads an empty log as nothing' "$(printf '' | since_of ng-a-29t9x)" ''

# timer_verdict since0 since1 removal unneeded
eq 'same since, removal 40.1 s later: kept' "$(timer_verdict 1000 1000 1040.1 40)" kept
eq 'since moved by under 1 s, removal 45 s later: kept' "$(timer_verdict 1000 1000.4 1045 40)" kept
eq 'since moved 30 s, removal 40.5 s after the new one: reset' "$(timer_verdict 1000 1030 1070.5 40)" reset
if v=$(timer_verdict 1000 1000 1039.9 40); then no 'removal before the unneeded time: unclear, exit 1' "got '$v', exit 0"
else eq 'removal before the unneeded time: unclear, exit 1' "$v" unclear; fi
if v=$(timer_verdict 1000 1000 1050 40); then no 'removal 10 s late: unclear, exit 1' "got '$v', exit 0"
else eq 'removal 10 s late: unclear, exit 1' "$v" unclear; fi
if v=$(timer_verdict 1000 1005 1045 40); then no 'since moved 5 s, within the margin: unclear, exit 1' "got '$v', exit 0"
else eq 'since moved 5 s, within the margin: unclear, exit 1' "$v" unclear; fi
if v=$(timer_verdict 1000 1030 1041 40); then no 'since reset but removal on the old timer: unclear, exit 1' "got '$v', exit 0"
else eq 'since reset but removal on the old timer: unclear, exit 1' "$v" unclear; fi

rlog='I1007 17:54:52.190398       1 planner.go:323] 1 nodes found to be unremovable in simulation, will re-check them at 2026-10-07 17:55:07.125123456 +0000 UTC m=+50.183
I1007 17:55:07.233000       1 planner.go:323] 1 nodes found to be unremovable in simulation, will re-check them at 2026-10-07 17:55:22.230000000 +0000 UTC m=+65.288'
eq 'recheck_of gives the latest recheck time, in epoch seconds' \
  "$(printf '%s\n' "$rlog" | recheck_of)" 1791395722.230
eq 'recheck_of reads the first of them from a log cut after it' \
  "$(printf '%s\n' "$rlog" | head -1 | recheck_of)" 1791395707.125
eq 'recheck_of gives nothing when no node was found unremovable' \
  "$(printf '%s\n' "$log" | recheck_of)" ''

eq 'klog_epoch reads a klog prefix with this year' \
  "$(printf 'I1007 17:44:34.724899       1 x.go:1] y\n' | klog_epoch)" \
  "$(perl -MTime::Local=timegm -e 'my @t = gmtime; printf "%.3f\n", timegm(34, 44, 17, 7, 9, $t[5] + 1900) + 0.724899')"

# The API helpers, through a stub kubectl first on PATH. KUBECTL_STUB picks
# what the apiserver does: present (the object exists, with STUB_TAINTS as its
# taint keys), absent (NotFound), refused (no connection) or forbidden (RBAC).
# A failed request must never read as "gone" or as "no taint".
stub=$(mktemp -d)
trap 'rm -rf "${stub:?}"' EXIT
cat > "$stub/kubectl" <<'EOF'
#!/bin/sh
case $KUBECTL_STUB in
  refused) echo 'The connection to the server 127.0.0.1:6443 was refused' >&2; exit 1 ;;
  forbidden) echo "Error from server (Forbidden): $2 \"$3\" is forbidden" >&2; exit 1 ;;
  absent)
    case " $* " in *' --ignore-not-found '*) exit 0 ;; esac
    echo "Error from server (NotFound): $2 \"$3\" not found" >&2; exit 1 ;;
  present)
    case " $* " in *' -o name '*) echo "$2/$3" ;; *) printf '%s' "$STUB_TAINTS" ;; esac ;;
  *) echo "stub kubectl: unknown KUBECTL_STUB '$KUBECTL_STUB'" >&2; exit 3 ;;
esac
EOF
chmod +x "$stub/kubectl"
PATH=$stub:$PATH
KUBECTL_STUB=''; STUB_TAINTS=''; export KUBECTL_STUB STUB_TAINTS
api() { KUBECTL_STUB=$1; STUB_TAINTS=${2:-}; } # mode, [taint keys]
status() { rc=0; "$@" || rc=$?; echo "$rc"; }
# refute <mode> [taints]: refute_taint's message, then its exit status. fail
# is replaced in the subshell, since the real one reads CA's container.
refute() {
  api "$@"
  rc=0
  # shellcheck disable=SC2329  # refute_taint calls it
  ( fail() { printf '%s; ' "$*"; exit 1; }; refute_taint ng-a-x ToBeDeletedByClusterAutoscaler ) || rc=$?
  printf 'exit %s\n' "$rc"
}

api present; eq 'exists: an object the apiserver shows is 0' "$(status exists pod x)" 0
api absent; eq 'exists: an object the apiserver says is gone is 1' "$(status exists pod x)" 1
api refused; eq 'exists: a refused connection is 2, not gone' "$(status exists pod x)" 2
api forbidden; eq 'exists: a Forbidden answer is 2, not gone' "$(status exists node x)" 2

api absent; eq 'wait_gone: returns 0 once the object is gone' "$(status wait_gone pod x 1)" 0
api present; eq 'wait_gone: times out while the object exists' "$(status wait_gone pod x 1)" 1
api refused; eq 'wait_gone: times out on a refused connection' "$(status wait_gone pod x 1)" 1
api forbidden; eq 'wait_gone: times out on a Forbidden answer' "$(status wait_gone node x 1)" 1
api refused; eq 'wait_pod_gone: times out on a refused connection' "$(status wait_pod_gone x 1)" 1
api forbidden; eq 'wait_node_gone: times out on a Forbidden answer' "$(status wait_node_gone x 1)" 1

api present 'DeletionCandidateOfClusterAutoscaler ToBeDeletedByClusterAutoscaler'
eq 'has_taint: 0 when the node has the key' "$(status has_taint x ToBeDeletedByClusterAutoscaler)" 0
api present DeletionCandidateOfClusterAutoscaler
eq 'has_taint: 1 when the node has other keys only' "$(status has_taint x ToBeDeletedByClusterAutoscaler)" 1
api present; eq 'has_taint: 1 when the node has no taints' "$(status has_taint x ToBeDeletedByClusterAutoscaler)" 1
api refused; eq 'has_taint: 2 on a refused connection, not "no taint"' "$(status has_taint x ToBeDeletedByClusterAutoscaler)" 2

eq 'refute_taint: passes when the node lacks the taint' "$(refute present DeletionCandidateOfClusterAutoscaler)" 'exit 0'
eq 'refute_taint: fails when the node has the taint' "$(refute present ToBeDeletedByClusterAutoscaler)" \
  'ng-a-x got ToBeDeletedByClusterAutoscaler; exit 1'
eq 'refute_taint: fails on a refused connection' "$(refute refused)" "could not read ng-a-x's taints; exit 1"
eq 'refute_taint: fails on a Forbidden answer' "$(refute forbidden)" "could not read ng-a-x's taints; exit 1"
eq 'refute_taint: names a deleted node as removed, not as an API error' "$(refute absent)" 'ng-a-x was removed; exit 1'

printf '%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
