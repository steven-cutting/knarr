#!/bin/sh
# Ticket 01 evidence, Verify 5: does gleam fail, or rewrite manifest.toml, when
# gleam.toml and the manifest disagree? For each edit to the probe's gleam.toml,
# runs each command in a fresh copy and records its exit code and whether
# manifest.toml changed. Then shows the workaround: a before-and-after
# comparison (git diff --exit-code manifest.toml) catches every rewrite, and a
# pre-check that compares the two files' requirement tables refuses every
# disagreeing pair before gleam runs, without writing.
# Usage: sh manifest/run.sh <pixi-env-dir> <bin-dir-holding-rebar3> <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
probe=$here/../rebar3/probe
env=${1:?usage: run.sh <pixi-env-dir> <bin-dir> <work-dir>}
bin=${2:?usage: run.sh <pixi-env-dir> <bin-dir> <work-dir>}
work=${3:?usage: run.sh <pixi-env-dir> <bin-dir> <work-dir>}
PATH="$env/bin:$bin:$PATH"; export PATH
printf 'date: %s\nhost: %s\n%s\n\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$(uname -sm)" "$(gleam --version)"
echo '== flags: no locked/frozen/offline option on build, check, deps download or update'
for c in build check 'deps download' update test run; do
  # shellcheck disable=SC2086
  flags=$(gleam $c --help | grep -oE -- '--[a-z-]+' | sort -u | tr '\n' ' ')
  printf '%-14s %s\n' "$c" "$flags"
  # shellcheck disable=SC2086
  if gleam $c --help | grep -qiE -- '--(locked|frozen|offline|no-update)'; then echo "gleam $c has a lock flag; revisit" >&2; exit 1; fi
done
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  # Every changelog up to the pinned release, searched for a flag that would
  # keep manifest.toml read-only.
  v=$(gleam --version | cut -d' ' -f2)
  log=$(mktemp)
  gh api -H 'Accept: application/vnd.github.raw' "repos/gleam-lang/gleam/contents/CHANGELOG.md?ref=v$v" > "$log"
  for f in $(gh api "repos/gleam-lang/gleam/contents/changelog?ref=v$v" --jq '.[].name'); do
    gh api -H 'Accept: application/vnd.github.raw' "repos/gleam-lang/gleam/contents/changelog/$f?ref=v$v" >> "$log"
  done
  hits=$(grep -cE -- '--(frozen|locked|offline|no-update)' "$log" || true)
  printf 'changelogs to v%s (%s lines): %s mentions of --frozen, --locked, --offline or --no-update\n' "$v" "$(wc -l < "$log" | tr -d ' ')" "$hits"
  rm -f "$log"
  [ "$hits" -eq 0 ] || { echo 'a changelog mentions a lock flag; revisit' >&2; exit 1; }
else
  echo 'changelogs: skipped (gh not installed or not authenticated)'
fi
tables() { # dir: write the three JSON inputs taplo extracts
  for t in dependencies dev_dependencies; do taplo get -f "$1/gleam.toml" -o json "$t" 2>/dev/null > "$1/$t.json" || echo '{}' > "$1/$t.json"; done
  taplo get -f "$1/manifest.toml" -o json requirements > "$1/requirements.json" 2>/dev/null || echo '{}' > "$1/requirements.json"
}
sum() { if command -v sha256sum >/dev/null; then sha256sum manifest.toml; else shasum -a 256 manifest.toml; fi | cut -d' ' -f1; }
mkdir -p "$work"
seed=$work/seed
cp -R "$probe" "$seed"
(cd "$seed" && gleam deps download >/dev/null 2>&1)   # warm the hex cache once
edit_none() { :; }
edit_widen() { sed 's/^prometheus = .*/prometheus = ">= 6.0.0 and < 7.0.0"/' gleam.toml > t && mv t gleam.toml; }
edit_remove() { sed '/^prometheus = /d' gleam.toml > t && mv t gleam.toml; }
edit_add() { printf 'gleam_json = ">= 3.0.0 and < 4.0.0"\n' >> gleam.toml; }
edit_manifest() { sed 's/^prometheus = { version = .*/prometheus = { version = ">= 6.1.0 and < 7.0.0" }/' manifest.toml > t && mv t manifest.toml; }
printf '\n== %-44s %-16s %-6s %s\n' 'edit' 'command' 'exit' 'manifest.toml'
rewrites=0
for e in none widen remove add manifest; do
  case $e in
    none) label='none (agreeing files)';;
    widen) label='gleam.toml: widen prometheus range';;
    remove) label='gleam.toml: drop prometheus';;
    add) label='gleam.toml: add gleam_json';;
    manifest) label='manifest.toml: stale [requirements]';;
  esac
  for c in check build 'deps download'; do
    d=$work/$e-$(printf '%s' "$c" | tr ' ' -)
    cp -R "$seed" "$d"
    ( cd "$d"
      "edit_$e"
      before=$(sum)
      set +e
      # shellcheck disable=SC2086
      gleam $c >run.log 2>&1; rc=$?
      set -e
      if [ "$(sum)" = "$before" ]; then w=unchanged; else w=REWRITTEN; fi
      printf '   %-44s %-16s %-6s %s\n' "$label" "gleam $c" "$rc" "$w"
      [ "$e" = none ] && [ "$w" != unchanged ] && { echo 'agreeing files rewrote manifest' >&2; exit 1; }
      [ "$w" = REWRITTEN ] && echo "$e $c" >> "$work/rewrites"
      true )
  done
done
[ -s "$work/rewrites" ] && rewrites=$(wc -l < "$work/rewrites" | tr -d ' ')
printf '\n%s command runs rewrote manifest.toml and exited 0\n' "$rewrites"
echo
echo '== diff from the "add gleam_json" build (what a gate would see)'
diff "$seed/manifest.toml" "$work/add-build/manifest.toml" || true
echo
echo '== workaround: git diff --exit-code manifest.toml after the build'
g=$work/git
cp -R "$seed" "$g"
cd "$g"
git init -q && git add gleam.toml manifest.toml src && git -c user.name=t -c user.email=t@t commit -qm seed
edit_add
gleam build >/dev/null 2>&1 && echo 'gleam build: exit 0'
if git diff --quiet --exit-code manifest.toml; then echo 'workaround missed the rewrite' >&2; exit 1; fi
echo 'git diff --exit-code manifest.toml: exit 1 (drift caught)'
git checkout -q manifest.toml gleam.toml
gleam build >/dev/null 2>&1
git diff --quiet --exit-code manifest.toml && echo 'agreeing files: git diff --exit-code manifest.toml exit 0'
echo
echo '== pre-check before gleam runs: requirements_check.escript, nothing written'
for e in none widen remove add manifest; do
  d=$work/pre-$e
  cp -R "$seed" "$d"
  (cd "$d" && "edit_$e")
  before=$(cd "$d" && sum)
  tables "$d"
  set +e
  out=$(escript "$here/requirements_check.escript" "$d/dependencies.json" "$d/dev_dependencies.json" "$d/requirements.json" 2>&1); rc=$?
  set -e
  [ "$(cd "$d" && sum)" = "$before" ] || { echo 'pre-check wrote manifest.toml' >&2; exit 1; }
  printf '   %-10s exit %s  %s\n' "$e" "$rc" "$(printf '%s' "$out" | head -1)"
  if [ "$e" = none ]; then [ "$rc" -eq 0 ] || exit 1; else [ "$rc" -eq 1 ] || { echo "pre-check missed $e" >&2; exit 1; }; fi
done
echo 'manifest/run.sh: ok'
