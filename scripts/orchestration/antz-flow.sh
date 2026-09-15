#!/bin/sh
# antz-flow.sh — the only git mutation an antz flow performs: mark the flow
# with its own branch. usage:
#   sh <path> start <slug>
# Run from inside the repository. Never destructive and never a commit: no
# -B, no --force, no reset, no merges, no branch deletes, and the one
# checkout it performs is refused, not forced, when it would overwrite
# uncommitted work. Everything else an orchestrator needs to resume (the
# change directory, OPEN_QUESTIONS.md, REJECTED.md) is read straight from the
# working tree — there is no state file and no probe.
set -eu

cmd=${1:-}
slug=${2:-}
[ "$cmd" = start ] || { echo 'usage: sh <path> start <slug>'; exit 1; }

# Mechanical slug validation, before any branch or positioning work:
# lowercase letters, digits, and hyphen only; no leading/trailing hyphen; no
# doubled hyphen; at most 40 characters. Nothing is created or moved.
case "$slug" in
  ''|*[!a-z0-9-]*|-*|*-|*--*) echo 'state=bad_slug'; exit 1 ;;
esac
[ "${#slug}" -le 40 ] || { echo 'state=bad_slug'; exit 1; }

command -v git >/dev/null 2>&1 || { echo 'state=no_git'; exit 1; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo 'state=no_repo'; exit 1; }
root=$(git rev-parse --show-toplevel)
git rev-parse HEAD >/dev/null 2>&1 || { echo 'state=no_commits'; exit 1; }

branch="antz/$slug"
if git show-ref --verify --quiet "refs/heads/$branch"; then
  reused=yes
else
  reused=no
  # A flow that has not written anything yet starts from a clean tree: the
  # work itself stays uncommitted while the flow runs, so the guard would
  # deadlock every resume if it applied there. It applies only on a new-flow
  # start with no change directory to resume (untracked non-ignored files
  # included). The user cleans, commits, or gitignores and re-invokes.
  if [ ! -d "$root/spdd/changes/$slug" ] && [ -n "$(git status --porcelain)" ]; then
    echo 'state=tree_dirty'; exit 1
  fi
  if ! git branch "$branch" >/dev/null 2>&1; then
    # A concurrent start may have created the branch in between: re-check
    # and proceed through the same positioning when it exists.
    git show-ref --verify --quiet "refs/heads/$branch" || { echo 'state=no_branch'; exit 1; }
  fi
fi

# Position the session on the marker branch with a plain, flagless switch.
# A refusal (uncommitted changes it would overwrite) stops machine-readably
# with nothing forced, stashed, reset, or deleted.
git switch "$branch" >/dev/null 2>&1 || { echo 'state=checkout_refused'; exit 1; }

if [ "$reused" = yes ]; then
  echo "state=reused root=$root"
  # Advisory only: a resume carries any pre-existing dirt into the human's
  # commit. Not a stop, and no routing changes.
  [ -z "$(git status --porcelain)" ] || echo 'dirty=yes'
else
  echo "state=started root=$root"
fi
