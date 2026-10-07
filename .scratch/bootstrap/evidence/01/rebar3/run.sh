#!/bin/sh
# Ticket 01 evidence, Verify 3: with the pixi environment and the fetched rebar3
# on PATH, build and run the probe, whose prometheus and ddskerl dependencies
# build with rebar3. Fails unless rebar3 compiled them and the counter reads 2.
# Usage: sh rebar3/run.sh <pixi-env-dir> <bin-dir-holding-rebar3> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
env=${1:?usage: run.sh <pixi-env-dir> <bin-dir> <work-dir>}
bin=${2:?usage: run.sh <pixi-env-dir> <bin-dir> <work-dir>}
work=${3:?usage: run.sh <pixi-env-dir> <bin-dir> <work-dir>}
PATH="$env/bin:$bin:$PATH"; export PATH
printf 'date: %s\nhost: %s\n%s\n%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" "$(gleam --version)" "$(rebar3 version)"
mkdir -p "$work"
cp -R "$here/probe/." "$work/"
cd "$work"
gleam build > build.log 2>&1 || { cat build.log; echo 'gleam build failed' >&2; exit 1; }
cat build.log
grep 'build_tools = \["rebar3"\]' manifest.toml | sed 's/, requirements.*//'
for app in prometheus ddskerl; do
  grep -q "^===> Compiling $app\$" build.log || { echo "rebar3 did not compile $app" >&2; exit 1; }
done
for app in prometheus ddskerl; do
  ls build/dev/erlang/$app/ebin/$app.app >/dev/null || { echo "$app was not compiled" >&2; exit 1; }
done
echo 'compiled: build/dev/erlang/{prometheus,ddskerl}/ebin'
out=$(gleam run 2>&1 | tail -1); echo "$out"
[ "$out" = 'prometheus counter after two inc: 2' ] || { echo 'probe did not run' >&2; exit 1; }
# Without rebar3 on PATH the same build fails, so the success above is rebar3's.
rm -rf build
PATH=$(printf '%s' "$PATH" | sed "s|$bin:||")
if command -v rebar3 >/dev/null; then echo "rebar3 still on PATH at $(command -v rebar3)" >&2; exit 1; fi
if gleam build >no-rebar3.log 2>&1; then echo 'built without rebar3' >&2; exit 1; fi
echo 'without rebar3 on PATH, gleam build fails:'; grep -i rebar no-rebar3.log | head -3
echo 'rebar3/run.sh: ok'
