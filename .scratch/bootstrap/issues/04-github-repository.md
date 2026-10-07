# 04: GitHub repository

**Context:** This adapts libpawdoku's T01. The repository is public: `steven-cutting/knarr`, Apache-2.0. Every step here leaves the worktree, so each one is **authorization required**. The agent prepares the exact command, shows it, and runs it only after the maintainer approves.

**What to build:** `steven-cutting/knarr` exists on GitHub with `main` pushed, hygiene settings applied, private vulnerability reporting on, and `main` protected. The required status check is added later by 05, once the `check` job exists.

**Non-goals:** CI workflows (05). Release settings and GHCR (28).

**Blocked by:** 03

**MVP critical path:** yes. CI (05) and image publishing (28) need the remote.

**Status:** done. See [the hand-back notes](#hand-back-notes) and the [evidence](../evidence/04/README.md).

- [x] **Authorization required:** the public repository is created with a description, and GitHub detects the Apache-2.0 licence.
- [x] **Authorization required:** `main` is pushed.
- [x] **Authorization required:** hygiene settings are applied: merge methods, delete-branch-on-merge, and unused features (wiki, projects) off, as the maintainer chooses.
- [x] **Authorization required:** private vulnerability reporting, secret scanning with push protection, and Dependabot alerts are on.
- [x] **Authorization required:** `main` is protected: pull request required, no force pushes, no deletions.
- [x] Every mutating `gh` command run is listed in the hand-back notes, with a read-only `gh api` call showing the resulting state.

## Hand-back notes

**Done on 2026-10-07**, in one session, with gh 2.100.0 logged in as `steven-cutting` (scopes `repo`, `workflow`, `read:org`, `gist`, `admin:public_key`, git protocol ssh). The repository is public at <https://github.com/steven-cutting/knarr>. `main` is pushed at `84668a5`, and `main` is protected.

### Before any change

- `gh repo view steven-cutting/knarr` answered `Could not resolve to a Repository`, and `git remote -v` printed nothing.
- `main` was at `84668a5`, ticket 03's last commit.
- Every commit on `main` has `tech@scutting.com` as author. The sibling repositories already show that address publicly, so making the history public exposes nothing new. The only other addresses in the history are `noreply@anthropic.com` from co-author trailers and `example.invalid` addresses in tests.
- A search of every patch on `main` found no private key, cloud or GitHub token, kubeconfig credential or password assignment. The history contains absolute local paths (`/Users/scutting/...`) in evidence transcripts, which are not secrets.
- The shared hooks directory has a `pre-commit` hook and no `pre-push` hook, so the push ran no hook.

### Decisions the maintainer made

The maintainer answered each question before any command it covered ran.

- **Create and push:** "Authorize all three", given against the three commands below, quoted verbatim, with the description shown.
- **Merge methods:** "All three (Recommended)": merge commit, squash and rebase, as on every sibling repository. They were already GitHub's defaults, so no command changed them. 28 can narrow them if release tooling needs it.
- **Administrators:** "Don't bind (Recommended)". `enforce_admins` is `false`, the house setting. The owner can still push to `main` directly, which bypasses the pull-request rule.
- **Settings:** "Authorize all four", given against the four commands below, quoted verbatim, with `protection.json` shown in full.
- **Wiki and projects off, delete-branch-on-merge on:** part of the authorized settings command.

### Every mutating command, and what it printed

Each command ran once and exited 0. The read-back for each is a line of [state.txt](../evidence/04/state.txt), which `state.sh` produces from read-only `gh` calls.

1. `gh repo create steven-cutting/knarr --public --description "A Kubernetes controller in Gleam that biases Deployment scale-down away from busy worker pods."` printed `https://github.com/steven-cutting/knarr`. It passed no `--source` or `--push`, which would have pushed this ticket's branch and made it the default. It also passed no `--license`, `--add-readme` or `--gitignore`, any of which would have seeded a commit that blocks the push. Read back: `gh repo view --json visibility,description,homepageUrl` gives `PUBLIC`, the description and an empty homepage, and `gh api repos/steven-cutting/knarr/license --jq .license.spdx_id` gives `Apache-2.0`.
2. `git remote add origin git@github.com:steven-cutting/knarr.git` printed nothing. Not a `gh` command, but it is a change: it writes the shared `.git/config` in the primary checkout, so every worktree now sees `origin`.
3. `git push -u origin main` printed:

   ```text
   To github.com:steven-cutting/knarr.git
    * [new branch]      main -> main
   branch 'main' set up to track 'origin/main'.
   ```

   Read back: `gh repo view --json defaultBranchRef` gives `main`. `gh api repos/steven-cutting/knarr/compare/84668a5c9a0dfb38d91f66afb614bd240921c6b9...main` gives `identical`, and `git ls-remote` gives the same SHA as `git rev-parse main`. So `gh repo edit --default-branch` was not needed.
4. `gh repo edit steven-cutting/knarr --delete-branch-on-merge --enable-wiki=false --enable-projects=false` printed nothing. Before: `false true true true` (delete on merge, issues, wiki, projects). Read back with `gh api repos/steven-cutting/knarr`: `true true false false`.
5. `gh api -X PUT repos/steven-cutting/knarr/private-vulnerability-reporting` printed nothing. Before: `{"enabled":false}`. Read back with a GET on the same path: `true`.
6. `gh api -X PUT repos/steven-cutting/knarr/vulnerability-alerts` printed nothing. Before: a GET answered `404`, which means off. Read back: the GET answers 204, which means on.
7. `gh api -X PUT repos/steven-cutting/knarr/branches/main/protection --input protection.json` sent [protection.json](../evidence/04/protection.json) and printed the new protection object. Before: `Branch not protected (HTTP 404)`. Read back with `gh api repos/steven-cutting/knarr/branches/main/protection`: `false  false true 0 false false false`. The fields are `strict`, the required checks (empty), administrators bound, pull request required, approvals, force pushes, deletions and push restrictions.

Secret scanning and push protection were already `enabled` when the repository was created, as GitHub sets them for new public repositories. So no command changed them. `state.txt` reads them back.

`sh .scratch/bootstrap/evidence/04/state.sh` ran after the last change and exited 0. Every check printed `ok`, and the two `info` lines only report. The script fails on any gh or git error rather than reading it as a setting.

### Departures from libpawdoku's T01

- **No bootstrap script.** T01 ran `biscuit_games_template`'s `bootstrap_repo.sh`, which hardcodes no review requirement. This ticket needs a pull request, so the commands are direct `gh` calls. Each one was compared with the state read beforehand, and only settings that differed were changed. The read-only [state.sh](../evidence/04/state.sh) takes the place of the script's dry run and its idempotency rerun.
- **A pull request is required, with zero approvals.** A single maintainer cannot approve their own pull request, so one approval would block every merge. `dismiss_stale_reviews`, `require_code_owner_reviews` and `require_last_push_approval` are `false`.
- **Required status checks are on with an empty list.** The ticket leaves the check to 05. `required_status_checks: {"strict": false, "checks": []}` requires nothing today, and it lets 05 add `check` without resending the whole protection object.
- **Dependabot alerts are on, and security-update pull requests are off.** The ticket asks for alerts. 27 decides whether Dependabot or something else opens update pull requests.

### Process notes

- The maintainer ran `just initialize` in this worktree, so the pre-commit hook and `just check` could run here without this session using the network.
- The only network calls this session made were the `gh` and `git` calls listed above, and the read-only `gh` reads of this repository and of `steven-cutting/libpawdoku`, made to copy the house settings.
- No other branch was pushed. This ticket's branch, `04-github-repository`, is not pushed. Landing it on `main` now needs a pull request, which is a separate authorized action.

- `just check` passed on the closing commit's tree. One earlier run failed a single `test-checkers` test (`1 failed, 86 passed`). Its name was lost with the output, and five further runs passed. This ticket changes no code, so the failure is an intermittent test in 03's suite, not yet identified.

Not verified:

- 05's additive call, `gh api -X POST repos/steven-cutting/knarr/branches/main/protection/required_status_checks/contexts -f 'contexts[]=check'`, was not run, because adding `check` is 05's authorized action. The endpoint exists for an enabled status-check list, which this one is.

### For other lanes

- **05:** add `check` as the only required status check with the additive call above, which is an authorized action. If that fails, resend [protection.json](../evidence/04/protection.json) with `"checks": [{"context": "check"}]`, because a `PUT` replaces the whole protection object. Then `sh .scratch/bootstrap/evidence/04/state.sh check` should exit 0. `main` already needs a pull request, so 05's own branch lands by pull request. Administrators are not bound, so the owner can still push directly if the first run blocks a merge.
- **11:** `sh .scratch/bootstrap/evidence/04/state.sh check` is the read-only `gh api` confirmation of branch protection that 11 asks for.
- **12:** private vulnerability reporting is on, so `SECURITY.md` can point to GitHub's form: <https://github.com/steven-cutting/knarr/security/advisories/new>.
- **27:** Dependabot alerts are on. Dependabot security updates are off, and `.github/dependabot.yml` does not exist, so the update tool is 27's choice.
- **28:** merge methods are GitHub's defaults (all three). Restricting them is 28's call if release tooling reads history.
- **Every lane:** `origin` is configured in the shared `.git/config`, so every worktree can push its branch. Pushing and opening a pull request each still need the maintainer's authorization.
