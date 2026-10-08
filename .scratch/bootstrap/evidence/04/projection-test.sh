#!/bin/sh
# Ticket 04 evidence: check protection.jq offline. The projection of
# protection-response.json, the object GitHub returned when ticket 04 set the
# protection, must be state.sh's expected line. Then each case edits one field
# of a copy and checks that only that field's labels change, to exactly the
# values given. So a field the projection drops, or reads under another label,
# fails here. Needs jq; makes no network call.
# Exits non-zero on any unexpected result.
# Usage: sh projection-test.sh > projection-test.txt 2>&1
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
response=$here/protection-response.json
baseline='strict=false checks= admins=false pr=true approvals=0 dismiss_stale=false code_owners=false last_push=false force_pushes=false deletions=false restrictions=false linear=false conversations=false signatures=false lock=false block_creations=false fork_syncing=false'
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
v=$(jq --version) || fail 'jq --version failed'
printf '%s\n' "$v"
tmp=$(mktemp -d) || fail 'mktemp failed'
trap 'rm -rf -- "${tmp:?}"' EXIT

v=$(jq -r -f "$here/protection.jq" "$response") || fail 'projecting the response failed'
[ "$v" = "$baseline" ] || fail "baseline: read '$v', wanted '$baseline'"
printf 'ok   baseline: %s\n' "$v"

each() { # name jq-edit label=value...
  name=$1 edit=$2
  shift 2
  want=$baseline
  for pair in "$@"; do
    want=$(printf '%s\n' "$want" | sed -E "s/(^| )${pair%%=*}=[^ ]*/\\1$pair/") || fail "$name: sed failed"
  done
  [ "$want" != "$baseline" ] || fail "$name: the case changes no label"
  jq "$edit" "$response" > "$tmp/case.json" || fail "$name: editing the response failed"
  v=$(jq -r -f "$here/protection.jq" "$tmp/case.json") || fail "$name: projecting failed"
  [ "$v" = "$want" ] || fail "$name: read '$v', wanted '$want'"
  printf 'ok   %s: %s\n' "$name" "$*"
}

echo
each strict '.required_status_checks.strict = true' strict=true
each 'a required check' '.required_status_checks.checks = [{"context": "check"}]' checks=check
each enforce_admins '.enforce_admins.enabled = true' admins=true
each 'no pull request required' '.required_pull_request_reviews = null' \
  pr=false approvals=null dismiss_stale=null code_owners=null last_push=null
each 'one approval' '.required_pull_request_reviews.required_approving_review_count = 1' approvals=1
each dismiss_stale_reviews '.required_pull_request_reviews.dismiss_stale_reviews = true' dismiss_stale=true
each require_code_owner_reviews '.required_pull_request_reviews.require_code_owner_reviews = true' code_owners=true
each require_last_push_approval '.required_pull_request_reviews.require_last_push_approval = true' last_push=true
each allow_force_pushes '.allow_force_pushes.enabled = true' force_pushes=true
each allow_deletions '.allow_deletions.enabled = true' deletions=true
each restrictions '.restrictions = {"users": [], "teams": [], "apps": []}' restrictions=true
each required_linear_history '.required_linear_history.enabled = true' linear=true
each required_conversation_resolution '.required_conversation_resolution.enabled = true' conversations=true
each required_signatures '.required_signatures.enabled = true' signatures=true
each lock_branch '.lock_branch.enabled = true' lock=true
each block_creations '.block_creations.enabled = true' block_creations=true
each allow_fork_syncing '.allow_fork_syncing.enabled = true' fork_syncing=true
each 'lock_branch missing' 'del(.lock_branch)' lock=null
