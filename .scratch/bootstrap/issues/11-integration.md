# 11: Integration

**Context:** This adapts libpawdoku's T11. The setup lanes (04–09) are each green on their own branch. This ticket proves that together they deliver what 03 promised, on a fresh machine and in CI.

**What to build:** A fresh clone reaches a green `just check` with one `just initialize`. CI is green on `main`, branch protection is verified, and every claim the lanes left unverified is either closed or turned into a ticket.

**Non-goals:** New tooling or new validators. A gap becomes a follow-up ticket, not a fix inside this one, unless it is a one-line correction.

**Blocked by:** 04, 05, 06, 07, 08, 09

**MVP critical path:** no. It consolidates the setup lanes, and no MVP ticket waits on it.

**Status:** ready-for-agent

- [ ] In a new directory, a fresh clone runs `just initialize` and then `just check`. Both are timed and the times recorded. `just check` then passes again with the network off.
- [ ] A linked worktree runs `just check` green without installing hooks.
- [ ] CI is green on `main`.
- [ ] A read-only `gh api` call confirms branch protection on `main`, with `check` as the only required status check.
- [ ] Every claim marked unverified in the hand-backs from 01–09 is closed with evidence or drafted as a follow-up.
