#!/bin/sh
# antz-flow.sh — git plumbing for one antz flow in the repo's main
# checkout. usage:
#   sh <tempfile> discover | ensure <slug> | state <slug> <probe-path> | release <slug>
# Run from inside the repository. Never destructive: no -B, no --force,
# no reset, no merges, no branch deletes, and never a forced or overwriting checkout —
# the one checkout ensure performs is refused, not forced, when it would destroy uncommitted work —
# and above all no commits: no role ever commits, so the work stays in
# the working tree where the human retains full control. ensure positions
# the session on the marker branch with a plain, flagless git switch. The
# branch antz/<slug> is only a marker of the commit the flow started from.
set -eu

cmd=${1:-}
[ -n "$cmd" ] || { echo 'usage: sh <tempfile> discover | ensure <slug> | state <slug> <probe-path> | release <slug>'; exit 1; }

# Preflight: the flow needs git on PATH and a git repository at or above
# the caller's directory. Both are stop-and-report states with their own
# machine line; there is no unbranched fallback mode.
command -v git >/dev/null 2>&1 || { echo 'state=no_git'; exit 1; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo 'state=no_repo'; exit 1; }

root=$(git rev-parse --show-toplevel)

br_exists() { git show-ref --verify --quiet "refs/heads/antz/$1"; }

case "$cmd" in
discover)
  # Branch markers for past/ongoing flows, then the working tree's own
  # change state — the only place resumable work can live, since a
  # branch's tree is always identical to the flow's base commit (nothing
  # is ever committed onto it).
  git branch --list 'antz/*' | sed 's/^[*+ ]*//' | grep '^antz/' | while read -r br; do
    printf 'candidate=branch slug=%s\n' "${br#antz/}"
  done
  for d in "$root/spdd/changes"/*/; do
    [ -d "$d" ] || continue
    printf 'candidate=on-disk slug=%s\n' "$(basename "$d")"
  done
  ;;
ensure)
   slug=${2:-}
   # Mechanical slug validation, before any branch or positioning work and
   # before the no-commits check: lowercase letters, digits, and hyphen
   # only; no leading/trailing hyphen; no doubled hyphen; at most 40
   # characters. The empty/absent slug is rejected the same way. The
   # rejection is a stop-and-report state: nothing is created or moved.
   case "$slug" in
     ''|*[!a-z0-9-]*|-*|*-|*--*)
       echo 'state=bad_slug'
       exit 1
       ;;
   esac
   [ "${#slug}" -le 40 ] || { echo 'state=bad_slug'; exit 1; }
   if ! git rev-parse HEAD >/dev/null 2>&1; then
     echo 'state=no_commits'
     exit 1
   fi
   # New-flow tree guard: starting a flow (the change dir is absent AND the
   # marker branch would be newly created) requires a clean working tree —
   # the fail-closed `git status --porcelain` check, untracked non-ignored
   # files included; the user cleans, commits, or gitignores and re-invokes.
   # Skipped on a resume (change dir present, the flow's own implementation
   # work legitimately lives in the tree) and on a branch-only reuse (the
   # marker already exists, so this is not a new-flow start). The refusal
   # runs before any branch creation or positioning: nothing is created or
   # moved.
   if ! br_exists "$slug" && [ ! -d "$root/spdd/changes/$slug" ] \
      && [ -n "$(git status --porcelain)" ]; then
     echo 'state=tree_dirty'
     exit 1
   fi
   fresh=no
   if ! br_exists "$slug"; then
     if git branch "antz/$slug" >/dev/null 2>&1; then
       fresh=yes
     else
       # The branch may have just been created by a concurrent ensure,
       # between this call's existence check and its git branch: re-check
       # and proceed through the same positioning as the resume path.
       # Only when the branch truly cannot be made to exist do we stop,
       # truthfully — never a fake success state.
       if ! br_exists "$slug"; then
         echo 'state=no_branch'
         exit 1
       fi
     fi
   fi
   # Position the session on the marker branch with a plain, flagless
   # switch. If git refuses (a destructive-checkout conflict: uncommitted
   # changes the switch would overwrite), stop machine-readably with
   # nothing forced, stashed, reset, or deleted.
   if git switch "antz/$slug" >/dev/null 2>&1; then
     if [ "$fresh" = yes ]; then
       echo 'state=created'
     else
       echo 'state=reused'
       # Advisory machine line (change flow-script-guards): a reuse on a
       # non-empty porcelain — change-dir resume or branch-only reuse —
       # names the pre-existing dirt. Advisory only: no routing change,
       # not a stop. A clean reuse prints exactly state=reused.
       [ -z "$(git status --porcelain)" ] || echo 'dirty=yes'
     fi
   else
     echo 'state=checkout_refused'
     exit 1
   fi
   ;;
state)
  slug=${2:-}
  probe=${3:-}
  [ -n "$slug" ] && [ -n "$probe" ] || { echo 'usage: state <slug> <probe-path>'; exit 1; }
  [ -f "$probe" ] || { echo 'probe file missing'; exit 1; }
  if ! br_exists "$slug"; then
    echo 'branch=missing'
    exit 1
  fi
  printf 'working_root=%s\n' "$root"
  CHANGE_DIR="$root/spdd/changes/$slug" sh "$probe"
  ;;
release)
  slug=${2:-}
  [ -n "$slug" ] || { echo 'usage: release <slug>'; exit 1; }
  br_exists "$slug" || { echo 'gate=refused reason=branch-missing'; exit 1; }
  [ -d "$root/spdd/archive/$slug" ] || { echo 'gate=refused reason=archive-missing'; exit 1; }
  [ ! -d "$root/spdd/changes/$slug" ] || { echo 'gate=refused reason=change-still-present'; exit 1; }
  # Nothing is ever removed — no worktree exists and nothing was ever
  # committed. The branch marker stays for the human's bookkeeping.
  printf 'released branch=antz/%s\n' "$slug"
  ;;
*)
  echo "unknown command: $cmd"
  exit 1
  ;;
esac
