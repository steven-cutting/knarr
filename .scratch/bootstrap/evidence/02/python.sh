#!/bin/sh
# Ticket 02 evidence: the Python stack the copied checkers need. Confirms the
# python, pytest and ruff pins on conda-forge for both platforms, solves 0003's
# manifest with and without them, reports what they add to the default
# environment, and proves the copied checkers' imports and the tools run through
# a PATH export alone. Exits non-zero on any unexpected result.
# Usage: sh python.sh <empty-work-dir> > python.txt 2>&1
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=${1:?usage: python.sh <empty-work-dir>}
mkdir -p "$work"; work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "work dir $work is not empty" >&2; exit 2; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
quiet() { log=$1; shift; "$@" > "$log" 2>&1 || { cat "$log"; fail "$*"; }; }
step() { printf '\n== %s\n' "$*"; }
# The pins 0004 adds to the default feature. python is held at 3.14: the bare
# newest on conda-forge is a 3.15 release candidate, and the upstream checkers
# declare requires-python >= 3.14.
# name, series searched (_ for the newest of any series), the pin.
pins='
python 3.14.* 3.14.8
pytest _ 9.1.1
ruff _ 0.16.10
'
printf 'date: %s\n%s\nhost: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(pixi --version)" "$(uname -sm)"

step 'conda-forge: each pin is the newest (python: the newest 3.14) on both platforms'
for platform in linux-64 osx-arm64; do
  printf '%s\n' "$pins" | while read -r name spec want; do
    [ -n "$name" ] || continue
    if [ "$spec" = _ ]; then query=$name; else query="$name $spec"; fi
    out=$(pixi search -c conda-forge -p "$platform" "$query" 2>&1) || fail "$query missing on $platform"
    got=$(printf '%s\n' "$out" | sed -n 's/^Version[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
    build=$(printf '%s\n' "$out" | sed -n 's/^Build[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
    [ "$got" = "$want" ] || fail "$name on $platform: want $want got $got"
    printf 'ok      %-9s %-7s %-10s build %s\n' "$platform" "$name" "$got" "$build"
  done
  bare=$(pixi search -c conda-forge -p "$platform" python 2>&1 | sed -n 's/^Version[[:space:]]*//p' | head -1)
  printf 'info    %-9s python newest of any series: %s (not pinned)\n' "$platform" "$bare"
done

step "solve 0003's manifest as proposed (base) and with the three pins (with-python)"
mkdir "$work/base" "$work/with-python"
cp "$here/../01/pixi.toml.proposed" "$work/base/pixi.toml"
# The three lines join the default feature directly after shellcheck.
awk '{print} /^shellcheck = /{print "python = \"==3.14.8\""; print "pytest = \"==9.1.1\""; print "ruff = \"==0.16.10\""}' \
  "$work/base/pixi.toml" > "$work/with-python/pixi.toml"
diff "$work/base/pixi.toml" "$work/with-python/pixi.toml" && fail 'the pins were not added' || true
for d in base with-python; do
  (cd "$work/$d" && quiet lock.log pixi lock && quiet install.log pixi install --locked)
  printf '%-12s solved both platforms; default installed\n' "$d"
done
for platform in linux-64 osx-arm64; do
  printf '%s: ' "$platform"
  (cd "$work/with-python" && pixi list -e default --platform "$platform" 2>/dev/null) \
    | awk '$1=="python"||$1=="pytest"||$1=="ruff"{printf "%s %s %s   ", $1, $2, $3}'
  echo
done

step 'default environment size on osx-arm64 (du -sk, as 01 measured with du)'
b=$(du -sk "$work/base/.pixi/envs/default" | cut -f1)
p=$(du -sk "$work/with-python/.pixi/envs/default" | cut -f1)
printf 'base %s MB, with-python %s MB, delta %s MB\n' "$((b / 1024))" "$((p / 1024))" "$(((p - b) / 1024))"

step 'the copied checkers need nothing beyond the standard library'
env=$work/with-python/.pixi/envs/default
PATH="$env/bin:$PATH"; export PATH
py=$(command -v python3)
[ "$py" = "$env/bin/python3" ] || fail "python3 resolved to $py, not the environment"
echo "python3 resolves to the environment through a PATH export alone: <work>${py#"$work"}"
python3 -I -c '
import hashlib, sys, tomllib
assert sys.version_info[:2] == (3, 14), sys.version
assert callable(hashlib.file_digest)
print("python", sys.version.split()[0], "tomllib ok, hashlib.file_digest ok")
'
pytest --version
ruff --version
echo 'python.sh: all checks passed'
