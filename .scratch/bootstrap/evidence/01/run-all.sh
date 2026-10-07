#!/bin/sh
# Ticket 01 evidence: rerun every script and rewrite every transcript beside it.
# Needs network, pixi 0.81.0, curl, gh (authenticated, for asset digests and
# the rebar3 Sigstore check) and docker (for linux.sh and the autoscaler digest).
# Usage: sh run-all.sh <empty-work-root>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${1:?usage: run-all.sh <empty-work-root>}
mkdir -p "$root"; root=$(cd "$root" && pwd)
[ -z "$(ls -A "$root")" ] || { echo "work root $root is not empty" >&2; exit 2; }
cd "$here"
env=$root/solve/.pixi/envs/default
run() { # transcript, command...
  out=$1; shift
  printf '%-22s ' "$out"
  if "$@" > "$out" 2>&1; then echo ok; else echo "FAILED (see $out)"; exit 1; fi
}
run search.txt   sh search.sh
run solve.txt    sh solve.sh "$root/solve"
run tls.txt      sh tls/run.sh "$env" "$root/tls"
rebar3() { sh rebar3/fetch.sh "$root/bin" && sh rebar3/run.sh "$env" "$root/bin" "$root/probe"; }
run rebar3.txt   rebar3
run manifest.txt sh manifest/run.sh "$env" "$root/bin" "$root/manifest"
run tools.txt    sh tools.sh "$root/tools"
run linux.txt    sh linux.sh "$root/solve"
