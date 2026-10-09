#!/bin/sh
# Ticket 28 evidence: what a linux/arm64 image would cost. The lock has no
# linux-aarch64 entries, so the build stage is expected to fail at `pixi
# install --locked` at once, without downloading anything; the time to that
# failure and pixi's own message are recorded. Then whether both base images
# have an arm64 variant, read from their registries without pulling. No
# re-lock: platforms are ticket 27's domain.
# Needs docker and network (the pixi image's arm64 variant, two registry reads).
# Usage: sh arm64-probe.sh <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=${1:?usage: arm64-probe.sh <empty-work-dir>}
work=$(work_dir "$work")
root=$(cd "$here/../../../.." && pwd)
image=knarr28-arm64-probe-$(sh "$root/scripts/cluster-name.sh" "$root" name)
trap 'docker image rm -f "$image" > /dev/null 2>&1 || true' EXIT
say() { printf '%s\n' "$*"; }
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
say "host: $(uname -sm); docker $(docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}'); linux/arm64 is native here"
say "pixi.toml platforms: $(grep -E '^platforms = ' "$root/pixi.toml")"
say "linux-aarch64 entries in pixi.lock: $(grep -c linux-aarch64 "$root/pixi.lock" || true)"
start=$(date +%s)
rc=0; docker build --platform linux/arm64 --target build --tag "$image" "$root" > "$work/build.log" 2>&1 || rc=$?
secs=$(($(date +%s) - start))
if [ "$rc" -eq 0 ]; then
  say "the arm64 build stage succeeded in $secs s: the lock now covers linux-aarch64, and this record is stale"
  exit 0
fi
step=$(grep -oE '^#[0-9]+ \[build +[0-9]+/[0-9]+\] RUN .*' "$work/build.log" | tail -1 | sed -E 's/^#[0-9]+ //' | cut -c1-110)
say "the arm64 build stage failed after $secs s at: $step"
say 'pixi says (build.log):'
grep -E 'Declared platforms|linux-64:|osx-arm64:|platform add' "$work/build.log" | sed -E 's/^#?[0-9]* *[0-9.]+ +//' | sort -u | sed 's/^/  /'
grep -q 'pixi workspace platform add linux-aarch64' "$work/build.log" || fail 'the build failed for a reason other than the missing linux-aarch64 platform'
say '-- arm64 variants of the base images (registry reads, no pull)'
for ref in ghcr.io/prefix-dev/pixi:0.81.0 ubuntu:24.04; do
  plats=$(docker buildx imagetools inspect "$ref" | grep -E '^ +Platform:' | awk '{ print $2 }' | grep -vE 'unknown' | sort -u | tr '\n' ' ')
  say "$ref: $plats"
  printf '%s\n' "$plats" | grep -q 'linux/arm64' || fail "$ref has no linux/arm64 variant"
done
say 'finding: arm64 needs linux-aarch64 in pixi.toml platforms and a re-lock (27), then one more build job on an ubuntu-24.04-arm runner and an imagetools create to merge the two manifests into one index; the native arm64 BEAM runtime image is unverified (13)'
