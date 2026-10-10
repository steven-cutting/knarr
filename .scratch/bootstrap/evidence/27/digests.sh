#!/bin/sh
# Ticket 27 evidence: the Dockerfile's two base images, pinned by the digest of
# their OCI index. For each FROM line it reads the pinned digest, asks the
# registry what the tag names today, and lists the pinned index's linux/amd64
# and linux/arm64 manifests. A pin that is not an index, or an index without
# both platforms, fails the run: the build is amd64 (Decision 0012) and ticket
# 38's arm64 build pins the same line. A tag that has moved since the pin is a
# finding, not a failure: it is what Renovate proposes as a digest update.
# Registry reads only. Needs docker with buildx.
# Usage: sh digests.sh <empty-work-dir>
# The gate runs shellcheck without -x, so it cannot see that lib.sh sets
# wt and py.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=$(work_dir "${1:?usage: digests.sh <empty-work-dir>}")
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
printf 'revision: %s\n' "$(git -C "$wt" rev-parse --short HEAD)"
bases=$(git -C "$wt" show HEAD:Dockerfile | sed -n 's/^FROM \([^ ]*\).*/\1/p')
[ "$(printf '%s\n' "$bases" | wc -l | tr -d ' ')" = 2 ] || fail "expected two FROM lines, got: $bases"
n=0
for ref in $bases; do
  n=$((n + 1))
  name=${ref%@*}
  pinned=${ref#*@}
  [ "$pinned" != "$ref" ] || fail "$ref is not pinned by digest"
  docker buildx imagetools inspect --format '{{json .Manifest}}' "$name" > "$work/$n-tag.json"
  docker buildx imagetools inspect --format '{{json .Manifest}}' "$name@$pinned" > "$work/$n-pinned.json"
  "$py" -I - "$name" "$pinned" "$work/$n-tag.json" "$work/$n-pinned.json" <<'EOF'
import json
import sys

name, pinned, tag_file, pinned_file = sys.argv[1:]
today = json.load(open(tag_file))["digest"]
index = json.load(open(pinned_file))
print(f"-- {name}")
print(f"pinned:       {pinned}")
print(f"tag today:    {today}")
if today == pinned:
    print("verdict:      the tag still names the pinned index")
else:
    print("verdict:      the tag has moved since the pin; Renovate proposes the new digest")
kinds = ("application/vnd.oci.image.index.v1+json",
         "application/vnd.docker.distribution.manifest.list.v2+json")
if index["mediaType"] not in kinds:
    sys.exit(f"FAIL: {pinned} is a {index['mediaType']}, not an index")
platforms = {}
for manifest in index["manifests"]:
    platform = manifest.get("platform", {})
    platforms.setdefault(f"{platform.get('os')}/{platform.get('architecture')}", manifest["digest"])
print(f"index:        {len(index['manifests'])} manifests, attestations included")
for wanted in ("linux/amd64", "linux/arm64"):
    if wanted not in platforms:
        sys.exit(f"FAIL: the pinned index has no {wanted} manifest")
    print(f"{wanted + ':':<14}{platforms[wanted]}")
EOF
done
