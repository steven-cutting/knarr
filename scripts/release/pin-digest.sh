#!/bin/sh
# Pins the release overlay to one image digest: replaces the one
# `digest: sha256:<64 hex>` line in deploy/release/kustomization.yaml and
# prints the image reference the overlay renders, which must be
# ghcr.io/steven-cutting/knarr@<digest>. It pins and renders a copy of deploy/
# first, so a failed render or a wrong reference leaves the overlay as it was.
# Ticket 37 runs it as `just release-pin <digest>` with the digest release.yml
# prints in its run summary. It writes a tracked file, so it is outside
# `just check`. It uses sed, not `kustomize edit set image`, which rewrites the
# file without its comments. Needs kustomize on PATH (`just cluster-install`).
# Usage: sh scripts/release/pin-digest.sh sha256:<64 hex>
# The gate runs shellcheck without -x, so it cannot see digest_re in lib.sh.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
image=ghcr.io/steven-cutting/knarr
deploy=$(cd "$here/../../deploy" && pwd)
file=$deploy/release/kustomization.yaml
digest=${1:-}

# One line of exactly sha256: and 64 hex digits: grep alone passes a value
# whose first line is a digest and whose later lines are anything.
{ [ ${#digest} -eq 71 ] && printf '%s\n' "$digest" | grep -qE "^$digest_re$"; } || {
  echo "not a digest: '$digest' (want sha256: and 64 lower-case hex digits)" >&2
  exit 2
}
lines=$(grep -cE "^ *digest: $digest_re$" "$file" || true)
[ "$lines" = 1 ] || { echo "$file has $lines digest lines, not one: fix it by hand" >&2; exit 1; }
command -v kustomize > /dev/null || { echo 'kustomize is missing: run just cluster-install' >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "${work:?}"' EXIT
trap 'exit 1' HUP INT TERM
cp -R "$deploy" "$work/deploy"
sed -E "s/^( *digest: )$digest_re\$/\1$digest/" "$file" > "$work/deploy/release/kustomization.yaml"
render=$(kustomize build "$work/deploy/release")
pinned=$(printf '%s\n' "$render" | sed -nE 's/^ *(- )?image: //p')
printf '%s\n' "$pinned"
[ "$pinned" = "$image@$digest" ] || {
  echo "the pinned overlay renders '$pinned', not $image@$digest; $file is unchanged" >&2
  exit 1
}
cp "$work/deploy/release/kustomization.yaml" "$file" # cp keeps the file's mode
