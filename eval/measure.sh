#!/usr/bin/env bash
#
# eval/measure.sh — the ladder: one state, one install, one batch.
#
# run.sh grades what is installed and refuses to run when the tree and the install
# disagree, so a measurement is three steps in a fixed order: put the graded files at the
# state under test, install them, run. This does exactly that, and puts the tree back on
# the branch it started from on the way out, whatever happens.
#
#   ./measure.sh before master N:2 B:1 D:1
#   ./measure.sh item2  d7dad3c N:2
#
# The tag labels the rows in results.tsv, usage.tsv and agents.tsv; the state is a
# branch, tag or commit; each scenario:N is a batch of N runs. Only what antz installs is
# taken from the state — prompts, agents, skills, extensions — so the harness itself
# stays at the tip and every batch is measured with the same instrument.
#
# A FAIL is a result, not an error, so a scenario outside its contract does not stop the
# ladder. The install's own output goes to the log with everything else.

set -uo pipefail

[ $# -ge 3 ] || { sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
tag="$1"; state="$2"; shift 2
branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"

restore() { git -C "$REPO" checkout "$branch" -- prompts agents skills extensions 2>/dev/null; }
trap restore EXIT

echo "== $tag: installing $state"
git -C "$REPO" checkout "$state" -- prompts agents skills extensions || exit 1
"$REPO/adapters/pi/install.sh" || exit 1

for pair in "$@"; do
  scenario="${pair%%:*}"; runs="${pair##*:}"
  echo "== $tag: $scenario x$runs"
  TAG="$tag" RUNS="$runs" "$HERE/run.sh" "$scenario"
done
