#!/bin/sh
# Ticket 27 evidence: the public sources Decision 0013 cites, fetched today.
# Each page is recorded with its HTTP status, size and sha256, and each cited
# phrase is looked for in the page's text (tags stripped, entities decoded,
# whitespace collapsed), as in 28's sources.sh. A fetch failure stops the run.
# A phrase that is not found prints "not found as of <date>" and counts as a
# finding, not a failure: vendor pages are reworded without notice. Three
# phrases are expected not to be found: the Mend-hosted app's page does not
# document allowedUnsafeExecutions, and osv-scanner's list of lockfiles names
# neither Gleam nor manifest.toml. Then the three scanners conda-forge carries.
# Public-source research, not script evidence of behaviour.
# Needs curl, perl and pixi.
# Usage: sh sources.sh <empty-work-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$here/lib.sh"
work=$(work_dir "${1:?usage: sources.sh <empty-work-dir>}")
today=$(date -u +%Y-%m-%d)
printf 'date: %sT%s\n' "$today" "$(date -u +%H:%MZ)"
text() { # html on stdin: visible text, one line
  perl -0777 -pe 's/<script.*?<\/script>//gs; s/<style.*?<\/style>//gs; s/<[^>]*>/ /g; s/&quot;/"/g; s/&#x27;|&#39;|&rsquo;|&lsquo;/\x27/g; s/&ldquo;|&rdquo;/"/g; s/&amp;/&/g; s/&lt;/</g; s/&gt;/>/g; s/\s+/ /g'
}

# id|url: fetched once each, into $work/<id>.html
pages='gleam|https://docs.renovatebot.com/modules/manager/gleam/
pixi|https://docs.renovatebot.com/modules/manager/pixi/
github-actions|https://docs.renovatebot.com/modules/manager/github-actions/
regex|https://docs.renovatebot.com/modules/manager/regex/
pre-commit|https://docs.renovatebot.com/modules/manager/pre-commit/
github-runners|https://docs.renovatebot.com/modules/datasource/github-runners/
local|https://docs.renovatebot.com/modules/platform/local/
options|https://docs.renovatebot.com/configuration-options/
self-hosted|https://docs.renovatebot.com/self-hosted-configuration/
mend|https://docs.renovatebot.com/mend-hosted/hosted-apps-config/
permissions|https://docs.renovatebot.com/security-and-permissions/
presets-default|https://docs.renovatebot.com/presets-default/
presets-docker|https://docs.renovatebot.com/presets-docker/
presets-helpers|https://docs.renovatebot.com/presets-helpers/
dependabot|https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories
dependency-graph|https://docs.github.com/en/code-security/reference/supply-chain-security/dependency-graph-supported-package-ecosystems
osv-batch|https://google.github.io/osv.dev/post-v1-querybatch/
osv-schema|https://ossf.github.io/osv-schema/
osv-scanner|https://google.github.io/osv-scanner/supported-languages-and-lockfiles/
trivy|https://api.osv.dev/v1/vulns/CVE-2026-33634'

# id|phrase|what it shows (a leading ! marks a phrase expected not to be found)
phrases='gleam|devDependencies Listed under dev-dependencies|the gleam manager reads the hyphenated dev table only, so gleam.toml spells it that way
gleam|The gleam manager uses the gleam program to update manifest.toml files|the hosted app must run gleam to move the lock
gleam|This manager supports lockFileMaintenance for the following file(s): manifest.toml|transitive hex packages move through lock file maintenance
pixi|Feature dependencies produce dynamic depType values in the form feature-<name>|the otp, cluster and audit features are read
pixi|Self-hosted administrators must explicitly allow this path by including pixi in the global allowedUnsafeExecutions setting|relocking pixi.lock is an unsafe execution
pixi|When pixi is not allowed, the package file is still updated, but pixi.lock is left unchanged|why every conda update stays held until 41 proves the hosted relock
github-actions|prefix-dev/setup-pixi pixi-version prefix-dev/pixi|setup-pixi'"'"'s pixi-version input is read as prefix-dev/pixi
github-actions|action\.ya?ml$/|every action.yml, the setup action'"'"'s included, is in the manager'"'"'s file patterns
github-actions|Actions pinned to a bare SHA without a version comment are disabled by default|why every SHA carries its version comment
regex|The regex manager uses RE2 which does not support backreferences and lookahead assertions|the custom managers avoid both; the gate test refuses them
regex|matches are done per-file|so the patterns carry no line anchors
pre-commit|functionality is currently in beta testing, so you must opt-in|the pre-commit manager stays off: no remote hook exists to update
github-runners|This datasource returns a list of all runners that are hosted by GitHub|runner labels are covered without configuration
local|This feature is flagged as experimental|the dry run'"'"'s platform is experimental
local|In this mode, Renovate defaults to dryRun=lookup|the dry run looks up updates and creates nothing
local|Branch creation is not supported|so the hold and the branches are 41'"'"'s to see on the hosted app
options|composer , gleam|rangeStrategy update-lockfile works for gleam
options|Renovate only queries the OSV database for dependencies that use one of these datasources|Renovate'"'"'s OSV alerts cover hex ...
options|packagist pypi rubygems|... and not conda, docker or GitHub actions
options|You will only get OSV-based vulnerability alerts for direct dependencies|and only direct dependencies, so hex-audit asks about every locked package
options|"schedule" : [], "dependencyDashboardApproval" : false|a vulnerability fix skips the landing hold once the app is live, though it still never automerges
self-hosted|"mise" , "pixi"|pixi is one of the allowedUnsafeExecutions values
mend|!allowedUnsafeExecutions|whether the hosted app allows pixi is undocumented; 41 proves it
mend|Installing Renovate into selected repositories always leads to onboarding PRs|what 41 should expect at installation
permissions|Read for repository content and write for creating branches|the app writes branches ...
permissions|Explicit permission needed to update workflows|... and workflow files: the trust surface 0013 records
presets-default|Enable Renovate Dependency Dashboard approval workflow|:dependencyDashboardApproval, the landing hold
presets-docker|"matchDatasources" : [ "docker" ], "pinDigests" : true|docker:pinDigests
presets-helpers|"matchDepTypes" : [ "action" , "workflow" ], "pinDigests" : true|helpers:pinGitHubActionDigests
dependabot|Hex mix v1|Dependabot'"'"'s hex support is mix, not Gleam
dependabot|Dependabot support for Conda does not include private registries, vendoring, or lock file updates|and it cannot move pixi.lock
dependency-graph|GitHub Actions workflows YAML|Dependabot alerts read the workflows; the page lists no Hex, Conda or Docker
osv-batch|a querybatch request may return results with a next_page_token for only a few of the total queries|why hex-audit refuses a paged answer instead of passing it
osv-schema|Hex The package manager for the Erlang ecosystem; the name is a Hex package name|OSV'"'"'s ecosystem name is Hex
osv-schema|the versions field is typically populated with enumerated versions (tags)|an OTP tag is matched against the tags OSV enumerated
osv-scanner|Elixir mix.lock|osv-scanner reads mix.lock for the Erlang ecosystem ...
osv-scanner|!manifest.toml|... and not Gleam'"'"'s manifest.toml
osv-scanner|!Gleam|... nor anything Gleam
trivy|Trivy ecosystem supply chain briefly compromised|why Trivy is excluded (GHSA-69fq-xp46-6x23)
trivy|force-push 76 of 77 version tags|the action tags themselves were moved'

printf '%s\n' "$pages" | while IFS='|' read -r id url; do
  code=$(curl -sSL -A 'Mozilla/5.0 (compatible; knarr evidence 27)' --max-time 60 -o "$work/$id.html" -w '%{http_code}' "$url") || code=000
  printf '%-17s http %s  %7s bytes  sha256 %s  %s\n' "$id" "$code" "$(wc -c < "$work/$id.html" | tr -d ' ')" "$(sha256_of < "$work/$id.html" | cut -c1-12)" "$url"
  [ "$code" = 200 ] || { echo "fetch failed: $url" >&2; exit 1; }
  text < "$work/$id.html" > "$work/$id.txt"
done
echo '--'
printf '%s\n' "$phrases" | while IFS='|' read -r id phrase what; do
  case $phrase in
    !*) phrase=${phrase#!}
        if grep -qF -- "$phrase" "$work/$id.txt"; then printf 'UNEXPECTED  %-17s "%s" is on the page now: %s\n' "$id" "$phrase" "$what"
        else printf 'not found   %-17s "%s" (expected; as of %s): %s\n' "$id" "$phrase" "$today" "$what"; fi ;;
    *)  if grep -qF -- "$phrase" "$work/$id.txt"; then printf 'found       %-17s "%s": %s\n' "$id" "$phrase" "$what"
        else printf 'not found   %-17s "%s" (as of %s): %s\n' "$id" "$phrase" "$today" "$what"; fi ;;
  esac
done > "$work/phrases.txt"
cat "$work/phrases.txt"
found=$(grep -c '^found' "$work/phrases.txt" || true)
missing=$(grep -c '^not found .*(as of' "$work/phrases.txt" || true)
expected_missing=$(grep -c '(expected;' "$work/phrases.txt" || true)
unexpected=$(grep -c '^UNEXPECTED' "$work/phrases.txt" || true)
printf -- '-- %s phrases found, %s not found, %s expected not found, %s unexpected\n' "$found" "$missing" "$expected_missing" "$unexpected"

echo '-- the scanners conda-forge carries (linux-64), newest build of each'
for tool in grype trivy osv-scanner; do
  version=$(pixi search "$tool" --platform linux-64 -c conda-forge 2> /dev/null | sed -n 's/^Version  *//p' | head -1)
  [ -n "$version" ] || fail "pixi search found no $tool"
  printf '%-12s %s\n' "$tool" "$version"
done
