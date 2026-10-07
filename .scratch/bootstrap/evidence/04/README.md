# Ticket 04 evidence

Evidence for [ticket 04](../../issues/04-github-repository.md). Gathered on 2026-10-07 with gh 2.100.0, logged in as `steven-cutting` with the `repo` scope.

[state.sh](state.sh) reads back every setting ticket 04 applied to `steven-cutting/knarr` and exits non-zero if any differs, or if any gh or git call fails. Lines beginning `info` only report. [state.txt](state.txt) is its transcript, taken after every change had been made. The script only reads: every call is a gh GET or a git read. [protection.json](protection.json) is the exact body sent to `PUT repos/steven-cutting/knarr/branches/main/protection`.

## Rerun

```sh
sh .scratch/bootstrap/evidence/04/state.sh > .scratch/bootstrap/evidence/04/state.txt 2>&1
```

Once 05 has added `check` as the required status check, pass it as the argument: `state.sh check`. Several checks are comma-separated, in any order. With no argument, the script expects the empty list that ticket 04 left.

## What it shows

- The repository is public, `main` is its default branch, the description is set, the homepage is empty, and GitHub detects the licence as Apache-2.0.
- GitHub's compare API reads `main` on GitHub as identical to `84668a5`, the commit ticket 04 pushed. A rerun after later merges reads `ahead`, which also passes.
- Merge commits, squash and rebase are all allowed. Branches are deleted on merge. Issues are on, and wiki and projects are off.
- Private vulnerability reporting, secret scanning, push protection and Dependabot alerts are on. Dependabot security-update pull requests are off. The script only reports them, because 27 decides them.
- `main` is protected by classic branch protection. A pull request is required, with zero approvals, so the only maintainer can merge their own. Administrators are not bound. Force pushes and deletions are refused, and pushes are not restricted. Required status checks are on with an empty list, which 05 fills. The repository has no rulesets.
