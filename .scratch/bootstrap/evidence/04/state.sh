#!/bin/sh
# Ticket 04 evidence: read back every repository setting ticket 04 applied to
# steven-cutting/knarr, and fail on any that differs. Read-only: every call is
# a gh GET or a git read. Needs gh logged in with the repo scope.
# The required status checks are an argument, so 05 can rerun this after it
# adds `check`: ticket 04 left the list empty.
# Exits non-zero on any unexpected result, and on any gh or git error.
# Usage: sh state.sh [comma-separated-required-checks] > state.txt 2>&1
set -eu
repo=steven-cutting/knarr
pushed=84668a5c9a0dfb38d91f66afb614bd240921c6b9 # the main ticket 04 pushed
checks=$(printf '%s' "${1:-}" | tr ',' '\n' | sort | paste -s -d , -)
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
expect() { # label actual wanted
  [ "$2" = "$3" ] || fail "$1: read '$2', wanted '$3'"
  printf 'ok   %s: %s\n' "$1" "${2:-(empty)}"
}
# A command substitution's failure does not stop `set -e` when it is an
# argument, so every read is assigned first and checked.
v=$(gh --version | head -n 1) || fail 'gh --version failed'
printf 'date: %s\n%s\nrepository: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$v" "$repo"

echo; echo '== the repository'
v=$(gh repo view "$repo" --json visibility,defaultBranchRef,description,homepageUrl \
  --jq '[.visibility, .defaultBranchRef.name, .homepageUrl, .description] | join("\n")') || fail 'gh repo view failed'
expect visibility "$(printf '%s\n' "$v" | sed -n 1p)" PUBLIC
expect 'default branch' "$(printf '%s\n' "$v" | sed -n 2p)" main
expect homepage "$(printf '%s\n' "$v" | sed -n 3p)" ''
expect description "$(printf '%s\n' "$v" | sed -n 4p)" \
  'A Kubernetes controller in Gleam that biases Deployment scale-down away from busy worker pods.'
v=$(gh api "repos/$repo/license" --jq .license.spdx_id) || fail 'reading the licence failed'
expect 'detected licence' "$v" Apache-2.0

echo; echo '== main on GitHub'
# GitHub's main must be the commit ticket 04 pushed, or a descendant of it.
v=$(gh api "repos/$repo/compare/$pushed...main" --jq .status) || fail 'comparing main failed'
case $v in identical | ahead) ;; *) fail "main on GitHub is $v relative to $pushed" ;; esac
printf 'ok   main on GitHub is %s with %s\n' "$v" "$pushed"
v=$(git ls-remote "git@github.com:$repo.git" refs/heads/main) || fail 'git ls-remote failed'
printf 'info remote main: %s\n' "$(printf '%s' "$v" | cut -f1)"

echo; echo '== hygiene: merge methods, delete-branch-on-merge, issues, wiki, projects'
v=$(gh api "repos/$repo" --jq '[.allow_merge_commit, .allow_squash_merge, .allow_rebase_merge] | map(tostring) | join(" ")') ||
  fail 'reading the repository failed'
expect 'merge commit, squash, rebase' "$v" 'true true true'
v=$(gh api "repos/$repo" --jq '[.delete_branch_on_merge, .has_issues, .has_wiki, .has_projects] | map(tostring) | join(" ")') ||
  fail 'reading the repository failed'
expect 'delete branch on merge, issues, wiki, projects' "$v" 'true true false false'

echo; echo '== security'
v=$(gh api "repos/$repo/private-vulnerability-reporting" --jq .enabled) || fail 'reading vulnerability reporting failed'
expect 'private vulnerability reporting' "$v" true
v=$(gh api "repos/$repo" --jq '[.security_and_analysis.secret_scanning.status, .security_and_analysis.secret_scanning_push_protection.status] | join(" ")') ||
  fail 'reading security_and_analysis failed'
expect 'secret scanning, push protection' "$v" 'enabled enabled'
# GitHub answers 204 with no body when Dependabot alerts are on and 404 when
# off. Any other failure is an error, not a state.
if err=$(gh api "repos/$repo/vulnerability-alerts" --silent 2>&1); then alerts=enabled
else
  case $err in *'HTTP 404'*) alerts=disabled ;; *) fail "reading Dependabot alerts failed: $err" ;; esac
fi
expect 'Dependabot alerts' "$alerts" enabled
# Security-update pull requests are 27's to decide, so this only reports them.
v=$(gh api "repos/$repo" --jq .security_and_analysis.dependabot_security_updates.status) ||
  fail 'reading security_and_analysis failed'
printf 'info Dependabot security updates: %s\n' "$v"

echo; echo '== protection on main'
echo 'fields: strict, required checks, administrators bound, pull request required,'
echo '        approvals, force pushes, deletions, push restrictions'
v=$(gh api "repos/$repo/branches/main/protection" --jq '[
    .required_status_checks.strict,
    ([.required_status_checks.checks[]?.context] | sort | join(",")),
    .enforce_admins.enabled,
    (.required_pull_request_reviews != null),
    .required_pull_request_reviews.required_approving_review_count,
    .allow_force_pushes.enabled,
    .allow_deletions.enabled,
    (.restrictions != null)
  ] | map(tostring) | join(" ")') || fail 'reading protection failed'
expect protection "$v" "false $checks false true 0 false false false"
v=$(gh api "repos/$repo/rulesets" --jq length) || fail 'reading rulesets failed'
expect rulesets "$v" 0
