#!/usr/bin/env bash
# Unit tests for the session guards added to agents/prompts/orchestrator.prompt,
# covering every unit-level scenario in
# spdd/changes/orchestrator-fast-path/04-sessionguards.feature
# (sessionguards-01..04).
#
# The guards are prose law, like the never-delegate-outside-the-three-roles
# rule: not tool-enforced on every client, binding regardless of what the tool
# grant technically allows. They govern one orchestrator invocation's
# delegations:
#   (a) dedup -- the same (sub-spec, role) pair is never delegated twice in
#       one invocation, with the single carve-out of step 4's bounded-retry
#       relay (still bounded by REJECTED.md);
#   (b) latch -- after any stop-and-report outcome, no further delegation of
#       any kind in that same session; resumption is always a fresh
#       invocation.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/skills-activation-prompts_test.sh. Run directly:
#   ./tests/orchestrator-sessionguards_test.sh
#
# Every reported test name embeds its scenario id so a failure maps straight
# back to the scenario it covers. All content assertions are static greps on
# the prompt text (the guards are prose law, not machinery); the
# sessionguards-04 additive-vs-HEAD guard mirrors the re-scoped guard of
# tests/orchestrator-skills-block_test.sh (testharness-03): removed lines are
# permitted only inside the three script fences.
#
# Evolved by change orchestrator-fast-path (sub-spec 05, receipts): the
# prompt's step-3 classification prose is legitimately rewritten (from
# run-the-suite classification to receipt-file reading), so sessionguards-04's
# real-tree removals check is gated on the prompt's prose (the file minus its
# fenced blocks) being unchanged vs HEAD. While the receipt rewrite is
# uncommitted it is vacuously retired with a loud note (not a failure -- same
# convention as tests/renderinject_test.sh's base-render gate); the
# structural assertions (steps 1-6 in order, tables survive, constraints
# only) stay enforced forever.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
FLOW_SCRIPT="$SCRIPT_DIR/scripts/orchestration/antz-flow.sh"
PROBE_SCRIPT="$SCRIPT_DIR/scripts/orchestration/antz-probe.sh"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/skills-activation-prompts_test.sh) -----

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

skip_test() {
  # $1 = reported test name (must contain its scenario id), $2 = reason.
  # An explicit, accounted-for stub for a scenario that is out of scope for
  # unit-level TDD (never a silent omission) -- same helper as
  # tests/versioning-rule_test.sh.
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
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

# Extract a "## <name>" section (its own heading line down to the next top
# level "## " heading or EOF) from $1 into $2.
extract_section() {
  # $1 = file, $2 = heading text, $3 = output file
  awk -v sec="$2" '
    $0 == "## " sec { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  ' "$1" > "$3"
}

# ---- the Process section (the guards live inside it, at its end) -------------

PROCESS=$(mktemp)
extract_section "$ORCHESTRATOR_PROMPT" "Process" "$PROCESS"

# ---- sessionguards-04: the additive-vs-HEAD guard helpers --------------------
# Mirrored from tests/orchestrator-skills-block_test.sh (testharness-03's
# re-scope): each of the prompt's three script fences is located by shape --
# flow (the first 3-space bare fence), skills (the fence carrying the
# antz-skills.sh include marker, or the pre-change marker comment as the
# fallback for the HEAD copy), probe (the 3-space ```sh fence) -- and a
# removed diff line is permitted only inside one of those fenced bodies on
# the old side. Any removal outside the three fenced bodies fails.

region_from_opener() {
  # $1 = file, $2 = 1-based line number of a fence opener. Prints
  # "opener closer" when the fence closes, nothing (non-zero) otherwise.
  close=$(awk -v o="$2" 'NR > o && /^ *```$/ { print NR; exit }' "$1")
  if [ -n "$close" ] && [ "$close" -gt "$2" ]; then
    printf '%s %s' "$2" "$close"
    return 0
  fi
  return 1
}

region_enclosing_line() {
  # $1 = file, $2 = 1-based line number of a line inside the fence. Prints
  # "opener closer" for the fence enclosing that line.
  open=$(awk -v tgt="$2" 'NR < tgt && /^ *```(sh)?$/ { l = NR } END { print l + 0 }' "$1")
  [ "$open" -gt 0 ] || return 1
  region_from_opener "$1" "$open"
}

compute_fence_regions() {
  # $1 = prompt file; sets FENCE_REGIONS="s1 e1 s2 e2 s3 e3" for the three
  # script fences. Fails (non-zero, FENCE_REGIONS empty) when any is missing.
  f="$1"
  FENCE_REGIONS=""
  fl=$(grep -nE '^   ```$' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$fl" ] || { echo "  no flow fence found in $f" >&2; return 1; }
  r=$(region_from_opener "$f" "$fl") || { echo "  flow fence does not close" >&2; return 1; }
  FENCE_REGIONS="$r"
  sl=$(grep -nE '^ *# antz-include: scripts/orchestration/antz-skills\.sh' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$sl" ] || sl=$(grep -nE '^ *# antz-skills\.sh' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$sl" ] || { echo "  no antz-skills marker found in $f" >&2; return 1; }
  r=$(region_enclosing_line "$f" "$sl") || { echo "  skills fence not locatable" >&2; return 1; }
  FENCE_REGIONS="$FENCE_REGIONS $r"
  pl=$(grep -nE '^   ```sh$' "$f" | head -n 1 | cut -d: -f1)
  [ -n "$pl" ] || { echo "  no probe fence found in $f" >&2; return 1; }
  r=$(region_from_opener "$f" "$pl") || { echo "  probe fence does not close" >&2; return 1; }
  FENCE_REGIONS="$FENCE_REGIONS $r"
}

removals_outside_regions() {
  # $1 = unified diff file; $2 = old-side regions, $3 = new-side regions
  # (each a flat "opener closer opener closer ..." list). Prints every
  # removed diff line lying outside the three script fences on BOTH sides;
  # empty output means the guard passes.
  awk -v oldr="$2" -v newr="$3" '
    BEGIN {
      on = split(oldr, oa, /[[:space:]]+/)
      ocount = int(on / 2)
      for (i = 1; i <= ocount; i++) { os[i] = oa[2*i - 1] + 0; oe[i] = oa[2*i] + 0 }
      nn = split(newr, na, /[[:space:]]+/)
      ncount = int(nn / 2)
      for (i = 1; i <= ncount; i++) { ns[i] = na[2*i - 1] + 0; ne[i] = na[2*i] + 0 }
    }
    /^@@ / {
      old = $2; new = $3
      sub(/^-/, "", old); sub(/^\+/, "", new)
      split(old, a, ","); oline = a[1] + 0
      split(new, b, ","); nline = b[1] + 0
      next
    }
    /^---/ { next }
    /^\+\+\+/ { next }
    /^\\/ { next }
    /^\+/ { nline++; next }
    /^-/ {
      inside = 0
      for (i = 1; i <= ocount; i++) if (os[i] > 0 && oline >= os[i] && oline <= oe[i]) inside = 1
      for (i = 1; i <= ncount; i++) if (ns[i] > 0 && nline >= ns[i] && nline <= ne[i]) inside = 1
      if (!inside) print
      oline++
      next
    }
    /^ / { oline++; nline++; next }
  ' "$1"
}

# Prints 1 when the working orchestrator.prompt's prose (the file minus its
# fenced blocks) differs from HEAD's copy -- a later sub-spec's legitimate
# prose edit -- and 0 when it doesn't (or HEAD's copy is unreadable, in
# which case there is nothing to compare against).
prompt_prose_distinct_from_head() {
  work=$(mktemp)
  basep=$(mktemp)
  awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$ORCHESTRATOR_PROMPT" > "$work"
  if git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$basep" 2>/dev/null; then
    awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$basep" > "$basep"
    cmp -s "$work" "$basep" && { printf '0'; rm -f "$work" "$basep"; return 0; }
    printf '1'
  else
    printf '0'
  fi
  rm -f "$work" "$basep"
}

# =============================================================================
# sessionguards-01: the dedup law -- within one orchestrator invocation the
# same (sub-spec, role) pair is never delegated twice; once a pair has been
# delegated, later flow steps route by the existing state machine (fresh
# classification from disk, the bounded retry, the stops) and never by
# re-delegating that pair. The single carve-out: step 4's bounded-retry relay
# of attributable blockers to the named sub-spec's coder session is the one
# permitted second delegation of a pair, still bounded by REJECTED.md (at
# most one relay per pair per entry; a second entry stops the flow for good).
# =============================================================================
test_sessionguards_01() {
  ok=0
  # The law itself: same (sub-spec, role) pair, never twice, per invocation.
  require "$PROCESS" 'the same (sub-spec, role) pair is never delegated twice' || ok=1
  require "$PROCESS" 'Within one invocation' || ok=1
  # Routing, not re-delegating: the existing state machine stays the path.
  require "$PROCESS" 'once a pair has been delegated' || ok=1
  require "$PROCESS" 'route by the existing state machine' || ok=1
  require "$PROCESS" 'fresh classification from disk' || ok=1
  require "$PROCESS" 'never by re-delegating that pair' || ok=1
  # The single carve-out: step 4's bounded-retry relay, still REJECTED.md-
  # bounded (one relay per pair per entry; the second entry stops the flow).
  require "$PROCESS" 'single carve-out' || ok=1
  require "$PROCESS" "step 4's bounded-retry relay" || ok=1
  require "$PROCESS" 'the one permitted second delegation of a pair' || ok=1
  require "$PROCESS" 'at most one relay per pair per entry' || ok=1
  require "$PROCESS" 'a second entry stops the flow for good' || ok=1
  # Per-invocation scoping: a later invocation starts with a clean slate.
  require "$PROCESS" 'a later orchestrator invocation starts with a clean slate' || ok=1
  require "$PROCESS" 'resume is a fresh session' || ok=1
  # Prompt-level law standing: binds regardless of the tool grant, like the
  # never-delegate-outside-the-three-roles rule.
  require "$PROCESS" 'regardless of what the tool grant technically allows' || ok=1
  require "$PROCESS" 'never-delegate-outside-the-three-roles rule' || ok=1
  return $ok
}

# =============================================================================
# sessionguards-02: the latch law -- after any stop-and-report outcome the
# session performs no further delegation of any kind, reporting and ending
# instead, with resumption always a fresh invocation; the stop outcomes it
# names include at least open_questions=yes, the flow script's machine-line
# stops, a BLOCKED:-reasoned sub-spec found in classification,
# rejected_count=2, a non-attributable blocker in a rejected entry, and a
# slug-ambiguity stop.
# =============================================================================
test_sessionguards_02() {
  ok=0
  # The law itself: after any stop, no further delegation; end by reporting.
  require "$PROCESS" 'After any stop-and-report outcome' || ok=1
  require "$PROCESS" 'no further delegation of any kind' || ok=1
  require "$PROCESS" 'reports and ends instead' || ok=1
  require "$PROCESS" 'resumption is always a fresh invocation' || ok=1
  # Every named stop outcome is covered.
  require "$PROCESS" 'open_questions=yes' || ok=1
  require "$PROCESS" 'state=no_git' || ok=1
  require "$PROCESS" 'state=no_repo' || ok=1
  require "$PROCESS" 'state=no_commits' || ok=1
  require "$PROCESS" 'state=checkout_refused' || ok=1
  require "$PROCESS" 'state=no_branch' || ok=1
  require "$PROCESS" 'branch=missing' || ok=1
  require "$PROCESS" 'change_dir=missing' || ok=1
  require "$PROCESS" 'gate=refused reason=' || ok=1
  require "$PROCESS" 'a `BLOCKED:`-reasoned sub-spec found in classification' || ok=1
  require "$PROCESS" 'rejected_count=2' || ok=1
  require "$PROCESS" 'a non-attributable blocker in a rejected entry' || ok=1
  require "$PROCESS" 'a slug-ambiguity stop (no unambiguous on-disk candidate)' || ok=1
  # Latch scope: delegation only -- the orchestrator's own read-only probing
  # (re-running the flow/probe scripts) is unchanged.
  require "$PROCESS" 'The latch covers delegation only' || ok=1
  require "$PROCESS" 'read-only probing' || ok=1
  return $ok
}

# =============================================================================
# sessionguards-03: the guards are pure prose law -- no new embedded or
# extracted script, no new flow subcommand, no new probe field, and no file
# under spdd/ records delegation history for them; the session's own account
# of the delegations it already made is the mechanism the prompt instructs it
# to apply.
# =============================================================================
test_sessionguards_03() {
  ok=0
  # The prompt states the mechanism: the session's own account, nothing
  # written to disk for it.
  require "$PROCESS" "own account of the delegations it has already made" || ok=1
  require "$PROCESS" 'nothing is written to disk' || ok=1
  # No new extracted script: scripts/orchestration/ still holds exactly the
  # three pre-existing script files.
  n=$(ls "$SCRIPT_DIR/scripts/orchestration/"*.sh 2>/dev/null | wc -l)
  [ "$n" -eq 3 ] || { echo "  scripts/orchestration/ holds $n scripts (expected 3)"; ok=1; }
  # (Loop variables never reuse run_test's global "name".)
  for script in antz-flow antz-probe antz-skills; do
    [ -f "$SCRIPT_DIR/scripts/orchestration/$script.sh" ] \
      || { echo "  missing pre-existing script: $script.sh"; ok=1; }
  done
  # No new embedded script: the prompt's three script fences still carry
  # exactly their include markers, each naming an existing file.
  for script in antz-flow antz-probe antz-skills; do
    c=$(grep -cF "# antz-include: scripts/orchestration/$script.sh" "$ORCHESTRATOR_PROMPT")
    [ "$c" -eq 1 ] || { echo "  expected exactly 1 include marker for $script.sh, got: $c"; ok=1; }
  done
  # No new flow subcommand: the usage line still names exactly the four
  # pre-existing subcommands.
  require "$FLOW_SCRIPT" 'discover | ensure <slug> | state <slug> <probe-path> | release <slug>' || ok=1
  # No new probe field: the probe's output vocabulary still names only the
  # pre-existing fields (no delegation-history emission).
  refuse "$PROBE_SCRIPT" 'delegations=' || ok=1
  refuse "$PROBE_SCRIPT" 'delegated=' || ok=1
  # No file under spdd/ records delegation history for the guards.
  ledger=$(find "$SCRIPT_DIR/spdd" -type f \( -iname '*deleg*' -o -iname '*ledger*' \) 2>/dev/null)
  [ -z "$ledger" ] || { echo "  delegation-history file(s) under spdd/: $ledger"; ok=1; }
  return $ok
}

# =============================================================================
# sessionguards-04: everything else in the prompt keeps its meaning -- the
# guards' diff vs HEAD is purely additive outside the three script fences,
# the steps keep their order, the existing tables and sections survive, and
# the guards add constraints only (never re-routing an existing outcome).
# =============================================================================
test_sessionguards_04() {
  ok=0
  # The guards state themselves as constraint-only additions.
  require "$PROCESS" 'They add constraints only' || ok=1
  require "$PROCESS" 'never re-route an existing outcome' || ok=1
  # Steps 1-6 keep their numbering and order (the column-0 numbered-step
  # headings, in file order, must read 1..6; fence content is indented, so
  # column-0 matches only the steps).
  step_nums=$(grep -nE '^[0-9]+\. ' "$ORCHESTRATOR_PROMPT" | cut -d: -f2 \
    | sed -E 's/^([0-9]+)\..*/\1/' | tr '\n' ' ')
  [ "$step_nums" = "1 2 3 4 5 6 " ] \
    || { echo "  numbered steps changed: $step_nums (expected 1..6 in order)"; ok=1; }
  # The existing tables and sections survive.
  require "$ORCHESTRATOR_PROMPT" '| discover output | Meaning / action |' || ok=1
  require "$ORCHESTRATOR_PROMPT" '| Output | Meaning |' || ok=1
  require "$ORCHESTRATOR_PROMPT" '| `rejected_count` | Action |' || ok=1
  require "$ORCHESTRATOR_PROMPT" '| release output | Meaning / action |' || ok=1
  require "$ORCHESTRATOR_PROMPT" '## Report Format' || ok=1
  # The guards' diff vs HEAD is purely additive outside the three script
  # fences: no pre-change line outside them was removed or reworded. Gated
  # per the header note on the prompt prose being unchanged vs HEAD (the
  # receipts sub-spec's step-3 rewrite retires this check with a loud note).
  if command -v git >/dev/null 2>&1 && [ -e "$SCRIPT_DIR/.git" ] \
     && git -C "$SCRIPT_DIR" cat-file -e HEAD:agents/prompts/orchestrator.prompt 2>/dev/null; then
    if [ "$(prompt_prose_distinct_from_head)" -eq 1 ]; then
      echo "  note: orchestrator.prompt prose changed vs HEAD (a later sub-spec's legitimate edit); the additive-vs-HEAD removal check is vacuously retired, structural assertions still enforced"
    else
      diff_file=$(mktemp)
      head_prompt=$(mktemp)
      git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/orchestrator.prompt > "$diff_file" \
        || { echo "  git diff failed"; rm -f "$diff_file" "$head_prompt"; return 1; }
      git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt > "$head_prompt" 2>/dev/null
      compute_fence_regions "$head_prompt" \
        || { echo "  could not locate the three script fences in the HEAD copy"; rm -f "$diff_file" "$head_prompt"; return 1; }
      os="$FENCE_REGIONS"
      compute_fence_regions "$ORCHESTRATOR_PROMPT" \
        || { echo "  could not locate the three script fences in the working tree"; rm -f "$diff_file" "$head_prompt"; return 1; }
      ns="$FENCE_REGIONS"
      bad=$(removals_outside_regions "$diff_file" "$os" "$ns")
      if [ -n "$bad" ]; then
        echo "  orchestrator.prompt has removed lines outside the three script fences:"
        printf '%s\n' "$bad"
        ok=1
      fi
      rm -f "$diff_file" "$head_prompt"
    fi
  fi
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "sessionguards-01: the dedup law -- a (sub-spec, role) pair is never delegated twice in one invocation; routing never re-delegates; step 4's bounded-retry relay is the single REJECTED.md-bounded carve-out" test_sessionguards_01
run_test "sessionguards-02: the latch law -- after any stop-and-report outcome no further delegation of any kind, resumption is a fresh invocation, and every named stop outcome is covered" test_sessionguards_02
run_test "sessionguards-03: pure prose law -- no new script, no new flow subcommand, no new probe field, no delegation ledger under spdd/, mechanism is the session's own account" test_sessionguards_03
run_test "sessionguards-04: everything else keeps its meaning -- additive outside the three script fences, steps 1-6 in order, tables survive, constraints only" test_sessionguards_04

# ---- e2e-only scenario: explicit SKIP stub -----------------------------------
# e2e-04 (spdd/changes/orchestrator-fast-path/07-e2e.feature) is the change's
# verifier-owned end-to-end QA suite: the guards' observable behavior (a
# BLOCKED: planning refusal stopping the session for good; a twice-rejected
# change never retried after its second "## Rejection <n>" entry) happens in
# live /antz sessions, which a unit suite cannot spawn -- here the guards are
# asserted as prose law (the guards are not tool-enforced machinery).
# Explicit stub so the scenario id is accounted for (suite convention: see
# tests/versioning-rule_test.sh).
skip_test "e2e-04: in a live flow a BLOCKED: planning refusal stops the session for good with no further delegation, and a twice-rejected change appends two '## Rejection <n>' entries and is never retried again" \
  "e2e-only: observable only in live /antz sessions, run by the verifier (07-e2e.feature)"

rm -f "$PROCESS"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 07-e2e.feature)"
[ "$fail_count" -eq 0 ]
