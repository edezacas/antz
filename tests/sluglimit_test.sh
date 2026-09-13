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
# sluglimit-02's working-vs-HEAD window assertions follow the change_pending()
# gating pattern of tests/bump440_test.sh, tests/bump450_test.sh and
# tests/bump460_test.sh (loud retirement by gating, stacking-robust): the
# window is enforced only while the derivation-bullet reword of
# agents/prompts/orchestrator.prompt is uncommitted (the flow's state), and
# retires vacuously with a loud note once the reword is committed -- a later
# legitimate edit can never resurrect the guard. The pinned-meaning
# assertions read no git HEAD and stay enforced in every repo state (the
# durable coverage once the window retires).
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
  # Re-keyed by change deembed-orchestration-scripts (sub-spec 05): the
  # window used to be the fenced region after the step 1 script embed's
  # second fence line -- the embed is gone (scripts are installed files,
  # never prompt content), so the window is the whole step 1 section: the
  # lines between the "1. **Derive" heading and the "2. **Probe" heading
  # (same heading-form extraction the de-embedded prose pins use).
  awk '/^1\. \*\*Derive/{s=1} /^2\. \*\*Probe/{s=0} s' "$1"
}

# =============================================================================
# scoped extracts
# =============================================================================

CUR_STEP1=$(mktemp)
step1_window "$ORCHESTRATOR_PROMPT" > "$CUR_STEP1"
CUR_BULLET=$(mktemp)
grep -m1 -F 'For new work: derive' "$CUR_STEP1" > "$CUR_BULLET"

# HEAD baseline: the repo is a git checkout. While the derivation-bullet
# reword is pending (uncommitted -- the flow's state, no role ever commits),
# HEAD is the pre-change state of the prompt and the window guards built on
# this baseline are enforced; once the reword is committed, the
# change_pending() gate retires those guards with a loud note, so the suite
# passes in both states.
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

head_bullet_states_length_limit() {
  # The reword's marker content: HEAD's slug-derivation bullet states the
  # length limit -- the "at most <n> characters" wording whose <n> is the
  # flow script's mechanical -le value (the wording sluglimit-01 pins in the
  # working bullet, read off HEAD's copy instead).
  limit=$(flow_limit)
  [ -n "$limit" ] && grep -qF "at most $limit characters" "$HEAD_BULLET"
}

change_pending() {
  # True while the derivation-bullet reword of agents/prompts/orchestrator.prompt
  # is uncommitted in the working tree (the flow's state -- no role ever
  # commits): the prompt differs from HEAD AND HEAD's bullet does not yet
  # state the length limit. The conjunction is the stacking lesson recorded
  # by tests/bump440_test.sh, tests/bump450_test.sh and tests/bump460_test.sh:
  # once HEAD carries the reword, any current working diff is a later
  # change's legitimate edit and must not resurrect the window guards
  # against it -- so they retire instead.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- agents/prompts/orchestrator.prompt 2>/dev/null \
    && ! head_bullet_states_length_limit
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
# bare "-2" suffix without semantic continuation. The pinned-meaning
# assertions never read git HEAD: they hold in every repo state and are the
# durable coverage once the window retires. The working-vs-HEAD window
# assertions (the collision tail byte-identical to HEAD's, the diff vs HEAD
# removing exactly one line and adding exactly one with verbatim bullet
# identity, and the fence-count and table-row-count equality vs HEAD's) are
# gated by change_pending(): enforced while the derivation-bullet reword is
# pending (uncommitted), retired with a loud note once committed -- the test
# stays registered and passes in both states (flow-09, orchestrator-06).
# =============================================================================
test_sluglimit_02() {
  ok=0

  # The pinned collision meanings, read off the working bullet itself --
  # absolute, no git HEAD read, enforced in every repo state: suffix only
  # on continuation, with all three collision checks named.
  require "$CUR_BULLET" "checked against \`spdd/changes/\`, \`spdd/archive/\`, and \`git branch --list 'antz/*'\` for collisions" || ok=1
  require "$CUR_BULLET" 'suffix (`-2`, ... ) only if the request continues an existing change and thus the slug is claimed' || ok=1
  # ask on an unclear continuation -- the waiting-user slug-ambiguity stop
  # (flow-07): never a bare "-2" suffix without semantic continuation.
  require "$CUR_BULLET" 'when the request'"'"'s continuation of an already-claimed slug is semantically unclear, stop and ask the user' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'slug-ambiguity stop (no unambiguous on-disk candidate, or a semantically unclear continuation of an already-claimed slug)' || ok=1

  # The pinned surrounding structure keeps its content (flow-09,
  # orchestrator-06) -- absolute: numbered steps still end at 6, the
  # discover table's header survives, the dedup guard keeps its exactly-two
  # exceptions.
  require "$ORCHESTRATOR_PROMPT" '6. On a fresh rejection' || ok=1
  if grep -qE '^7\. ' "$ORCHESTRATOR_PROMPT"; then
    echo "  a step 7 exists (numbered steps must end at 6)"; ok=1
  fi
  require "$ORCHESTRATOR_PROMPT" '| discover output | Meaning / action |' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'exactly two exceptions, both step 4' || ok=1

  # The working-vs-HEAD window guards -- gated by change_pending(): enforced
  # only while the derivation-bullet reword is pending, retired with one
  # loud note otherwise (never deleted; the guard keeps its registration).
  if ! change_pending; then
    echo "  note: the working-vs-HEAD window guards on agents/prompts/orchestrator.prompt are vacuously retired -- the derivation-bullet reword is committed vs HEAD (HEAD's bullet already states the length limit, so any current diff is a later change's legitimate edit and must not resurrect these guards); the pinned-meaning assertions above stay enforced"
    return $ok
  fi

  # (pending) The collision rule survives byte-identical: everything from
  # "from the raw request," onward equals HEAD's (the rule was not reworded
  # by the edit).
  CUR_TAIL=$(tail_of "$CUR_BULLET")
  HEAD_TAIL=$(tail_of "$HEAD_BULLET")
  [ -n "$HEAD_TAIL" ] || { echo "  HEAD's derivation bullet has no 'from the raw request,' tail"; return 1; }
  [ "$CUR_TAIL" = "$HEAD_TAIL" ] \
    || { echo "  the collision-rule tail is not byte-identical to HEAD's"; ok=1; }

  # (pending) Invariant: only the derivation bullet changes in the prompt --
  # the diff vs HEAD is exactly one removed line and one added line, and they
  # are the HEAD and working bullets verbatim.
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

  # (pending) The surrounding structure is untouched by the edit: the fence
  # count and the table-row count equal HEAD's.
  wf=$(grep -cE '^   ```(sh)?$' "$ORCHESTRATOR_PROMPT")
  hf=$(grep -cE '^   ```(sh)?$' "$HEAD_PROMPT")
  [ "$wf" -eq "$hf" ] || { echo "  fence count $wf differs from HEAD's $hf"; ok=1; }
  wt=$(grep -c '^|' "$ORCHESTRATOR_PROMPT")
  ht=$(grep -c '^|' "$HEAD_PROMPT")
  [ "$wt" -eq "$ht" ] || { echo "  table-row count $wt differs from HEAD's $ht"; ok=1; }
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "sluglimit-01: the step 1 slug-derivation bullet states the derived slug is at most 40 characters -- the flow script's mechanical state=bad_slug length limit, matched to its -le value -- in place of the undefined short, so a derived slug passes the gate rather than relying on it as a catch" test_sluglimit_01
run_test "sluglimit-02: the bullet keeps the collision rules' pinned meaning -- suffix only on continuation with the spdd/changes/, spdd/archive/ and antz/* collision checks, and the ask-the-user stop on a semantically unclear continuation -- enforced absolutely, while the working-vs-HEAD window guards on orchestrator.prompt (tail identity, the one-removed/one-added diff with verbatim bullet identity, fence/table-count equality) are enforced by the change_pending() gate while the reword is pending and retired with a loud note once committed" test_sluglimit_02

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
