#!/bin/sh
# Ticket 10 evidence: rerun every script and rewrite every transcript beside it,
# then check that no spike cluster is left and OrbStack's k8s is disabled.
# Needs network, pixi 0.81.0, curl, perl, openssl, gh (authenticated), docker
# (OrbStack, for orbstack.sh) and about 15 minutes.
# Usage: sh run-all.sh <empty-work-root>
# The work root ends up holding setup-envtest's read-only asset directory;
# remove it with: chmod -R u+w <root> && rm -rf <root>
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
run fetch.txt                 sh fetch.sh "$tools"
run name_test.txt             sh name_test.sh
run pins.txt                  sh pins.sh "$tools"
run deletion-cost-kwokctl.txt sh deletion-cost.sh "$tools" kwokctl "$root/deletion-cost-kwokctl"
run deletion-cost-kind.txt    sh deletion-cost.sh "$tools" kind "$root/deletion-cost-kind"
run timing.txt                sh timing.sh "$tools" "$root/timing"
# Before orbstack.sh: worktree.sh asserts ~/.kube/config is unchanged.
run worktree.txt              sh worktree.sh "$tools" "$root/worktree"
run orbstack.txt              sh orbstack.sh "$tools" "$root/orbstack"
run ca-kwok.txt               sh ca-kwok.sh "$tools" "$root/ca-kwok"

left=$(docker ps -a --format '{{.Names}} {{.Label "io.x-k8s.kind.cluster"}} {{.Label "k3d.cluster"}}' |
  awk '$2 != "" || $3 != "" || $1 ~ /^kwok-/')
[ -z "$left" ] || { printf 'spike containers left:\n%s\n' "$left" >&2; exit 1; }
echo 'no kind, k3d or kwok container left'
[ "$(orbctl config get k8s.enable)" = false ] || { echo 'OrbStack k8s.enable is not false' >&2; exit 1; }
echo 'OrbStack k8s.enable: false'
