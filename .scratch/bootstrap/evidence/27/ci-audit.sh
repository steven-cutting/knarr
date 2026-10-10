#!/bin/sh
# Ticket 27 evidence: one audit.yml run on GitHub, read back with gh. It prints
# the run's trigger, commit and jobs, then three things from the logs: the
# hex-advisories verdict; grype's table for the image-scan job, the scan of
# the real linux/amd64 knarr image, which is built in CI only (Decision 0012);
# and the link audit's errors. A job's failure is a finding, not a failure of
# this script; a run that has not finished, or a job missing from it, is.
# gh reads only. Needs an authenticated gh.
# Usage: sh ci-audit.sh <run-id>
set -eu
run=${1:?usage: ci-audit.sh <run-id>}
repo=steven-cutting/knarr
gh run view "$run" -R "$repo" --json status,conclusion,event,headBranch,headSha,createdAt,url \
  --jq '"run: \(.url)\nevent: \(.event) on \(.headBranch) at \(.headSha[0:7]), \(.createdAt)\nstatus: \(.status), \(.conclusion)"'
[ "$(gh run view "$run" -R "$repo" --json status --jq .status)" = completed ] ||
  { echo "run $run has not finished" >&2; exit 1; }
echo '-- jobs'
gh run view "$run" -R "$repo" --json jobs \
  --jq '.jobs[] | "\(.name): \(.conclusion), \(.startedAt) to \(.completedAt)"'
job() { # name: the job's id, or nothing
  gh run view "$run" -R "$repo" --json jobs --jq ".jobs[] | select(.name == \"$1\") | .databaseId"
}
hex_job=$(job 'Hex advisories')
scan_job=$(job 'Image scan')
links_job=$(job 'External links')
[ -n "$hex_job" ] || { echo 'the run has no Hex advisories job' >&2; exit 1; }
[ -n "$scan_job" ] || { echo 'the run has no Image scan job' >&2; exit 1; }
[ -n "$links_job" ] || { echo 'the run has no External links job' >&2; exit 1; }
# gh prints each log line as job<TAB>step<TAB>timestamp text.
echo '-- Hex advisories: just hex-audit'
gh run view "$run" -R "$repo" --log --job "$hex_job" |
  sed -n 's/^[^	]*	[^	]*	[^ ]* //p' | grep -E '^(hex-audit:|[A-Z][A-Z0-9-]+-[0-9A-Za-z-]+  )' || true
echo '-- Image scan: just image-scan (grype --only-fixed --fail-on high)'
gh run view "$run" -R "$repo" --log --job "$scan_job" |
  sed -n 's/^[^	]*	[^	]*	[^ ]* //p' |
  grep -E '^(grype |NAME +INSTALLED|[a-z0-9][a-z0-9.+_-]* +[^ ]+ +[^ ]+ +(deb|binary|conda|python|go-module|java-archive|erlang-otp|hex|rpm|apk) |\[[0-9]+\] |error: recipe|ERROR|discovered vulnerabilities)' || true
echo '-- External links: just links-audit (errors and the summary only)'
gh run view "$run" -R "$repo" --log --job "$links_job" |
  sed -n 's/^[^	]*	[^	]*	[^ ]* //p' | grep -E '^\[ERROR\]|Total \(in|error: recipe' || true
