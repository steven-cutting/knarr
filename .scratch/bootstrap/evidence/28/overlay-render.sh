#!/bin/sh
# Ticket 28 evidence: the designed release overlay (overlay/) renders and
# validates against the vendored schemas, first as committed (placeholder
# digest), then with the digest registry.sh pushed. The second render is what
# ticket 37 installs, apart from the digest. The diff against the base render
# shows that the overlay changes the image reference and the pull policy and
# nothing else: the Role's rules stay empty and no token is mounted.
# Needs the cluster pixi environment (kustomize; `just cluster-install`) and
# kubeconform from .tools/bin (`just initialize`). Offline.
# Usage: sh overlay-render.sh <empty-work-dir> <sha256:digest>
# The gate runs shellcheck without -x, so it cannot see digest_re in lib.sh.
# shellcheck disable=SC2154
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=${1:?usage: overlay-render.sh <empty-work-dir> <sha256:digest>}
digest=${2:?usage: overlay-render.sh <empty-work-dir> <sha256:digest>}
work=$(work_dir "$work")
printf '%s\n' "$digest" | grep -qE "^$digest_re$" || fail "not a digest: $digest"
root=$(cd "$here/../../../.." && pwd)
PATH=$root/.pixi/envs/cluster/bin:$root/.tools/bin:$PATH
command -v kustomize > /dev/null || { echo 'kustomize is missing: run just cluster-install' >&2; exit 2; }
command -v kubeconform > /dev/null || { echo 'kubeconform is missing: run just initialize' >&2; exit 2; }
schemas=$root/scripts/schemas/kubernetes
say() { printf '%s\n' "$*"; }
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
say "kustomize $(kustomize version), kubeconform $(kubeconform -v)"

validate() { # rendered yaml: the kubeconform summary, asserted
  s=$(kubeconform -strict -summary -schema-location "$schemas/{{.ResourceKind}}{{.KindSuffix}}.json" < "$1" 2>&1 | tail -1)
  say "kubeconform: $s"
  [ "$s" = 'Summary: 3 resources found parsing stdin - Valid: 3, Invalid: 0, Errors: 0, Skipped: 0' ] || fail "kubeconform did not validate all three resources of $1"
}
field() { # rendered yaml, regex: the matching lines, trimmed
  grep -E "$2" "$1" | sed -E 's/^ *(- )?//' | sort -u | tr '\n' ';' | sed 's/;$//'
}

say '-- the base, for comparison'
kustomize build "$root/deploy/base" > "$work/base.yaml"
validate "$work/base.yaml"
say "$(field "$work/base.yaml" '^ *(- )?image:'); $(field "$work/base.yaml" 'imagePullPolicy:')"

say '-- the committed overlay (placeholder digest)'
kustomize build "$here/overlay" > "$work/committed.yaml"
validate "$work/committed.yaml"
say "$(field "$work/committed.yaml" '^ *(- )?image:')"
[ "$(field "$work/committed.yaml" '^ *(- )?image:')" = 'image: ghcr.io/steven-cutting/knarr@sha256:0000000000000000000000000000000000000000000000000000000000000000' ] || fail 'the committed overlay does not pin the placeholder digest'

say "-- the overlay with the dry run's digest"
mkdir -p "$work/render/base" "$work/render/release"
cp "$root/deploy/base/kustomization.yaml" "$root/deploy/base/resources.json" "$work/render/base/"
sed -e 's|^  - \.\./\.\./\.\./\.\./\.\./deploy/base$|  - ../base|' -e "s|digest: sha256:0*$|digest: $digest|" "$here/overlay/kustomization.yaml" > "$work/render/release/kustomization.yaml"
cp "$here/overlay/pull-policy.yaml" "$work/render/release/"
grep -q "digest: $digest" "$work/render/release/kustomization.yaml" || fail 'the digest was not substituted'
kustomize build "$work/render/release" > "$work/release.yaml"
validate "$work/release.yaml"
say "$(field "$work/release.yaml" '^ *(- )?image:')"
[ "$(field "$work/release.yaml" '^ *(- )?image:')" = "image: ghcr.io/steven-cutting/knarr@$digest" ] || fail 'the rendered image is not pinned by the given digest'
say "$(field "$work/release.yaml" 'imagePullPolicy:')"
[ "$(field "$work/release.yaml" 'imagePullPolicy:')" = 'imagePullPolicy: IfNotPresent' ] || fail 'pull policy is not IfNotPresent'
say "Role $(awk '/^kind: Role$/ { r = 1 } r && /^rules:/ { print; exit }' "$work/release.yaml")"
grep -qE '^rules: \[\]$' "$work/release.yaml" || fail 'the Role is not the empty base Role'
say "$(field "$work/release.yaml" 'automountServiceAccountToken:') (ServiceAccount and pod)"
[ "$(grep -c 'automountServiceAccountToken: false' "$work/release.yaml")" -eq 2 ] || fail 'the token is mounted somewhere'
say '-- diff base -> release render (the overlay changes exactly these lines)'
diff "$work/base.yaml" "$work/release.yaml" > "$work/render.diff" && fail 'the overlay changed nothing' || true
sed 's/^/  /' "$work/render.diff"
[ "$(grep -cE '^[<>]' "$work/render.diff")" -eq 4 ] || fail 'the overlay changed more than the image and the pull policy'
