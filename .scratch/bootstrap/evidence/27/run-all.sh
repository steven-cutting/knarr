#!/bin/sh
# Ticket 27 evidence: rerun every script and rewrite every transcript beside
# it, then check that no Renovate container was left behind (every run is
# --rm).
# Needs network, docker (buildx), curl, perl, git, gh (authenticated), pixi,
# and the pixi default and audit environments (`just initialize`, `just
# audit-install`). grype's database makes the work root about 3 GB.
# Usage: sh run-all.sh <empty-work-root>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${1:?usage: run-all.sh <empty-work-root>}
mkdir -p "$root"; root=$(cd "$root" && pwd)
[ -z "$(ls -A "$root")" ] || { echo "work root $root is not empty" >&2; exit 2; }
cd "$here"
run() { # transcript, command...
  out=$1; shift
  printf '%-18s ' "$out"
  if "$@" > "$out" 2>&1; then echo ok; else echo "FAILED (see $out)"; exit 1; fi
}
run inventory.txt   sh inventory.sh "$root/inventory"
run sources.txt     sh sources.sh "$root/sources"
run digests.txt     sh digests.sh "$root/digests"
run renovate.txt    sh renovate.sh "$root/renovate"
run osv-probe.txt   sh osv-probe.sh "$root/osv"
run grype-probe.txt sh grype-probe.sh "$root/grype"

# A failed listing stops the run rather than reading as "none left".
images=$(docker ps -a --format '{{.Image}}') || { echo 'cannot list docker containers' >&2; exit 1; }
left=$(printf '%s\n' "$images" | grep -F 'renovatebot/renovate' || true)
[ -z "$left" ] || { printf 'left by this run:\n%s\n' "$left" >&2; exit 1; }
echo 'no Renovate container left'
