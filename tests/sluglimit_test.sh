#!/usr/bin/env bash
# Unit tests for change precision-gaps, sub-spec 04
# (spdd/changes/precision-gaps/04-sluglimit.feature, scenarios
# sluglimit-01..02): the orchestrator prompt's step 1 slug-derivation bullet
# states the flow script's mechanical length limit (at most 40 characters,
# the `state=bad_slug` gate) in place of the undefined "short" (sluglimit-01),
# while the collision rules keep their pinned meaning -- suffix only on a
# real continuation of an already-claimed change, checked against
# spdd/changes/, spdd/archive/, and `git branch --list 'antz/*'`, and the
# ask-the-user stop on a semantically unclear continuation (sluglimit-02).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/rolechecks_test.sh. Run directly:
#   ./tests/sluglimit_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
FLOW_SH="$SCRIPT_DIR/scripts/orchestration/antz-flow.sh"

pass_count=0
fail_count=0

# ---- tiny test runner (mirrors tests/rolechecks_test.sh) ---------------------

run_test() {
  # $1 = reported test name (must contain its scenario id), $2 = function name
  name="$1"; fn="$2"
  if "$fn"; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name"
    fail_count=$((fail_count + 1))
  fi
}

require() {
  # $1 = file, $2 = fixed string that must appear in it
  if grep -qF -- "$2" "$1"; then return 0; fi
  echo "  missing required text: $2"
  return 1
}

refuse() {
  # $1 = file, $2 = fixed string that must NOT appear in it
  if grep -qF -- "$2" "$1"; then
    echo "  found forbidden text: $2"
    return 1
  fi
  return 0
}

# The step-1 prose window (everything after the fenced flow script's closing
# fence up to step 2's "2. **Probe" line) -- same extraction as
# tests/antz-flow_test.sh's PROSE_STEP1 -- then the single slug-derivation
# bullet inside it. Scoping to the window means a phrase elsewhere in the
# prompt never satisfies a bullet assertion.
step1_window() {
  awk '/^   ```$/{n++; next} /^2\. \*\*Probe/{exit} n>=2' "$1"
}

# =============================================================================
# scoped extracts
# =============================================================================

CUR_STEP1=$(mktemp)
step1_window "$ORCHESTRATOR_PROMPT" > "$CUR_STEP1"
CUR_BULLET=$(mktemp)
grep -m1 -F 'For new work: derive' "$CUR_STEP1" > "$CUR_BULLET"

# HEAD baseline: the repo is a git checkout and this change's work is
# uncommitted (no role ever commits), so HEAD is the pre-change state of the
# prompt and of the flow script.
HEAD_PROMPT=$(mktemp)
git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$HEAD_PROMPT" 2>/dev/null \
  || { echo "FATAL: cannot read HEAD:agents/prompts/orchestrator.prompt"; exit 1; }
HEAD_STEP1=$(mktemp)
step1_window "$HEAD_PROMPT" > "$HEAD_STEP1"
HEAD_BULLET=$(mktemp)
grep -m1 -F 'For new work: derive' "$HEAD_STEP1" > "$HEAD_BULLET"

# The collision-rule tail: everything from "from the raw request," to the end
# of the bullet. In the pre-change state this is HEAD's whole collision rule;
# sluglimit-02 pins that it survives byte-identical while the head of the
# bullet gains the length limit.
tail_of() {
  awk '{ i = index($0, "from the raw request,"); if (i) print substr($0, i) }' "$1"
}

# The flow script's mechanical length limit, read off the bad_slug gate line
# (`[ "${#slug}" -le 40 ] || { echo 'state=bad_slug'; ...`).
flow_limit() {
  grep -F "state=bad_slug" "$FLOW_SH" \
    | grep -oE -- '-le [0-9]+' | head -n 1 | sed 's/^-le //'
}

# =============================================================================
# sluglimit-01: the derivation bullet states the length limit -- the derived
# slug is at most 40 characters, the flow script's mechanical `state=bad_slug`
# limit, in place of the undefined "short"; the intent is that a derived slug
# passes the gate rather than relying on the gate as a catch. The stated
# number equals the script's mechanical value, and the script itself is
# byte-unchanged (the rule already landed in flow-script-guards).
# =============================================================================
test_sluglimit_01() {
  ok=0
  # Given: the bullet is step 1's slug-derivation bullet, one line, unique.
  [ -s "$CUR_BULLET" ] || { echo "  no 'For new work: derive' bullet in step 1"; return 1; }
  n=$(grep -c -F 'For new work: derive' "$CUR_STEP1")
  [ "$n" -eq 1 ] || { echo "  $n bullets match 'For new work: derive', expected 1"; ok=1; }

  # The length limit is stated: at most 40 characters -- the flow script's
  # mechanical limit (the bad_slug gate) named in place.
  require "$CUR_BULLET" 'at most 40 characters' || ok=1
  require "$CUR_BULLET" 'state=bad_slug' || ok=1
  require "$CUR_BULLET" 'length limit' || ok=1

  # In place of the undefined "short": the word is gone from the bullet, and
  # the kebab-case character-class half of the rule survives the reword.
  refuse "$CUR_BULLET" 'short' || ok=1
  require "$CUR_BULLET" 'kebab-case' || ok=1

  # The intent: a derived slug passes the gate rather than relying on it as
  # a catch.
  require "$CUR_BULLET" 'passes that gate rather than relying on it as a catch' || ok=1

  # The stated limit is the script's mechanical limit: the number in the
  # bullet equals the `-le` value on the bad_slug gate line.
  limit=$(flow_limit)
  [ -n "$limit" ] || { echo "  could not read the -le length limit from antz-flow.sh's bad_slug gate"; return 1; }
  require "$CUR_BULLET" "at most $limit characters" \
    || { echo "  the bullet's stated limit does not equal the flow script's mechanical -le $limit"; ok=1; }

  # Invariant: scripts/orchestration/antz-flow.sh is byte-unchanged by this
  # sub-spec (the mechanical rule already landed in flow-script-guards).
  git -C "$SCRIPT_DIR" diff --quiet HEAD -- scripts/orchestration/antz-flow.sh \
    || { echo "  scripts/orchestration/antz-flow.sh differs from HEAD (must stay byte-unchanged)"; ok=1; }
  return $ok
}

# =============================================================================
# sluglimit-02: the collision rules keep their pinned meaning. The suffix
# rule ("-2", ... only when the request continues an existing, already-claimed
# change) with the checks against spdd/changes/, spdd/archive/, and
# `git branch --list 'antz/*'`, and the ask-the-user stop on a semantically
# unclear continuation (flow-07's waiting-user slug-ambiguity stop) -- never a
# bare "-2" suffix without semantic continuation. Mechanically: the bullet's
# collision tail is byte-identical to HEAD's, and the only line of the whole
# prompt that differs from HEAD is the derivation bullet itself -- the
# ensure-state meanings, the four tables, the numbered steps ending at 6, the
# fence count, and the dedup guard's exactly-two exceptions keep their pinned
# content (flow-09, orchestrator-06).
# =============================================================================
test_sluglimit_02() {
  ok=0

  # The collision rule survives byte-identical: everything from "from the raw
  # request," onward equals HEAD's (the rule was not reworded by the edit).
  CUR_TAIL=$(tail_of "$CUR_BULLET")
  HEAD_TAIL=$(tail_of "$HEAD_BULLET")
  [ -n "$HEAD_TAIL" ] || { echo "  HEAD's derivation bullet has no 'from the raw request,' tail"; return 1; }
  [ "$CUR_TAIL" = "$HEAD_TAIL" ] \
    || { echo "  the collision-rule tail is not byte-identical to HEAD's"; ok=1; }

  # The pinned collision meanings, read off the bullet itself:
  # suffix only on continuation, with all three collision checks named.
  require "$CUR_BULLET" "checked against \`spdd/changes/\`, \`spdd/archive/\`, and \`git branch --list 'antz/*'\` for collisions" || ok=1
  require "$CUR_BULLET" 'suffix (`-2`, ... ) only if the request continues an existing change and thus the slug is claimed' || ok=1
  # ask on an unclear continuation -- the waiting-user slug-ambiguity stop
  # (flow-07): never a bare "-2" suffix without semantic continuation.
  require "$CUR_BULLET" 'when the request'"'"'s continuation of an already-claimed slug is semantically unclear, stop and ask the user' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'slug-ambiguity stop (no unambiguous on-disk candidate, or a semantically unclear continuation of an already-claimed slug)' || ok=1

  # Invariant: only the derivation bullet changes in the prompt -- the diff
  # vs HEAD is exactly one removed line and one added line, and they are the
  # HEAD and working bullets verbatim.
  DIFF=$(git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/orchestrator.prompt)
  minus=$(printf '%s\n' "$DIFF" | grep -cE '^-[^-]')
  plus=$(printf '%s\n' "$DIFF" | grep -cE '^\+[^+]')
  [ "$minus" -eq 1 ] || { echo "  the prompt diff removes $minus lines, expected exactly 1"; ok=1; }
  [ "$plus" -eq 1 ] || { echo "  the prompt diff adds $plus lines, expected exactly 1"; ok=1; }
  printf '%s\n' "$DIFF" | grep -E '^-[^-]' | sed 's/^-//' > /tmp/sluglimit.removed.$$
  printf '%s\n' "$DIFF" | grep -E '^\+[^+]' | sed 's/^+//' > /tmp/sluglimit.added.$$
  cmp -s /tmp/sluglimit.removed.$$ "$HEAD_BULLET" \
    || { echo "  the removed line is not HEAD's slug-derivation bullet"; ok=1; }
  cmp -s /tmp/sluglimit.added.$$ "$CUR_BULLET" \
    || { echo "  the added line is not the working slug-derivation bullet"; ok=1; }
  rm -f /tmp/sluglimit.removed.$$ /tmp/sluglimit.added.$$

  # The pinned surrounding structure keeps its content (flow-09,
  # orchestrator-06): numbered steps still end at 6, the fence count and the
  # tables are unchanged vs HEAD, the dedup guard keeps its exactly-two
  # exceptions.
  require "$ORCHESTRATOR_PROMPT" '6. On a fresh rejection' || ok=1
  if grep -qE '^7\. ' "$ORCHESTRATOR_PROMPT"; then
    echo "  a step 7 exists (numbered steps must end at 6)"; ok=1
  fi
  wf=$(grep -cE '^   ```(sh)?$' "$ORCHESTRATOR_PROMPT")
  hf=$(grep -cE '^   ```(sh)?$' "$HEAD_PROMPT")
  [ "$wf" -eq "$hf" ] || { echo "  fence count $wf differs from HEAD's $hf"; ok=1; }
  wt=$(grep -c '^|' "$ORCHESTRATOR_PROMPT")
  ht=$(grep -c '^|' "$HEAD_PROMPT")
  [ "$wt" -eq "$ht" ] || { echo "  table-row count $wt differs from HEAD's $ht"; ok=1; }
  require "$ORCHESTRATOR_PROMPT" '| discover output | Meaning / action |' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'exactly two exceptions, both step 4' || ok=1
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "sluglimit-01: the step 1 slug-derivation bullet states the derived slug is at most 40 characters -- the flow script's mechanical state=bad_slug length limit, matched to its -le value -- in place of the undefined short, so a derived slug passes the gate rather than relying on it as a catch" test_sluglimit_01
run_test "sluglimit-02: the bullet keeps the collision rules' pinned meaning -- suffix only on continuation with the spdd/changes/, spdd/archive/ and antz/* collision checks, and the ask-the-user stop on a semantically unclear continuation -- while the only prompt line changed vs HEAD is the derivation bullet itself" test_sluglimit_02

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
