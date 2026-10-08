# Ticket 04 evidence

Evidence for [ticket 04](../../issues/04-github-repository.md). Gathered on 2026-10-07 with gh 2.100.0, logged in as `steven-cutting` with the `repo` scope. `state.txt` was taken again at 2026-10-08T00:02Z (UTC), after the adversarial-review fixes.

[state.sh](state.sh) reads back every setting ticket 04 applied to `steven-cutting/knarr`, and every branch-protection field, whether applied or left at its default. It exits non-zero if any differs, or if any gh or git call fails. Lines beginning `info` only report. [state.txt](state.txt) is its transcript, taken after every change had been made. The script only reads: every call is a gh GET or a git read.

- [protection.json](protection.json) is the exact body sent to `PUT repos/steven-cutting/knarr/branches/main/protection`.
- [protection-response.json](protection-response.json) is the protection object GitHub returned from that `PUT`. It has the same shape as a `GET` on the same path.
- [protection.jq](protection.jq) is the projection `state.sh` reads protection through. It prints one labelled `key=value` line, and a missing field prints `null`.
- [projection-test.sh](projection-test.sh) checks that projection offline with jq, and [projection-test.txt](projection-test.txt) is its transcript. It projects the recorded response to `state.sh`'s expected line. Then it edits one field of a copy at a time, and checks that only that field's label changes, to the value expected. It edits every boolean the projection reads, among them `require_last_push_approval` and `lock_branch`, either of which would block every merge. It also sets one approval, adds a required check, restricts pushes, drops pull request reviews, and deletes `lock_branch`.

## Rerun

```sh
sh .scratch/bootstrap/evidence/04/state.sh > .scratch/bootstrap/evidence/04/state.txt 2>&1
sh .scratch/bootstrap/evidence/04/projection-test.sh > .scratch/bootstrap/evidence/04/projection-test.txt 2>&1
```

Once 05 has added `check` as the required status check, pass it as the argument: `state.sh check`. Several checks are comma-separated, in any order. With no argument, the script expects the empty list that ticket 04 left.

## What it shows

- The repository is public, `main` is its default branch, the description is set, the homepage is empty, and GitHub detects the licence as Apache-2.0.
- GitHub's compare API reads `main` on GitHub as identical to `84668a5`, the commit ticket 04 pushed. A rerun after later merges reads `ahead`, which also passes.
- Merge commits, squash and rebase are all allowed. Branches are deleted on merge. Issues are on, and wiki and projects are off.
- Private vulnerability reporting, secret scanning, push protection and Dependabot alerts are on. Dependabot security-update pull requests are off. The script only reports them, because 27 decides them.
- `main` is protected by classic branch protection. A pull request is required, with zero approvals, so the only maintainer can merge their own. Stale reviews are not dismissed, and neither code-owner review nor approval of the last push is required. Administrators are not bound, so the owner can still push to `main` directly. Force pushes and deletions are refused, and pushes are not restricted. Required status checks are on with an empty list, which 05 fills. The branch is not locked. Linear history, conversation resolution and signed commits are not required, creations are not blocked, and fork syncing is off. The repository has no rulesets.
