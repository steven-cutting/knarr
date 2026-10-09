#!/bin/sh
# Ticket 28 evidence: how long the native linux/amd64 image build takes on
# GitHub's ubuntu-24.04 runners today, from the last twelve ci.yml runs' "Kind
# smoke" job: the whole job and its `just image-build` step, with the median
# over the steps that succeeded. A run that is queued, in progress or
# cancelled has null timestamps and is shown as such, never as a number.
# These are the only native build numbers available: the maintainer's host
# emulates amd64 (amd64-probe.sh). Read only, through gh.
# Needs gh (authenticated) and perl.
# Usage: sh ci-durations.sh <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=${1:?usage: ci-durations.sh <empty-work-dir>}
work=$(work_dir "$work")
repo=steven-cutting/knarr
job='Kind smoke'
step='Run just image-build'
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
runs=$(gh run list --repo "$repo" --workflow ci.yml --limit 12 --json databaseId,conclusion,createdAt,event,headBranch \
  --jq '.[] | "\(.databaseId) \(.conclusion) \(.createdAt) \(.event) \(.headBranch)"')
[ -n "$runs" ] || fail 'gh run list returned nothing'
printf 'runner: ubuntu-24.04 (ci.yml); job: %s; step: %s\n' "$job" "$step"
printf '%-12s %-21s %-13s %-28s %-9s %6s %6s\n' run created event branch job 'job s' 'step s'
# seconds <conclusion> <startedAt> <completedAt>: the duration, or "-" for
# anything that did not complete (null fields, or no conclusion yet).
seconds() { if [ "$1" != null ] && d=$(step_seconds "$2" "$3" 2> /dev/null); then printf '%s\n' "$d"; else echo -; fi; }
steps=$work/step-seconds.txt
: > "$steps"
printf '%s\n' "$runs" | while read -r id _ created event branch; do
  j=$(gh run view "$id" --repo "$repo" --json jobs \
    --jq '.jobs[] | select(.name | startswith("'"$job"'")) | "\(.conclusion) \(.startedAt) \(.completedAt) " + ([.steps[] | select(.name == "'"$step"'") | "\(.conclusion) \(.startedAt) \(.completedAt)"] | first // "null null null")')
  [ -n "$j" ] || { printf '%-12s %-21s %-13s %-28s %s\n' "$id" "$created" "$event" "$branch" 'no such job'; continue; }
  # shellcheck disable=SC2086  # six space-separated fields from jq
  set -- $j
  js=$(seconds "$1" "$2" "$3")
  ss=$(seconds "$4" "$5" "$6")
  printf '%-12s %-21s %-13s %-28s %-9s %6s %6s\n' "$id" "$created" "$event" "$branch" "$1" "$js" "$ss"
  [ "$4" = success ] && [ "$ss" != - ] && printf '%s\n' "$ss" >> "$steps" || true
done
[ -s "$steps" ] || fail "no successful $step step among the last twelve runs"
n=$(wc -l < "$steps" | tr -d ' ')
printf 'image-build steps that succeeded: %s (in jobs that passed or failed later); min %s s, median %s s, max %s s\n' "$n" "$(sort -n "$steps" | head -1)" "$(median < "$steps")" "$(sort -n "$steps" | tail -1)"
