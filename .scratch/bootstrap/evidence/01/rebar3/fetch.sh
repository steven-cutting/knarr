#!/bin/sh
# Ticket 01 evidence, Verify 3: fetch the pinned rebar3 escript into <bin-dir>,
# refuse it unless its sha256 matches the pin, and, when gh is installed and
# authenticated, verify its Sigstore bundle against erlang/rebar3's publish
# workflow. The pin below is what 03's pin list carries.
# Usage: sh rebar3/fetch.sh <bin-dir>
set -eu
version=3.27.1
sha256=708407032479514dd68b581a0b09a68b5a781fb6f53dcf4ad81ce4ef6b92940f
bin=${1:?usage: fetch.sh <bin-dir>}
url=https://github.com/erlang/rebar3/releases/download/$version/rebar3
mkdir -p "$bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --proto '=https' -o "$tmp/rebar3" "$url"
if command -v sha256sum >/dev/null; then got=$(sha256sum "$tmp/rebar3" | cut -d' ' -f1); else got=$(shasum -a 256 "$tmp/rebar3" | cut -d' ' -f1); fi
[ "$got" = "$sha256" ] || { printf 'rebar3 %s: sha256 %s, want %s\n' "$version" "$got" "$sha256" >&2; exit 1; }
printf 'rebar3 %s sha256 %s: matches pin\n' "$version" "$got"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  curl -fsSL --proto '=https' -o "$tmp/rebar3.sigstore.json" "$url.sigstore"
  gh attestation verify "$tmp/rebar3" --bundle "$tmp/rebar3.sigstore.json" --repo erlang/rebar3 \
    --signer-workflow erlang/rebar3/.github/workflows/publish.yml --source-ref "refs/tags/$version" \
    --format json --jq '.[0].verificationResult.signature.certificate | "sigstore: signed by \(.buildSignerURI)"'
  # The same bundle must refuse a copy with one byte appended.
  cp "$tmp/rebar3" "$tmp/tampered"; printf x >> "$tmp/tampered"
  if gh attestation verify "$tmp/tampered" --bundle "$tmp/rebar3.sigstore.json" --repo erlang/rebar3 >/dev/null 2>&1; then
    echo 'sigstore: a tampered copy verified' >&2; exit 1
  fi
  echo 'sigstore: a copy with one byte appended is refused'
else
  echo 'sigstore: skipped (gh not installed or not authenticated); the sha256 pin is the check'
fi
mv "$tmp/rebar3" "$bin/rebar3"
chmod 0755 "$bin/rebar3"
