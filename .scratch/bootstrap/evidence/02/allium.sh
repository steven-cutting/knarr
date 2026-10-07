#!/bin/sh
# Ticket 02 evidence: the Allium binary moves from biscuit_games_tooling's
# installer to 0003's tools.txt. Downloads allium-tools 3.6.1 for linux-64 and
# osx-arm64 and requires each sha256 to match both the checksum v0.3.0's
# install_allium.py carried and GitHub's recorded asset digest. Lists each
# archive, extracts only its `allium` member, runs the macOS one on an
# osx-arm64 host, and prints the two tools.txt lines. Needs curl and gh.
# Exits non-zero on any unexpected result.
# Usage: sh allium.sh <empty-work-dir> > allium.txt 2>&1
set -eu
work=${1:?usage: allium.sh <empty-work-dir>}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
repo=juxt/allium-tools version=3.6.1
base=https://github.com/$repo/releases/download/v$version
printf 'date: %s\nhost: %s\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)"

# platform, release target, the CHECKSUMS entry in biscuit_games_tooling v0.3.0
# src/biscuit_games_tooling/install_allium.py
carried='
linux-64 x86_64-unknown-linux-gnu e00c99ae234b10207719257a70e7c2dcad73060864468cd293fb7ad40524e970
osx-arm64 aarch64-apple-darwin ecfae02fcf8e60475a014944183158ccde4104f6f0223e1bf91f98519fcb19eb
'
gh release view "v$version" -R "$repo" --json assets --jq '.assets[] | "\(.name) \(.digest)"' > "$work/digests"
curl -fsSL --proto '=https' -o "$work/SHA256SUMS.txt" "$base/SHA256SUMS.txt"
: > "$work/lines"
printf '%s\n' "$carried" > "$work/carried"
while read -r platform target want; do
  [ -n "$platform" ] || continue
  asset=allium-$target.tar.gz
  d=$work/$platform; mkdir -p "$d/download" "$d/bin"
  curl -fsSL --proto '=https' -o "$d/download/$asset" "$base/$asset"
  got=$(sha "$d/download/$asset")
  digest=$(awk -v a="$asset" '$1==a{sub("sha256:","",$2); print $2}' "$work/digests")
  [ "$got" = "$want" ] || fail "$asset: sha256 $got, v0.3.0 carried $want"
  [ "$got" = "$digest" ] || fail "$asset: sha256 $got, GitHub digest $digest"
  if grep -q "$asset" "$work/SHA256SUMS.txt"; then sums='listed in SHA256SUMS.txt'; else sums='not in SHA256SUMS.txt'; fi
  printf 'ok   %-10s %s\n     sha256 %s\n     (matches v0.3.0 install_allium.py and the GitHub asset digest; %s)\n' \
    "$platform" "$asset" "$got" "$sums"
  printf '     members: %s\n' "$(tar -tzf "$d/download/$asset" | tr '\n' ' ')"
  # The one member only, as install_allium.py read it.
  tar -xzf "$d/download/$asset" -C "$d/bin" allium
  [ -f "$d/bin/allium" ] || fail "$asset has no allium member"
  if [ "$platform" = osx-arm64 ] && [ "$(uname -sm)" = 'Darwin arm64' ]; then
    v=$("$d/bin/allium" --version)
    printf '     runs: %s\n' "$v"
    # run_allium reads the second field of --version against the pin.
    [ "$(printf '%s\n' "$v" | awk '{print $2}')" = "$version" ] || fail "allium --version says $v"
  fi
  printf 'allium %s %s %s/%s %s allium\n' "$version" "$platform" "$base" "$asset" "$got" >> "$work/lines"
done < "$work/carried"

echo
echo '== SHA256SUMS.txt covers only these (why v0.3.0 hashed the binaries itself)'
sed 's/^[0-9a-f]* *//' "$work/SHA256SUMS.txt"
echo
echo '== newest allium-tools releases (07 may move the pin)'
gh release list -R "$repo" -L 3
latest=$(gh release view -R "$repo" --json tagName --jq .tagName)
[ "$latest" = "v$version" ] || fail "the newest release is $latest, not v$version; 0004's pin needs a deliberate move"
echo
echo '== tools.txt lines (name version platform url sha256 member)'
cat "$work/lines"
