#!/bin/sh
# Install the host platform's tools.txt pins into a tool directory (Decision
# 0003, "Escape hatch"). Each download is refused unless its sha256 matches the
# pin; a refused download never replaces an installed binary. An installed pin
# is recorded beside the binary, so a rerun with unchanged pins skips the
# download and works offline. A tool installed here whose lines are gone is
# removed with its record, so a dropped pin leaves nothing on PATH; a binary
# with no record was never installed here and is left alone. rebar3's Sigstore
# bundle is verified as well when gh is installed and authenticated; without gh
# the sha256 is the check.
# Usage: sh scripts/install-tools.sh <tools.txt> <bin-dir>
set -eu
pins=${1:?usage: install-tools.sh <tools.txt> <bin-dir>}
bin=${2:?usage: install-tools.sh <tools.txt> <bin-dir>}

case $(uname -sm) in
  'Darwin arm64') host=osx-arm64 ;;
  'Linux x86_64') host=linux-64 ;;
  *) printf 'install-tools: tools.txt pins no tools for %s\n' "$(uname -sm)" >&2; exit 2 ;;
esac
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

stamps=$bin/.pins
mkdir -p "$stamps"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Read every line first, so a malformed file is refused before anything runs.
sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$pins" > "$tmp/pins"
while read -r name version platform url want member extra; do
  if [ -z "$member" ] || [ -n "$extra" ]; then
    printf 'install-tools: malformed line for %s in %s\n' "$name" "$pins" >&2; exit 2
  fi
done < "$tmp/pins"

while read -r name version platform url want member; do
  [ "$platform" = "$host" ] || continue
  line="$name $version $platform $url $want $member"
  if [ -x "$bin/$name" ] && [ "$(cat "$stamps/$name" 2> /dev/null)" = "$line" ]; then
    printf 'ok   %s %s already installed\n' "$name" "$version"
    continue
  fi
  work=$tmp/$name
  mkdir -p "$work"
  # https for every committed pin; file:// lets the tests serve pins locally.
  # A redirect may only go to https.
  curl -fsSL --proto '=https,file' --proto-redir '=https' -o "$work/download" "$url" ||
    { printf 'install-tools: could not download %s %s from %s\n' "$name" "$version" "$url" >&2; exit 1; }
  got=$(sha "$work/download")
  if [ "$got" != "$want" ]; then
    printf 'install-tools: %s %s sha256 %s, pin %s; refusing it\n' "$name" "$version" "$got" "$want" >&2
    exit 1
  fi
  if [ "$name" = rebar3 ] && command -v gh > /dev/null && gh auth status > /dev/null 2>&1; then
    curl -fsSL --proto '=https' -o "$work/bundle.json" "$url.sigstore"
    gh attestation verify "$work/download" --bundle "$work/bundle.json" --repo erlang/rebar3 \
      --signer-workflow erlang/rebar3/.github/workflows/publish.yml --source-ref "refs/tags/$version" > /dev/null ||
      { printf 'install-tools: rebar3 %s failed Sigstore verification\n' "$version" >&2; exit 1; }
    printf '     rebar3 %s Sigstore bundle verified\n' "$version"
  fi
  case $url in
    *.tar.gz)
      mkdir "$work/x"
      tar -xzf "$work/download" -C "$work/x"
      find "$work/x" -type f -name "$member" > "$work/found"
      if [ "$(wc -l < "$work/found" | tr -d ' ')" != 1 ]; then
        printf 'install-tools: %s %s archive holds %s files named %s, want 1\n' \
          "$name" "$version" "$(wc -l < "$work/found" | tr -d ' ')" "$member" >&2
        exit 1
      fi
      file=$(cat "$work/found") ;;
    *) file=$work/download ;;
  esac
  chmod 0755 "$file"
  mv -f "$file" "$bin/$name"
  printf '%s\n' "$line" > "$stamps/$name"
  printf 'ok   %s %s installed (sha256 matches the pin)\n' "$name" "$version"
done < "$tmp/pins"

for stamp in "$stamps"/*; do
  [ -f "$stamp" ] || continue
  name=${stamp##*/}
  awk -v name="$name" -v host="$host" '$1 == name && $3 == host { found = 1 } END { exit !found }' "$tmp/pins" && continue
  rm -f "${bin:?}/$name" "$stamp"
  printf 'ok   removed %s (tools.txt no longer pins it for %s)\n' "$name" "$host"
done
