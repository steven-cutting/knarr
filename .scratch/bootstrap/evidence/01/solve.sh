#!/bin/sh
# Ticket 01 evidence: solve pixi.toml.proposed for both platforms, install every
# environment, show what activation would add, and prove which commands write
# pixi.lock on drift. Exits non-zero on any unexpected result.
# Usage: sh solve.sh <empty-work-dir> > solve.txt 2>&1
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=${1:?usage: solve.sh <empty-work-dir>}
mkdir -p "$work"
cd "$work"
[ -z "$(ls -A .)" ] || { echo "work dir $work is not empty" >&2; exit 2; }
cp "$here/pixi.toml.proposed" pixi.toml
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
sum() { if command -v sha256sum >/dev/null; then sha256sum pixi.lock; else shasum -a 256 pixi.lock; fi | cut -d' ' -f1; }
# Runs a command with its output in a log, failing (with the log) if it fails;
# a pipe into tail or grep would hide the exit status from set -e.
quiet() { log=$1; shift; "$@" > "$log" 2>&1 || { cat "$log"; fail "$*"; }; }
step() { printf '\n== %s\n' "$*"; }

printf 'date: %s\n%s\nhost: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(pixi --version)" "$(uname -sm)"

step 'pixi lock (both platforms, every environment)'
quiet lock.log pixi lock
grep -E '^(Platform|  \+ \(conda\) (erlang|openssl|gleam) )' lock.log || true
locked=$(sum); echo "pixi.lock sha256 $locked"
[ -n "$locked" ] || fail 'no pixi.lock to hash'

step 'pixi install --locked (no -e) installs the default environment only'
quiet install-default.log pixi install --locked; tail -1 install-default.log
envs=$(find .pixi/envs -mindepth 1 -maxdepth 1 -exec basename {} \; | tr '\n' ' ')
echo "installed: $envs"
[ "$envs" = 'default ' ] || fail "bare install --locked installed: $envs"

step 'pixi install --locked --all'
quiet install-all.log pixi install --locked --all; tail -1 install-all.log
[ "$(sum)" = "$locked" ] || fail 'install --locked changed pixi.lock'

step 'pixi lock --check on the fresh lock'
pixi lock --check || fail 'lock --check failed on a fresh lock'
pixi lock --check --offline --dry-run || fail 'lock --check --offline --dry-run failed on a fresh lock'
[ "$(sum)" = "$locked" ] || fail 'lock --check changed a fresh pixi.lock'
echo 'both pass; pixi.lock unchanged'

step 'one solve group: erlang and openssl are the same build in every environment'
for platform in linux-64 osx-arm64; do
  for env in default cluster runtime; do
    printf '%-9s %-9s ' "$platform" "$env"
    pixi list -e "$env" --platform "$platform" 2>/dev/null | awk '$1=="erlang"||$1=="openssl"{printf "%s %s %s   ", $1, $2, $3}'
    echo
  done
  n=$(for env in default cluster runtime; do pixi list -e "$env" --platform "$platform" 2>/dev/null | awk '$1=="erlang"||$1=="openssl"{print $1, $2, $3}'; done | sort -u | wc -l)
  [ "$n" -eq 2 ] || fail "erlang/openssl builds differ across environments on $platform"
done

step 'runtime environment, linux-64 (what the runtime image carries)'
pixi list -e runtime --platform linux-64

step 'default environment, osx-arm64'
pixi list -e default

step 'activation scripts (etc/conda/activate.d) per environment'
for env in default cluster runtime; do
  d=.pixi/envs/$env/etc/conda/activate.d
  printf '%s: ' "$env"; if [ -d "$d" ]; then find "$d" -mindepth 1 -maxdepth 1 -exec basename {} \; | tr '\n' ' '; echo; else echo '(none)'; fi
done

step 'variables pixi activation sets beyond PATH and CONDA_*/PIXI_* bookkeeping'
pixi shell-hook -e default --shell bash | grep '^export ' | grep -Ev '^export (PATH|CONDA_|PIXI_)' || echo '(none)'

step 'tools run by name through a PATH export alone (no pixi run, no activation)'
PATH="$work/.pixi/envs/default/bin:$PATH"
export PATH
gleam --version
erl -noshell -eval 'io:format("OTP ~s, erts ~s~n", [erlang:system_info(otp_release), erlang:system_info(version)]), halt().'
just --version; prek --version; typos --version; lychee --version; taplo --version 2>&1 | head -1
markdownlint-cli2 --help 2>&1 | head -1; actionlint --version | head -1; shellcheck --version | sed -n 2p
for b in kind kubectl kustomize tilt helm; do [ ! -e ".pixi/envs/default/bin/$b" ] || fail "$b leaked into the default env"; done
echo 'cluster binaries absent from default: ok'
CPATH="$work/.pixi/envs/cluster/bin"
"$CPATH/kind" version; "$CPATH/kubectl" version --client 2>&1 | head -1; "$CPATH/kustomize" version
"$CPATH/tilt" version; "$CPATH/helm" version --short
[ ! -e .pixi/envs/runtime/bin/gleam ] || fail 'gleam leaked into the runtime env'
echo 'runtime env holds erlang and no gleam: ok'

step 'drift: edit one pin (shellcheck ==0.11.0 -> ==0.10.0) and run each command'
cp pixi.toml pixi.toml.orig; cp pixi.lock pixi.lock.orig
sed 's/^shellcheck = "==0.11.0"/shellcheck = "==0.10.0"/' pixi.toml.orig > pixi.toml
grep -q '^shellcheck = "==0.10.0"' pixi.toml || fail 'pin edit did not apply'
try() { # label, command...; prints exit code and whether pixi.lock changed, then restores it
  label=$1; shift
  set +e; "$@" >/dev/null 2>&1; rc=$?; set -e
  if [ "$(sum)" = "$locked" ]; then w=unchanged; else w=REWRITTEN; fi
  printf '%-44s exit %-3s pixi.lock %s\n' "$label" "$rc" "$w"
  cp pixi.lock.orig pixi.lock
  last_rc=$rc last_w=$w
}
# Each row below is asserted, not only printed: 0003's lock-check command and
# its PATH-export rule rest on them, and a pixi release that changes one of
# them must fail this script so that 0003 is revisited.
try 'pixi lock --check'                       pixi lock --check
[ "$last_rc" -ne 0 ] && [ "$last_w" = REWRITTEN ] || fail 'plain lock --check no longer rewrites on drift; revisit 0003'
check_w=$last_w
try 'pixi lock --check --offline --dry-run'   pixi lock --check --offline --dry-run
[ "$last_rc" -ne 0 ] && [ "$last_w" = unchanged ] || fail 'dry-run lock check did not fail cleanly'
try 'pixi install --locked'                   pixi install --locked
[ "$last_rc" -ne 0 ] && [ "$last_w" = unchanged ] || fail 'install --locked did not refuse drift'
try 'pixi install --frozen'                   pixi install --frozen
[ "$last_rc" -eq 0 ] && [ "$last_w" = unchanged ] || fail 'install --frozen no longer installs a stale lock silently; revisit 0003'
try 'pixi run true'                           pixi run true
[ "$last_rc" -eq 0 ] && [ "$last_w" = REWRITTEN ] || fail 'pixi run no longer rewrites a stale lock; revisit 0003'
run_w=$last_w
try 'pixi run --frozen true'                  pixi run --frozen true
[ "$last_rc" -eq 0 ] && [ "$last_w" = unchanged ] || fail 'pixi run --frozen changed; revisit 0003'
cp pixi.toml.orig pixi.toml
printf 'plain lock --check on drift: pixi.lock %s; pixi run on drift: pixi.lock %s\n' "$check_w" "$run_w"

step 'commands confirmed in --help'
for c in install lock update run; do
  printf -- '-- pixi %s: %s\n' "$c" "$(pixi "$c" --help | sed -n 1p)"
  pixi "$c" --help | grep -E '^ +(-[a-z], )?(--(locked|frozen|all|check|dry-run|offline)\b|\[PACKAGES\])' -A1 | grep -v '^--$'
done
echo; echo 'solve.sh: all checks passed'
