#!/bin/sh
# Ticket 15 evidence: rerun every script and rewrite every transcript beside it,
# then check that no spike cluster or CA container is left.
# Needs network, pixi 0.81.0, curl, perl, openssl, gh (authenticated), docker
# and about 20 minutes.
# Usage: sh run-all.sh <empty-work-root>
# The tools come from 10's fetch.sh, whose output goes to <root>/fetch.log, not
# to a transcript here. The work root ends up holding setup-envtest's read-only
# asset directory; remove it with: chmod -R u+w <root> && rm -rf <root>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${1:?usage: run-all.sh <empty-work-root>}
mkdir -p "$root"; root=$(cd "$root" && pwd)
[ -z "$(ls -A "$root")" ] || { echo "work root $root is not empty" >&2; exit 2; }
cd "$here"
tools=$root/tools
run() { # transcript, command...
  out=$1; shift
  printf '%-26s ' "$out"
  if "$@" >| "$out" 2>&1; then echo ok; else echo "FAILED (see $out)"; exit 1; fi
}
run "$root/fetch.log"         sh ../10/fetch.sh "$tools"
run lib_test.txt              sh lib_test.sh
run source.txt                sh source.sh "$root/source"
run exp1-false-blocks.txt     sh exp1-false-blocks.sh "$tools" "$root/exp1"
run exp2-recheck.txt          sh exp2-recheck.sh "$tools" "$root/exp2"
run exp3-timer.txt            sh exp3-timer.sh "$tools" "$root/exp3"
run exp4-local-storage.txt    sh exp4-local-storage.sh "$tools" "$root/exp4"

# lib.sh names the CA container <cluster>-ca, and the cluster is named by
# 10's name.sh after the work dir: exp<N>-<8 hex>.
left=$(docker ps -a --format '{{.Names}} {{.Label "io.x-k8s.kind.cluster"}} {{.Label "k3d.cluster"}}' |
  awk '$2 != "" || $3 != "" || $1 ~ /^kwok-/ || $1 ~ /^exp[1-4]-[0-9a-f]+-ca$/')
[ -z "$left" ] || { printf 'spike containers left:\n%s\n' "$left" >&2; exit 1; }
echo 'no kind, k3d, kwok or CA container left'
