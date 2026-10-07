#!/bin/sh
# Install the read-only prek config as the pre-commit hook, from the primary
# checkout only. Every linked worktree shares the primary checkout's .git/hooks,
# and prek writes a shim naming an absolute path into whichever worktree ran it,
# so a hook installed from a linked worktree runs that worktree's prek for
# commits made anywhere, and fails every commit once the worktree is deleted.
# The test is the one git uses: in a linked worktree the git directory and the
# common directory differ. A linked worktree still reaches a green `just check`
# without hooks; the gate does not depend on them.
set -eu
git_dir=$(git rev-parse --path-format=absolute --git-dir)
common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
if [ "$git_dir" = "$common_dir" ]; then
  prek install --overwrite --hook-type pre-commit
else
  printf '%s\n' 'This is a linked worktree: skipping hook installation.' >&2
  printf '%s\n' 'Hooks are shared by every worktree; run just initialize once from the primary checkout to install them.' >&2
fi
