#!/bin/sh
# Ticket 28 evidence: the GHCR route rehearsed end to end against a throwaway
# registry:2 on loopback, with the exact buildx command the drafted release
# workflow runs. In order:
#   1. the release guards on this checkout: tag == gleam.toml version, and the
#      tag set tags_for derives (X.Y.Z, X.Y, sha-<7>; no latest)
#   2. buildx build --push of a linux/amd64 image with knarr's OCI labels, with
#      --provenance=false --sbom=false on the docker driver, and why
#   3. the digest read three ways (--metadata-file, the registry's
#      Docker-Content-Digest, imagetools inspect), all equal; every tag
#      resolves to it
#   4. the pre-push guard's three verdicts against this registry
#   5. tags move, digests do not: a second push to the same tag changes what
#      the tag resolves to, while the old digest still pulls and shows the
#      first push's labels
#   6. a real pull by digest and by tag after the local copies are removed
# The image is a stand-in: FROM scratch, one file, knarr's labels. The real
# image cannot be built on this host (amd64-probe.txt), and none of the
# registry mechanics above depends on what is in the image. Nothing here
# touches ghcr.io.
# Needs docker (buildx, the docker driver), curl, perl, git and the registry:2
# image (pulled on first use).
# Usage: sh registry.sh <empty-work-dir>
# The gate runs shellcheck without -x, so it cannot see that probe_tag in lib.sh
# sets verdict, verdict_rc, code and curl_rc.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=${1:?usage: registry.sh <empty-work-dir>}
work=$(work_dir "$work")
root=$(cd "$here/../../../.." && pwd)
# One registry per worktree, named like the worktree's clusters, so two
# worktrees can run this at once and the leftover check in run-all.sh knows
# which container is this run's.
name=knarr28-reg-$(sh "$root/scripts/cluster-name.sh" "$root" name)
repo=knarr
say() { printf '%s\n' "$*"; }
cleanup() {
  docker rm -f "$name" > /dev/null 2>&1 || true
  # shellcheck disable=SC2046  # image ids, one per word
  docker image rm -f $(docker image ls -q "localhost:$port/$repo" 2> /dev/null) > /dev/null 2>&1 || true
}
port=0
trap cleanup EXIT

printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
say "docker $(docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}'), $(docker buildx version | cut -d' ' -f1-2), builder: $(docker buildx inspect | awk '/^Driver:/ { d = $2 } /^BuildKit( daemon)? version:/ { v = $NF } END { print d " driver, BuildKit " v }')"

say '-- 1. release guards on this checkout'
tag=v0.1.0
version=$(toml_version < "$root/gleam.toml")
rc=0; tag_matches_version "$tag" "$version" || rc=$?
say "tag $tag against gleam.toml version $version: exit $rc (0 is a match)"
[ "$rc" -eq 0 ] || fail "the dry run's tag must match gleam.toml"
sha=$(git -C "$root" rev-parse HEAD)
tags=$(tags_for "$tag" "$sha")
say "tags for $tag at ${sha}: $(printf '%s' "$tags" | tr '\n' ' ')"
[ "$(printf '%s\n' "$tags" | grep -c '^latest$')" -eq 0 ] || fail 'latest must never be pushed'

say "-- 2. buildx build --push to a throwaway registry:2 ($name)"
docker run -d --name "$name" -p 127.0.0.1::5000 registry:2 > /dev/null
port=$(docker port "$name" 5000/tcp | head -1 | sed 's/.*://')
reg=http://127.0.0.1:$port
i=0; until [ "$(curl -s -o /dev/null -w '%{http_code}' "$reg/v2/")" = 200 ]; do
  i=$((i + 1)); [ "$i" -lt 40 ] || fail 'registry:2 never answered /v2/'; sleep 0.5
done
say "registry:2 on $reg (loopback only)"
ctx=$work/stand-in
mkdir -p "$ctx"
printf 'FROM scratch\nCOPY stand-in.txt /knarr-stand-in\n' > "$ctx/Dockerfile"
echo 'knarr release dry run: first push' > "$ctx/stand-in.txt"
tagargs=''
for t in $tags; do tagargs="$tagargs --tag localhost:$port/$repo:$t"; done
# The command the drafted release.yml runs, with its tags. --provenance=false
# --sbom=false: the docker driver pushes a single manifest and cannot attach
# attestations (shown below); with them on, the pushed object would be an
# index with a different digest, which is what the overlay would then pin.
start=$(date +%s)
# shellcheck disable=SC2086  # one --tag per word
docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  --label "org.opencontainers.image.source=https://github.com/steven-cutting/knarr" \
  --label "org.opencontainers.image.version=$version" \
  --label "org.opencontainers.image.revision=$sha" \
  --label "org.opencontainers.image.title=knarr stand-in for the release dry run" \
  --metadata-file "$work/metadata.json" $tagargs --push "$ctx" > "$work/build.log" 2>&1 ||
  { tail -20 "$work/build.log"; fail 'buildx build --push failed'; }
say "pushed $(printf '%s\n' "$tags" | wc -l | tr -d ' ') tags in $(($(date +%s) - start)) s (log: $work/build.log)"
say "manifest media type: $(perl -0777 -ne 'print $1 if /"containerimage\.descriptor":\s*\{\s*"mediaType":\s*"([^"]+)"/' "$work/metadata.json")"
say "image store: $(docker info --format '{{.Driver}}{{range .DriverStatus}} {{index . 0}}={{index . 1}}{{end}}')"
if docker buildx build --platform linux/amd64 --provenance=mode=min --tag "localhost:$port/$repo:attest-probe" --push "$ctx" > "$work/attest-probe.log" 2>&1; then
  say "with --provenance=mode=min the same build pushes an index instead (the containerd image store allows it; the classic store refuses):"
  docker buildx imagetools inspect "localhost:$port/$repo:attest-probe" | grep -E '^(MediaType|Digest|  Platform|  Annotations|    vnd\.docker\.reference\.type):' | sed 's/^/  /'
  say "  so with attestations on, the digest to pin is the index's, not the image manifest's (ticket 38)"
else
  say "with --provenance=mode=min the docker driver refuses: $(grep -E 'ERROR|error' "$work/attest-probe.log" | head -1 | cut -c1-160)"
fi

say '-- 3. one digest, three readings'
d_meta=$(digest_of_metadata < "$work/metadata.json") || fail 'no digest in metadata.json'
d_head=$(head_digest "$reg" "$repo" "$version") || fail 'no Docker-Content-Digest from the registry'
d_insp=$(docker buildx imagetools inspect "localhost:$port/$repo:$version" | digest_of_inspect) || fail 'no digest from imagetools inspect'
printf "%-26s %s\n" "--metadata-file:" "$d_meta" "Docker-Content-Digest:" "$d_head" "imagetools inspect:" "$d_insp"
[ "$d_meta" = "$d_head" ] && [ "$d_meta" = "$d_insp" ] || fail 'the three digest readings differ'
say 'all three agree'
for t in $tags; do
  d=$(head_digest "$reg" "$repo" "$t") || fail "tag $t has no digest"
  [ "$d" = "$d_meta" ] || fail "tag $t resolves to $d, not $d_meta"
  say "tag $t -> $d_meta"
done
say "tags/list: $(curl -s "$reg/v2/$repo/tags/list")"

say '-- 4. the pre-push guard against this registry'
probe_tag "$reg" "$repo" "$version"
say "HEAD $repo:$version: $verdict (exit $verdict_rc, http $code): the workflow would refuse to push"
[ "$verdict" = present ] || fail "expected present for $version"
probe_tag "$reg" "$repo" 9.9.9
say "HEAD $repo:9.9.9: $verdict (exit $verdict_rc, http $code): the workflow would proceed"
[ "$verdict" = absent ] || fail 'expected absent for 9.9.9'
probe_tag http://127.0.0.1:1 "$repo" "$version"
say "HEAD against a closed port: $verdict (exit $verdict_rc, curl $curl_rc): the workflow would stop, not push"
[ "$verdict" = unknown ] || fail 'expected unknown for a closed port'

say '-- 5. tags move, digests do not'
say "a second push to $repo:$version, which the guard above refuses in the workflow; here it shows what a moved tag does"
echo 'knarr release dry run: second push' > "$ctx/stand-in.txt"
docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  --label "org.opencontainers.image.version=$version" --label 'org.opencontainers.image.title=second push' \
  --metadata-file "$work/metadata2.json" --tag "localhost:$port/$repo:$version" --push "$ctx" > "$work/build2.log" 2>&1 ||
  { tail -20 "$work/build2.log"; fail 'second buildx build --push failed'; }
d2=$(digest_of_metadata < "$work/metadata2.json") || fail 'no digest in metadata2.json'
printf "%-26s %s\n" "second push:" "$d2"
d_head2=$(head_digest "$reg" "$repo" "$version") || fail "no digest for $version after the second push"
printf "%-26s %s\n" "tag $version now ->" "$d_head2"
[ "$d_head2" = "$d2" ] || fail "tag $version does not resolve to the second push"
short=$(printf '%s' "$sha" | cut -c1-7)
d_sha=$(head_digest "$reg" "$repo" "sha-$short") || fail "no digest for sha-$short"
printf "%-26s %s\n" "tag sha-$short still ->" "$d_sha"
[ "$d_sha" = "$d_meta" ] || fail "sha-$short moved"
# shellcheck disable=SC2046  # image ids, one per word
docker image rm -f $(docker image ls -q "localhost:$port/$repo") > /dev/null 2>&1 || true
pull_rc=0; docker pull -q "localhost:$port/$repo@$d_meta" > /dev/null 2>&1 || pull_rc=$?
say "docker pull $repo@<first digest> after the tag moved: exit $pull_rc"
rc=0; v=$(tag_moved_verdict "$d_meta" "$d2" "$pull_rc") || rc=$?
say "verdict: $v (exit $rc)"
[ "$v" = moved ] || fail "expected moved, got $v"
say "labels on the image pulled by the first digest: $(docker image inspect "localhost:$port/$repo@$d_meta" --format '{{index .Config.Labels "org.opencontainers.image.version"}} {{index .Config.Labels "org.opencontainers.image.revision"}} / {{index .Config.Labels "org.opencontainers.image.title"}}')"

say '-- 6. a real pull by tag, after removing every local copy'
# shellcheck disable=SC2046  # image ids, one per word
docker image rm -f $(docker image ls -q "localhost:$port/$repo") > /dev/null 2>&1 || true
docker pull -q "localhost:$port/$repo:$version" > /dev/null
say "docker pull $repo:$version: RepoDigests $(docker image inspect "localhost:$port/$repo:$version" --format '{{join .RepoDigests " "}}' | sed "s|localhost:$port/||g"), title: $(docker image inspect "localhost:$port/$repo:$version" --format '{{index .Config.Labels "org.opencontainers.image.title"}}')"
say "arch of the pulled image: $(docker image inspect "localhost:$port/$repo:$version" --format '{{.Os}}/{{.Architecture}}')"
say "digest=$d_meta"
