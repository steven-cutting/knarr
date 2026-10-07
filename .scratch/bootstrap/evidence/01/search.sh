#!/bin/sh
# Ticket 01 evidence: confirm every conda-forge package and its newest version on
# both platforms. Prints one line per package and platform; exits non-zero if a
# package expected on conda-forge is missing or its newest version differs from
# the pin the decision record names.
# Usage: sh search.sh > search.txt
set -eu
expect='
gleam 1.19.0
erlang 29.1.1
just 1.58.0
prek 0.5.5
typos 1.51.1
lychee 0.24.2
taplo 0.10.0
markdownlint-cli2 0.23.3
actionlint 1.7.12
shellcheck 0.11.0
kubernetes-kind 0.33.0
kubernetes-client 1.34.3
kustomize 5.8.2
tilt 0.37.8
kubernetes-helm 4.3.0
'
# Not on conda-forge (or, for k3d, a different project of the same name).
absent='rebar3 kubeconform hadolint ripsecrets editorconfig-checker kwok setup-envtest cluster-autoscaler'
printf 'date: %s\npixi: %s\nhost: %s\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(pixi --version)" "$(uname -sm)"
fail=0
for platform in linux-64 osx-arm64; do
  printf '%s\n' "== $platform"
  printf '%s\n' "$expect" | while read -r name want; do
    [ -n "$name" ] || continue
    out=$(pixi search -c conda-forge -p "$platform" "$name" 2>&1) || { printf 'MISSING %s\n' "$name"; exit 1; }
    got=$(printf '%s\n' "$out" | sed -n 's/^Version[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
    build=$(printf '%s\n' "$out" | sed -n 's/^Build[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
    if [ "$got" = "$want" ]; then
      printf 'ok      %-20s %-10s build %s\n' "$name" "$got" "$build"
    else
      printf 'DIFFERS %-20s want %s got %s\n' "$name" "$want" "$got"; exit 1
    fi
  done || fail=1
  for name in $absent; do
    if out=$(pixi search -c conda-forge -p "$platform" "$name" 2>&1) && printf '%s' "$out" | grep -q '^Version'; then
      printf 'PRESENT %s (expected absent)\n%s\n' "$name" "$out"; fail=1
    else
      printf 'absent  %s\n' "$name"
    fi
  done
  # k3d exists, but it is a noarch Python package unrelated to k3d.io.
  out=$(pixi search -c conda-forge -p "$platform" k3d 2>&1)
  printf '%s\n' "-- k3d (conda-forge; not k3d.io's k3d):"
  printf '%s\n' "$out" | sed -n '/^Name/,/^Run exports/p' | grep -Ev '^(Size|Timestamp|File Name|URL|MD5|Run exports)'
  printf '%s\n' "$out" | grep -E '^Build[[:space:]]+py' >/dev/null || { printf 'k3d is no longer the noarch python package\n'; fail=1; }
  printf '\n'
done
exit "$fail"
