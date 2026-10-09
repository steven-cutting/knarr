#!/bin/sh
# Ticket 28 evidence: rerun every script and rewrite every transcript beside
# it, then check that the run left no registry container and no local image of
# its own behind.
# Needs network, docker (buildx, the docker driver), curl, perl, gh
# (authenticated), the pixi default and cluster environments (`just
# initialize`, `just cluster-install`) and kubeconform from .tools/bin. About
# a minute with the Docker layer cache warm.
# Usage: sh run-all.sh <empty-work-root>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${1:?usage: run-all.sh <empty-work-root>}
mkdir -p "$root"; root=$(cd "$root" && pwd)
[ -z "$(ls -A "$root")" ] || { echo "work root $root is not empty" >&2; exit 2; }
cd "$here"
run() { # transcript, command...
  out=$1; shift
  printf '%-22s ' "$out"
  if "$@" > "$out" 2>&1; then echo ok; else echo "FAILED (see $out)"; exit 1; fi
}
run lib_test.txt        sh lib_test.sh
run ghcr-probe.txt      sh ghcr-probe.sh
run ci-durations.txt    sh ci-durations.sh "$root/ci"
run sources.txt         sh sources.sh "$root/sources"
run registry.txt        sh registry.sh "$root/registry"
digest=$(tail -1 registry.txt | sed -n 's/^digest=//p')
[ -n "$digest" ] || { echo 'registry.txt has no digest= line' >&2; exit 1; }
run overlay-render.txt  sh overlay-render.sh "$root/overlay" "$digest"
run amd64-probe.txt     sh amd64-probe.sh "$root/amd64"
run arm64-probe.txt     sh arm64-probe.sh "$root/arm64"
run actionlint.txt      sh actionlint.sh

# Only this run's objects count: the registry container and the probe images
# are named after this worktree (scripts/cluster-name.sh), so another
# worktree's run does not fail the check. A failed listing stops the run
# rather than reading as "none left".
wt=$(cd "$here/../../../.." && pwd)
n=$(sh "$wt/scripts/cluster-name.sh" "$wt" name)
containers=$(docker ps -a --format '{{.Names}}') || { echo 'cannot list docker containers' >&2; exit 1; }
images=$(docker image ls --format '{{.Repository}}:{{.Tag}}') || { echo 'cannot list docker images' >&2; exit 1; }
left=$(printf '%s\n%s\n' "$containers" "$images" | grep -E "^knarr28-(reg|amd64-probe|arm64-probe)-$n(:|$)" || true)
[ -z "$left" ] || { printf 'left by this run:\n%s\n' "$left" >&2; exit 1; }
echo 'no registry container or probe image left by this run'
