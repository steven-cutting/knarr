#!/bin/sh
# Ticket 14 evidence: rerun every script and rewrite its transcript beside it,
# then delete the worktree's kind cluster. emulation.txt is not rerun: it is
# the hand-run record of the ARM-host attempt, which cannot build the image.
# Needs network, docker and about 20 minutes.
# Usage: sh run-all.sh <worktree> <empty-work-root>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
worktree=${1:?usage: run-all.sh <worktree> <empty-work-root>}
root=${2:?usage: run-all.sh <worktree> <empty-work-root>}
mkdir -p "$root"; root=$(cd "$root" && pwd)
[ -z "$(ls -A "$root")" ] || { echo "work root $root is not empty" >&2; exit 2; }
worktree=$(cd "$worktree" && pwd)
cd "$here"
run() { # transcript, command...
  out=$1; shift
  printf '%-16s ' "$out"
  if "$@" > "$out" 2>&1; then echo ok; else echo "FAILED (see $out)"; exit 1; fi
}
run tls.txt      sh tls/run.sh "$worktree" "$root/tls"
run s1-kind.txt  sh s1-kind.sh "$worktree" "$root/s1-kind"
cp "$root/s1-kind/version.json" version.json
run wrong-ca.txt sh wrong-ca.sh "$worktree" "$root/wrong-ca"
(cd "$worktree" && KNARR_CLUSTER=kind just cluster-down)
echo 'cluster deleted'
