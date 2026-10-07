#!/bin/sh
# Ticket 15 evidence, experiment 3: does a safe-to-evict flip reset CA 1.35.2's
# per-node unneeded timer? Measured against --scale-down-unneeded-time=40s.
#
#   leg A  absent -> "true", about 15 s into the unneeded time
#   leg B  "true" -> absent, the same
#   leg C  absent -> "false" about 15 s in, then back to absent once CA has
#          seen it. The node should leave the unneeded set, come back with a
#          new since, and be removed about 40 s after the new since, later
#          than the old one would have allowed. This is also experiment 2 (a).
#          The flip back comes as soon as CA logs the block, two loops before
#          --unremovable-node-recheck-timeout (15 s) runs out, so the
#          transcript tells the two possible causes of the return apart: the
#          loop that first sees the annotation gone (or the one after), or
#          the recheck time CA logs. Every loop from the flip back to the
#          return is shown, with its "ignoring ... unremovable" line.
#
# since is CA's own "is unneeded since" value. since0 is read before the flip
# and since1 from the first full loop after it (a loop that started after the
# annotate). removal is CA's "Scale-down: removing node" line. All three are on
# the container's clock. timer_verdict (lib.sh, lib_test.sh) gives kept or
# reset with a 10 s margin, two scan intervals.
#
# Each leg gets a fresh CA container. Setup and flags: lib.sh and README.md.
# Needs docker.
# Usage: sh exp3-timer.sh <tools-dir> <empty-work-dir>
# shellcheck disable=SC2218  # a false positive in 0.11.0: see lib.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage='usage: exp3-timer.sh <tools-dir> <empty-work-dir>'
# shellcheck source=lib.sh disable=SC1091  # the gate runs without -x
. "$here/lib.sh"
ca_init "${1:?$usage}" "${2:?$usage}"
ste='"cluster-autoscaler.kubernetes.io/safe-to-evict"'
ste_key=cluster-autoscaler.kubernetes.io/safe-to-evict
blackout=''
unneeded=40
recheck=15

# loop_lines <mark>: the log of the first loop that starts after <mark>: the
# lines from the first "Starting main loop" past <mark> up to the next one
# (lib.sh, loop_after). It waits until that loop has finished.
loop_lines() {
  i=0; until [ "$(ca_log | tail -n +"$(($1 + 1))" | grep -c 'Starting main loop')" -ge 2 ]; do
    i=$((i + 1)); [ "$i" -lt 60 ] || fail 'CA ran no loop after the flip'; sleep 0.5
  done
  ca_log | tail -n +"$(($1 + 1))" | awk '/Starting main loop/ { n++; if (n == 2) exit } n == 1'
}
wait_until() { # epoch on CA's clock
  i=0; until perl -e 'exit !($ARGV[1] >= $ARGV[0])' "$1" "$(ca_now)"; do
    i=$((i + 1)); [ "$i" -lt 240 ] || fail 'CA clock did not reach the flip time'; sleep 0.5
  done
}
annotate() { # pod, true|false|absent
  if [ "$2" = absent ]; then kubectl annotate pod "$1" "$ste_key-" > /dev/null
  else kubectl annotate pod "$1" "$ste_key=$2" --overwrite > /dev/null; fi
}
rel() { perl -e 'printf "%+.1f s", $ARGV[1] - $ARGV[0]' "$@"; }
hms() { perl -e 'my @t = gmtime $ARGV[0]; printf "%02d:%02d:%06.3f", @t[2, 1], $t[0] + $ARGV[0] - int $ARGV[0]' "$1"; }

# leg <name> <initial: absent|true> <flip: true|absent|false>
leg() {
  app=exp3-$1
  if [ "$2" = true ]; then ann="$ste: \"true\""; else ann=''; fi
  ca_start
  node=$(place_on_new_node "$app" "$ann")
  pod=$(pod_of "$app")
  echo "pod $pod ($2) is on new node $node"
  wait_log "$node is unneeded since" 60 || fail "$node never unneeded"
  since0=$(ca_log | since_of "$node")
  wait_until "$(perl -e 'print $ARGV[0] + 15' "$since0")"
  mark=$(ca_mark); annotate "$pod" "$3"
  if [ "$3" = false ]; then
    # Flip back as soon as CA has logged the block: the loop that blocked has
    # already listed the pods, so the next loop is the first to see absent.
    wait_log "Node $node cannot be removed: pod annotated as not safe to evict present: $pod" 20 || fail 'not blocked by "false"'
    mark2=$(ca_mark); annotate "$pod" absent
  fi
  lines=$(loop_lines "$mark")
  seen=$(loop_after "$mark")
  since1=$(printf '%s\n' "$lines" | since_of "$node")
  if [ -n "$since1" ]; then s1=$(hms "$since1"); else s1='(not unneeded)'; fi
  printf '  since0 %s; flip %s -> %s seen by the loop at since0 %s; since1 %s\n' \
    "$(hms "$since0")" "$2" "$3" "$(rel "$since0" "$seen")" "$s1"
  if [ "$3" = false ]; then
    [ -z "$since1" ] || fail "$node still unneeded after the flip to \"false\""
    show_log_after "$mark" "Node $node cannot be removed|nodes found to be unremovable in simulation, will re-check them at" 2
    recheck_at=$(ca_log | tail -n +"$((mark + 1))" | grep -m1 'will re-check them at' | recheck_of)
    [ -n "$recheck_at" ] || fail 'CA logged no recheck time'
    back_lines=$(loop_lines "$mark2")
    t_back=$(loop_after "$mark2")
    echo "  flip false -> absent seen by the loop at since0 $(rel "$since0" "$t_back"); CA's recheck time is since0 $(rel "$since0" "$recheck_at")"
    i=0; until [ -n "$(ca_log | tail -n +"$((mark2 + 1))" | since_of "$node")" ]; do
      i=$((i + 1)); [ "$i" -lt 120 ] || fail "$node never unneeded again"; sleep 0.5
    done
    since1=$(ca_log | tail -n +"$((mark2 + 1))" | since_of "$node")
    echo "  every loop from the flip back to the return:"
    show_log_after "$mark2" "Starting main loop|ignoring [0-9]+ nodes unremovable|$node is unneeded since" 40 |
      awk -v n="$node is unneeded since" '{ print } index($0, n) { exit }'
    echo "  $node unneeded again: since1 $(hms "$since1") (since0 $(rel "$since0" "$since1"), recheck time $(rel "$recheck_at" "$since1"), $(rel "$t_back" "$since1") after the loop that saw the flip back)"
    # The return is the recheck, not the flip back, when: the flip back was
    # seen well before the recheck time; the loop that saw it still skipped
    # the node as recently unremovable; the return is at least two loops after
    # that one; and the return is the first loop at or after the recheck time.
    printf '%s\n' "$back_lines" | grep -q 'ignoring 1 nodes unremovable' || fail 'leg C: the loop that saw the flip back did not skip the node'
    perl -e 'my ($t, $s, $r, $scan) = @ARGV; exit !($t < $r - $scan + 1 && $s >= $t + 2 * $scan - 1 && $s >= $r - 0.01 && $s < $r + $scan + 1)' \
      "$t_back" "$since1" "$recheck_at" 5 || fail 'leg C: the return is not explained by the recheck time alone'
    blackout=recheck
  fi
  wait_taint "$node" ToBeDeletedByClusterAutoscaler 120 || fail "$node never tainted for deletion"
  removal=$(first_log_epoch "Scale-down: removing node $node,")
  wait_node_gone "$node" 60 || fail "$node not deleted"
  no_other_reason "$node"
  printf '  removal %s: since0 %s, since1 %s (unneeded time %s s)\n' "$(hms "$removal")" "$(rel "$since0" "$removal")" "$(rel "$since1" "$removal")" "$unneeded"
  if [ "$3" = false ]; then
    echo "  removal is $(rel "$(perl -e 'print $ARGV[0] + $ARGV[1]' "$since0" "$unneeded")" "$removal") later than since0 + $unneeded s"
  fi
  verdict=$(timer_verdict "$since0" "$since1" "$removal" "$unneeded") || fail "leg $1: timing unclear"
  ca_stop; kubectl delete deployment "$app" --wait=true > /dev/null
}

echo; echo '== cluster'
ca_cluster_up

echo; echo '== leg A: absent -> "true"'
leg a absent true
[ "$verdict" = kept ] || fail "leg A: $verdict"
echo "ok   leg A: timer $verdict"

echo; echo '== leg B: "true" -> absent'
leg b true absent
[ "$verdict" = kept ] || fail "leg B: $verdict"
echo "ok   leg B: timer $verdict"

echo; echo '== leg C: absent -> "false" -> absent'
leg c absent false
[ "$verdict" = reset ] || fail "leg C: $verdict"
echo "ok   leg C: timer $verdict"
[ "$blackout" = recheck ] || fail 'leg C: blackout not checked'
echo "ok   leg C: the node stayed out after the loops that saw the annotation gone, and came back on the first loop at CA's recheck time (block + $recheck s)"

echo
echo 'verdict: switching between absent and "true" keeps the unneeded timer; a spell of "false" drops the node from the unneeded set, it is looked at again only when the unremovable recheck timeout runs out (counted from when CA found it blocked, not from the flip back), and then it starts a new timer'
