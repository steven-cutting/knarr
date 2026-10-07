#!/bin/sh
# Ticket 01 evidence, Verify 4: for every tool conda-forge lacks, download the
# pinned release asset for linux-64 and osx-arm64, compute its sha256, and
# require it to match both GitHub's recorded asset digest and the publisher's
# checksum file where one exists. On an osx-arm64 host, runs each macOS binary
# once to print its version. Prints the pin list 03 copies. Needs curl and gh.
# Usage: sh tools.sh <empty-work-dir> > tools.txt 2>&1
set -eu
work=${1:?usage: tools.sh <empty-work-dir>}
mkdir -p "$work"
printf 'date: %s\nhost: %s\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)"
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
# name version repo tag checksum-file linux-64-asset osx-arm64-asset member
pins='
rebar3 3.27.1 erlang/rebar3 3.27.1 - rebar3 rebar3 rebar3
kubeconform 0.8.0 yannh/kubeconform v0.8.0 CHECKSUMS kubeconform-linux-amd64.tar.gz kubeconform-darwin-arm64.tar.gz kubeconform
hadolint 2.15.1 hadolint/hadolint v2.15.1 checksums.sha256 hadolint-linux-x86_64 hadolint-macos-arm64 -
ripsecrets 0.1.11 sirwart/ripsecrets v0.1.11 - ripsecrets-0.1.11-x86_64-unknown-linux-gnu.tar.gz ripsecrets-0.1.11-aarch64-apple-darwin.tar.gz ripsecrets
editorconfig-checker 4.0.2 editorconfig-checker/editorconfig-checker v4.0.2 checksums.txt editorconfig-checker-linux-amd64.tar.gz editorconfig-checker-darwin-all.tar.gz editorconfig-checker
kwok 0.8.0 kubernetes-sigs/kwok v0.8.0 - kwok-linux-amd64 kwok-darwin-arm64 -
kwokctl 0.8.0 kubernetes-sigs/kwok v0.8.0 - kwokctl-linux-amd64 kwokctl-darwin-arm64 -
k3d 5.9.0 k3d-io/k3d v5.9.0 checksums.txt k3d-linux-amd64 k3d-darwin-arm64 -
setup-envtest 0.25.2 kubernetes-sigs/controller-runtime v0.25.2 - setup-envtest-linux-amd64 setup-envtest-darwin-arm64 -
'
fail=0
list=$work/pins.txt; : > "$list"
printf '%s\n' "$pins" > "$work/pins.in"
while read -r name version repo tag sums linux mac member; do
  [ -n "$name" ] || continue
  d=$work/$name; mkdir -p "$d"
  base=https://github.com/$repo/releases/download/$tag
  gh release view "$tag" -R "$repo" --json assets --jq '.assets[] | "\(.name) \(.digest)"' > "$d/digests"
  [ "$sums" = - ] || curl -fsSL --proto '=https' -o "$d/$sums" "$base/$sums"
  for pa in "linux-64 $linux" "osx-arm64 $mac"; do
    platform=${pa%% *}; asset=${pa#* }
    mkdir -p "$d/$platform"
    curl -fsSL --proto '=https' -o "$d/$platform/$asset" "$base/$asset"
    # shellcheck disable=SC2218  # false positive in 0.11.0: sha is defined above
    got=$(sha "$d/$platform/$asset")
    gh_digest=$(awk -v a="$asset" '$1==a{sub("sha256:","",$2); print $2}' "$d/digests")
    if [ "$gh_digest" = null ] && [ "$sums" = - ] && [ "$name" = ripsecrets ]; then
      # v0.1.11 (2025-05-27) predates GitHub's asset digests and publishes no
      # checksum file, so this sha256 is a first-use pin: it was computed here.
      src='nothing upstream: first-use pin computed here'
    elif [ "$got" != "$gh_digest" ]; then
      printf 'FAIL %s %s: sha256 %s, GitHub digest %s\n' "$name" "$asset" "$got" "$gh_digest"; exit 1
    elif [ "$sums" = - ]; then src='matches GitHub asset digest; no checksum file published'; else
      pub=$(awk -v a="$asset" '{f=$2; sub("^\\*","",f); sub("^.*/","",f)} f==a{print $1}' "$d/$sums")
      [ "$got" = "$pub" ] || { printf 'FAIL %s %s: sha256 %s, %s says %s\n' "$name" "$asset" "$got" "$sums" "$pub"; exit 1; }
      src="matches GitHub asset digest and $sums"
    fi
    printf 'ok   %-21s %-7s %-10s %s\n     sha256 %s  (%s)\n' "$name" "$version" "$platform" "$asset" "$got" "$src"
    printf '%s %s %s %s/%s %s %s\n' "$name" "$version" "$platform" "$base" "$asset" "$got" "$member" >> "$list"
    if [ "$platform" = osx-arm64 ] && [ "$(uname -sm)" = 'Darwin arm64' ]; then
      x=$d/$platform/x; mkdir -p "$x"
      case $asset in
        *.tar.gz) tar -xzf "$d/$platform/$asset" -C "$x"; bin=$(find "$x" -type f -name "$member" | head -1);;
        *) cp "$d/$platform/$asset" "$x/$name"; bin=$x/$name;;
      esac
      chmod +x "$bin"
      case $name in
        rebar3) v=$(printf '(skipped: an escript; rebar3/run.sh runs it)');;
        kubeconform) v=$("$bin" -v 2>&1);;
        kwok|kwokctl) v=$("$bin" --version 2>&1);;
        setup-envtest) v=$("$bin" --help 2>&1 | head -1 | sed 's|^Usage: [^ ]*/|Usage: |');;
        k3d) v=$("$bin" version 2>&1 | head -1);;
        *) v=$("$bin" --version 2>&1 | head -1);;
      esac
      printf '     runs: %s\n' "$v"
    fi
  done
done < "$work/pins.in"
echo
echo '== Cluster Autoscaler: no binary assets; images only, pinned by digest'
for tag in cluster-autoscaler-1.35.2 cluster-autoscaler-1.36.1; do
  n=$(gh release view "$tag" -R kubernetes/autoscaler --json assets --jq '.assets | length')
  printf '%s: %s release assets\n' "$tag" "$n"
  [ "$n" -eq 0 ] || fail=1
done
for v in v1.35.2 v1.36.1; do
  img=registry.k8s.io/autoscaling/cluster-autoscaler:$v
  dig=$(docker buildx imagetools inspect "$img" --format '{{json .Manifest.Digest}}' | tr -d '"')
  printf '%s@%s\n' "$img" "$dig"
  case $dig in sha256:*) ;; *) fail=1;; esac
done
echo
echo '== pin list (name version platform url sha256 member)'
cat "$list"
exit "$fail"
