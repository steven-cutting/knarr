#!/bin/sh
# Ticket 02 evidence: rerun every script and rewrite every transcript beside it.
# Needs network, pixi 0.81.0, curl, an authenticated gh and a local clone of
# biscuit_games_tooling whose origin/main is current.
# Usage: sh run-all.sh <empty-work-root> <biscuit_games_tooling-clone>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${1:?usage: run-all.sh <empty-work-root> <biscuit_games_tooling-clone>}
clone=${2:?usage: run-all.sh <empty-work-root> <biscuit_games_tooling-clone>}
mkdir -p "$root"; root=$(cd "$root" && pwd)
[ -z "$(ls -A "$root")" ] || { echo "work root $root is not empty" >&2; exit 2; }
cd "$here"
run() { # transcript, command...
  out=$1; shift
  printf '%-16s ' "$out"
  if "$@" > "$out" 2>&1; then echo ok; else echo "FAILED (see $out)"; exit 1; fi
}
run provenance.txt sh provenance.sh "$clone"
run python.txt     sh python.sh "$root/python"
run allium.txt     sh allium.sh "$root/allium"
run ripsecrets.txt sh ripsecrets.sh "$root/ripsecrets"
