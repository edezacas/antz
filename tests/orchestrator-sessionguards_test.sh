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
#       one invocation, with exactly two exceptions, both step 4's: the
#       attributable-blocker relay to the named sub-spec's coder and the one
#       bounded whole-change verifier retry (still bounded by REJECTED.md);
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
#
# Extended by change flow-script-guards (sub-spec 02): sessionguards-02's
# latch stop list gains the new machine-line stops state=tree_dirty and
# state=bad_slug (its list is "include at least", so the existing scenario
# id stays valid); sessionguards-04's structural assertions keep holding
# while its additive-vs-HEAD prose check self-retires with the loud note
# while 02's prose edit is uncommitted.
#
# Extended by change style-rewrite (sub-spec 05): the orchestrator's two
# 100-130-word blocks -- step 4's rejected_count=1 row and the Session
# guards' **Dedup.** bullet -- are rewritten as short lists with identical
# contracts (relay/retry/stop semantics, exactly-two exceptions, latch).
# The orchprose-01/02/03 tests pin the new shapes against extracts scoped to
# the step-4 and Session guards blocks, and orchprose-03 runs the
# neighboring suites (antz-flow, receipts, status-probe) to prove they pass
# unmodified.
#
# Re-keyed by change deembed-orchestration-scripts (sub-spec 05,
# testsuite-04): the per-script '# antz-include:' marker-count pins in
# sessionguards-03 become the invocation-line form (each script
# path-referenced via __ANTZ_SCRIPTS_DIR__/<name>.sh, no marker anywhere),
# and orchprose-01's structural fence counts move 14/7/1 -> 8/4/0. The
# dedup/latch law assertions and the no-delegation-ledger checks are
# unchanged.

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
# sessionguards-01 (amended by fix-orchestrator-flow 1.2): the dedup law --
# within one orchestrator invocation the same (sub-spec, role) pair is never
# delegated twice; once a pair has been delegated, later flow steps route by
# the existing state machine (fresh classification from disk, the bounded
# retry, the stops) and never by re-delegating that pair. Exactly two
# exceptions, both step 4's: relaying each attributable blocker to the
# sub-spec's coder session (at most one relay per pair per entry; a second
# entry stops the flow for good), and the one bounded whole-change verifier
# retry (bounded by REJECTED.md: the count reaching 2 stops the flow for
# good). No third exception: the specifier is never re-delegated within an
# invocation.
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
  # Exactly two exceptions, both step 4's, each still REJECTED.md-bounded:
  # the attributable-blocker relay, and the one whole-change verifier retry.
  require "$PROCESS" 'exactly two exceptions, both step 4' || ok=1
  require "$PROCESS" 'relaying each attributable blocker to the `coder` session for the sub-spec it names' || ok=1
  require "$PROCESS" 'at most one relay per pair per entry' || ok=1
  require "$PROCESS" 'a second entry stops the flow for good' || ok=1
  require "$PROCESS" 'the one bounded whole-change `verifier` retry' || ok=1
  require "$PROCESS" 'bounded by `REJECTED.md`: the count reaching 2 stops the flow for good' || ok=1
  # No third exception: the specifier is never re-delegated.
  require "$PROCESS" 'No third exception exists' || ok=1
  require "$PROCESS" 'the specifier is never re-delegated within an invocation' || ok=1
  # Per-invocation scoping: a later invocation starts with a clean slate.
  require "$PROCESS" 'a later orchestrator invocation starts with a clean slate' || ok=1
  require "$PROCESS" 'resume is a fresh session' || ok=1
  # Prompt-level law standing: binds regardless of the tool grant, like the
  # never-delegate-outside-the-three-roles rule.
  require "$PROCESS" 'regardless of what the tool grant technically allows' || ok=1
  require "$PROCESS" 'never-delegate-outside-the-three-roles rule' || ok=1
  # The superseded "single carve-out" framing is gone (flow-06's closure).
  refuse "$PROCESS" 'single carve-out' || ok=1
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
  # The list is "include at least", so it stays valid while being extended:
  # change flow-script-guards (sub-spec 02) adds the two new machine-line
  # stops, and documents the dirty=yes advisory as explicitly not a stop.
  # (The line-scoped latch/report assertions live in tests/antz-flow_test.sh,
  # test_orchestrator_06_latch_and_report_stops.)
  require "$PROCESS" 'state=tree_dirty' || ok=1
  require "$PROCESS" 'state=bad_slug' || ok=1
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
  # No new embedded script: re-keyed by change deembed-orchestration-scripts
  # (testsuite-04) from the include-marker counts to the invocation-line
  # form — each script is path-referenced in the prompt (one path-reference
  # invocation per script at minimum), and no include marker exists anywhere.
  for script in antz-flow antz-probe antz-skills; do
    c=$(grep -cF "__ANTZ_SCRIPTS_DIR__/$script.sh" "$ORCHESTRATOR_PROMPT")
    [ "$c" -ge 1 ] \
      || { echo "  no __ANTZ_SCRIPTS_DIR__ path reference for $script.sh, got: $c"; ok=1; }
  done
  m=$(grep -cF "# antz-include:" "$ORCHESTRATOR_PROMPT")
  [ "$m" -eq 0 ] || { echo "  expected no include marker anywhere, got: $m"; ok=1; }
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

# ---- change style-rewrite (sub-spec 05): scoped extracts for the two lists ----
#
# The orchprose-01/02 shape pins read section-scoped extracts, never the bare
# prompt, so a stray mention elsewhere can't satisfy them (the convention of
# tests/antz-flow_test.sh's prose extracts). The step-4 extract is byte-same
# as tests/receipts_test.sh's STEP4; the Session guards extract is byte-same
# as tests/antz-flow_test.sh's PROSE_GUARDS.

# Step 4: from its numbered heading to step 5's heading (the rejected_count
# table, the short row cells, and the relay bullet list under the table).
STEP4=$(mktemp)
awk '/^4\. Once every sub-spec is `done`/ { flag=1 }
     /^5\. / { flag=0 }
     flag { print }' "$ORCHESTRATOR_PROMPT" > "$STEP4"

# The Session guards block (dedup + latch bullets): from its bold heading to
# the "## Report Format" section.
GUARDS=$(mktemp)
awk '/^\*\*Session guards/{s=1} /^## Report Format/{s=0} s' "$ORCHESTRATOR_PROMPT" > "$GUARDS"

# This suite's own source file (the orchprose-03 registration check reads it).
SELF="$SCRIPT_DIR/tests/orchestrator-sessionguards_test.sh"

# =============================================================================
# orchprose-01 (change style-rewrite, sub-spec 05): step 4's rejected_count=1
# row is shortened to the routing instruction itself, and the relay detail
# moves to a short bullet list directly under the step-4 table -- one item per
# outcome with the same meaning as before (relay to the named sub-spec's
# coder unconditionally; the orchestrated verifier retry when the entry holds
# no non-attributable blocker; stop-and-report naming the manual verifier
# pass when it holds one). The rejected_count=0 and rejected_count=2 rows are
# byte-unchanged, and the structure pins hold: four tables, 8 fence lines /
# 4 blocks with no ```sh fence (re-keyed by change
# deembed-orchestration-scripts, testsuite-04, from the embedded era's 14/7/
# one-sh-fence counts), steps ending at 6, no new fenced block.
# =============================================================================
test_orchprose_01() {
  ok=0
  # The row: exactly one, still reading as the routing instruction.
  n=$(grep -c '^   | 1 |' "$STEP4")
  [ "$n" -eq 1 ] || { echo "  step-4 table has $n '| 1 |' rows (expected 1)"; ok=1; }
  row1=$(grep '^   | 1 |' "$STEP4" | head -n 1)
  if ! printf '%s\n' "$row1" | grep -qF 'Read `REJECTED.md`'"'"'s one entry from disk (from the working root — never from conversational memory)'; then
    echo "  the rejected_count=1 row dropped the read-from-disk instruction"; ok=1
  fi
  if ! printf '%s\n' "$row1" | grep -qF 'Relay each attributable blocker per the rules below'; then
    echo "  the rejected_count=1 row does not route to the rules below"; ok=1
  fi
  # The row is short: the relay detail lives in the list under the table.
  if printf '%s\n' "$row1" | grep -qF 'unconditionally'; then
    echo "  the rejected_count=1 row still carries the relay detail inline"; ok=1
  fi
  # The list sits directly under the table: the first non-blank line after
  # the rejected_count=2 row is a bullet, and there are exactly three.
  first=$(awk '/^   \| 2 \|/ {s=1; next} s && NF {print; exit}' "$STEP4")
  case $first in
    '   - '*) ;;
    *) echo "  no bullet list directly under the step-4 table (first line after it: $first)"; ok=1 ;;
  esac
  list=$(awk '/^   \| 2 \|/ {s=1; next} s' "$STEP4")
  n=$(printf '%s\n' "$list" | grep -c '^   - ')
  [ "$n" -eq 3 ] || { echo "  the relay list has $n bullets (expected 3)"; ok=1; }
  # One item per outcome, same meaning preserved.
  item1=$(printf '%s\n' "$list" | grep '^   - ' | sed -n '1p')
  item2=$(printf '%s\n' "$list" | grep '^   - ' | sed -n '2p')
  item3=$(printf '%s\n' "$list" | grep '^   - ' | sed -n '3p')
  pin_item() {
    # $1 = bullet text, $2 = required fragment, $3 = label
    if ! printf '%s' "$1" | grep -qF -- "$2"; then
      echo "  $3 missing: $2"; ok=1
    fi
  }
  pin_item "$item1" 'Relay each attributable blocker to the `coder` session for the sub-spec it names' 'relay bullet 1'
  pin_item "$item1" 'unconditionally' 'relay bullet 1'
  pin_item "$item1" 'a repeat relay just no-ops in `coder`' 'relay bullet 1'
  pin_item "$item1" 'an unrelayed one can burn the retry' 'relay bullet 1'
  pin_item "$item2" 'non-attributable blocker in that entry -> delegate the whole change to `verifier` once more, the one bounded retry, orchestrated' 'relay bullet 2'
  pin_item "$item3" 'Any non-attributable blocker (doesn'"'"'t trace to a single sub-spec — cross-feature coherence, an e2e QA step) -> stop and report instead, naming the resume action explicitly' 'relay bullet 3'
  pin_item "$item3" 'the user resolves it (themselves, or via a new `specifier` round), then invokes `verifier` directly' 'relay bullet 3'
  pin_item "$item3" 'That manual pass *is* the bounded retry' 'relay bullet 3'
  pin_item "$item3" 'never delegate it yourself' 'relay bullet 3'
  # The rejected_count=0 and rejected_count=2 rows are byte-unchanged (the
  # exact approved row texts, pinned as literals from the pre-rewrite table).
  require "$STEP4" '   | 0 | Delegate the whole change to `verifier`, once (never once per sub-spec — its archive step moves the whole directory). |' || ok=1
  require "$STEP4" '   | 2 | The bounded retry already happened and was rejected again. Stop, report both entries verbatim, and never invoke `coder` or `verifier` again for this change. |' || ok=1
  # The structure pins hold: exactly four tables (four |---|---| separators),
  # 8 fence lines / 4 blocks with no ```sh fence (the no-new-fenced-block
  # check re-keyed by change deembed-orchestration-scripts, testsuite-04: the
  # former 14 lines / 7 blocks / one probe fence belonged to the embed era),
  # and the numbered steps still ending at 6 with no step 7.
  tables=$(grep -cE '^ *\|---\|---\| *$' "$ORCHESTRATOR_PROMPT")
  [ "$tables" -eq 4 ] || { echo "  expected 4 tables, got $tables |---|---| separators"; ok=1; }
  fences=$(grep -cE '^   ```$' "$ORCHESTRATOR_PROMPT")
  [ "$fences" -eq 8 ] || { echo "  expected 8 fence lines (4 blocks), got: $fences"; ok=1; }
  shfences=$(grep -c '^   ```sh$' "$ORCHESTRATOR_PROMPT")
  [ "$shfences" -eq 0 ] || { echo "  expected no sh-fence openers, got: $shfences"; ok=1; }
  require "$ORCHESTRATOR_PROMPT" '6. On a fresh rejection' || ok=1
  if grep -qE '^7\. ' "$ORCHESTRATOR_PROMPT"; then
    echo "  a new process step appeared"; ok=1
  fi
  return $ok
}

# =============================================================================
# orchprose-02 (change style-rewrite, sub-spec 05): the **Dedup.** bullet is
# rewritten as a lead line (law + mechanism, ending by introducing the list)
# plus a short list of exactly two exception items, both step 4's, closed by
# the no-third-exception sentence kept as prose -- all inside the Session
# guards block, around whose unchanged standing wording the list sits. The
# **Latch.** bullet is byte-unchanged: the latch contract is not part of the
# rewrite. Every phrase the neighboring suites pin (flow-06, sessionguards-01,
# orchestrator-06, sluglimit) survives verbatim, each on one physical line.
# =============================================================================
test_orchprose_02() {
  ok=0
  dedup=$(awk '/^- \*\*Dedup\.\*\*/ {s=1} /^- \*\*Latch\.\*\*/ {s=0} s' "$GUARDS")
  [ -n "$dedup" ] || { echo "  no **Dedup.** bullet in the Session guards block"; return 1; }
  lead=$(printf '%s\n' "$dedup" | head -n 1)
  # The lead keeps the law and its mechanism...
  for p in 'Within one invocation' \
           'the same (sub-spec, role) pair is never delegated twice' \
           'once a pair has been delegated' \
           'route by the existing state machine' \
           'fresh classification from disk' \
           'never by re-delegating that pair' \
           'own account of the delegations it has already made' \
           'nothing is written to disk' \
           'a later orchestrator invocation starts with a clean slate' \
           'resume is a fresh session'; do
    printf '%s\n' "$lead" | grep -qF -- "$p" || { echo "  dedup lead missing: $p"; ok=1; }
  done
  # ...and ends by introducing the exception list with the exactly-two clause.
  printf '%s\n' "$lead" | grep -qF 'exactly two exceptions, both step 4' \
    || { echo "  dedup lead missing the exceptions clause"; ok=1; }
  case "$lead" in
    *"both step 4's:"*) ;;
    *) echo "  the dedup lead does not close by introducing the list (must end with: ... both step 4's:)"; ok=1 ;;
  esac
  # The list enumerates exactly two exceptions, one item each, both step 4's.
  n=$(printf '%s\n' "$dedup" | grep -c '^  - ')
  [ "$n" -eq 2 ] || { echo "  the dedup list has $n items (expected exactly 2 exceptions)"; ok=1; }
  ex1=$(printf '%s\n' "$dedup" | grep '^  - ' | sed -n '1p')
  ex2=$(printf '%s\n' "$dedup" | grep '^  - ' | sed -n '2p')
  pin_exception() {
    # $1 = item text, $2 = required fragment, $3 = label
    if ! printf '%s' "$1" | grep -qF -- "$2"; then
      echo "  $3 missing: $2"; ok=1
    fi
  }
  pin_exception "$ex1" 'relaying each attributable blocker to the `coder` session for the sub-spec it names' 'exception item 1'
  pin_exception "$ex1" 'at most one relay per pair per entry' 'exception item 1'
  pin_exception "$ex1" 'a second entry stops the flow for good' 'exception item 1'
  pin_exception "$ex2" 'the one bounded whole-change `verifier` retry when a rejected entry holds only attributable blockers' 'exception item 2'
  pin_exception "$ex2" 'bounded by `REJECTED.md`: the count reaching 2 stops the flow for good' 'exception item 2'
  # The close keeps the no-third-exception law -- as prose, never a third
  # exception item.
  close=$(printf '%s\n' "$dedup" | grep -F 'No third exception exists')
  [ -n "$close" ] || { echo "  the dedup close ('No third exception exists') is gone"; ok=1; }
  if printf '%s\n' "$close" | grep -q '^  - '; then
    echo "  the no-third-exception close became an exception item"; ok=1
  fi
  printf '%s\n' "$close" | grep -qF 'the specifier is never re-delegated within an invocation' \
    || { echo "  the close dropped the specifier rule"; ok=1; }
  printf '%s\n' "$close" | grep -qF 'persisting after the specifier delegation stops the session rather than re-delegating' \
    || { echo "  the close dropped the change_dir=missing rule"; ok=1; }
  # The guards' standing wording survives around the list, and the superseded
  # "single carve-out" framing stays absent.
  require "$GUARDS" 'prompt-level law' || ok=1
  require "$GUARDS" 'regardless of what the tool grant technically allows' || ok=1
  require "$GUARDS" 'never-delegate-outside-the-three-roles rule' || ok=1
  require "$GUARDS" 'They add constraints only' || ok=1
  refuse "$GUARDS" 'single carve-out' || ok=1
  # The **Latch.** bullet is byte-unchanged vs HEAD (the latch contract is
  # not part of this rewrite); retired with a loud note only when git or
  # HEAD's copy is unreadable, same gate style as sessionguards-04.
  if command -v git >/dev/null 2>&1 && [ -e "$SCRIPT_DIR/.git" ] \
     && git -C "$SCRIPT_DIR" cat-file -e HEAD:agents/prompts/orchestrator.prompt 2>/dev/null; then
    work_latch=$(grep -F -- '- **Latch.**' "$GUARDS")
    head_latch=$(git -C "$SCRIPT_DIR" show HEAD:agents/prompts/orchestrator.prompt | grep -F -- '- **Latch.**')
    { [ -n "$work_latch" ] && [ "$work_latch" = "$head_latch" ]; } \
      || { echo "  the **Latch.** bullet changed or went missing -- it must stay byte-unchanged"; ok=1; }
  else
    echo "  note: git/HEAD unreadable -- the **Latch.** byte-unchanged check is vacuously retired"
  fi
  return $ok
}

# =============================================================================
# orchprose-03 (change style-rewrite, sub-spec 05): the new shape pins live in
# this suite, registered with test names carrying the orchprose ids, scoped to
# the step-4 and Session guards extracts; and the three neighboring suites
# that must survive the rewrite pass unmodified -- flow-06's dedup phrases and
# the structural pins in tests/antz-flow_test.sh, receipts-09's step-4 intro
# strings in tests/receipts_test.sh (its STEP4 extract ends at step 5, so the
# relay list under the table can't disturb it), and the probe-script/
# include-marker checks in tests/orchestrator-status-probe_test.sh. Each is
# run as a real subprocess and must exit 0.
# =============================================================================
test_orchprose_03() {
  ok=0
  # The new pins are registered here, named after the sub-spec's ids, and
  # they read the scoped extracts (guard: a stray mention elsewhere can't
  # satisfy them -- orchprose-01/02 assert against STEP4/GUARDS only).
  grep -qF 'run_test "orchprose-01' "$SELF" \
    || { echo "  orchprose-01's pin is not registered in this suite"; ok=1; }
  grep -qF 'run_test "orchprose-02' "$SELF" \
    || { echo "  orchprose-02's pin is not registered in this suite"; ok=1; }
  grep -qF '"$STEP4"' "$SELF" || { echo "  no pin reads the step-4 extract"; ok=1; }
  grep -qF '"$GUARDS"' "$SELF" || { echo "  no pin reads the Session guards extract"; ok=1; }
  # receipts-09's step-4 strings stay in the step-4 INTRO line, above the
  # table (the same three strings receipts_test.sh requires -- proof by
  # construction that its STEP4 extract still holds them).
  intro=$(awk '/^4\. Once every sub-spec is `done`/{print; exit}' "$ORCHESTRATOR_PROMPT")
  printf '%s\n' "$intro" | grep -qF 'without running the unit suite' \
    || { echo "  step-4 intro lost the no-suite-run clause"; ok=1; }
  printf '%s\n' "$intro" | grep -qF 'no "final gate" re-test' \
    || { echo "  step-4 intro lost the no-final-gate clause"; ok=1; }
  printf '%s\n' "$intro" | grep -qF "the verifier's own e2e Integration Verification suite remains the independent gate" \
    || { echo "  step-4 intro lost the independent-gate clause"; ok=1; }
  # The neighboring suites pass unmodified -- run each as a subprocess.
  for suite in antz-flow_test.sh receipts_test.sh orchestrator-status-probe_test.sh; do
    sfile="$SCRIPT_DIR/tests/$suite"
    [ -f "$sfile" ] || { echo "  missing neighboring suite: $suite"; ok=1; continue; }
    if ! out=$(sh "$sfile" 2>&1); then
      echo "  $suite exited non-zero:"
      printf '%s\n' "$out" | tail -n 5
      ok=1
    fi
  done
  return $ok
}

# =============================================================================
# testsuite-04 (change deembed-orchestration-scripts, sub-spec 05): the
# marker-count pins re-key to the invocation-line forms and the structural
# counts move to the de-embedded shape; the dedup/latch law assertions and
# the no-delegation-ledger checks are unchanged. This test pins the re-key.
# =============================================================================
test_testsuite_04_marker_counts_rekeyed() {
  ok=0
  body=$(awk '/^test_sessionguards_03\(\)/,/^}$/' "$SELF")
  printf '%s\n' "$body" | grep -qF '__ANTZ_SCRIPTS_DIR__/$script.sh' \
    || { echo "  sessionguards-03 does not count path-reference lines"; ok=1; }
  printf '%s\n' "$body" | grep -qF '# antz-include: scripts/orchestration/$script.sh' \
    && { echo "  sessionguards-03 still counts include markers"; ok=1; }
  b1=$(awk '/^test_orchprose_01\(\)/,/^}$/' "$SELF")
  printf '%s\n' "$b1" | grep -qF 'expected 8 fence lines' \
    || { echo "  orchprose-01 lost the de-embedded fence-line count"; ok=1; }
  printf '%s\n' "$b1" | grep -qF 'expected no sh-fence openers' \
    || { echo "  orchprose-01 lost the no-sh-fence count"; ok=1; }
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "sessionguards-01: the dedup law -- a (sub-spec, role) pair is never delegated twice in one invocation; routing never re-delegates; exactly two exceptions, both step 4's, each REJECTED.md-bounded" test_sessionguards_01
run_test "sessionguards-02: the latch law -- after any stop-and-report outcome no further delegation of any kind, resumption is a fresh invocation, and every named stop outcome is covered" test_sessionguards_02
run_test "sessionguards-03: pure prose law -- no new script, no new flow subcommand, no new probe field, no delegation ledger under spdd/, mechanism is the session's own account" test_sessionguards_03
run_test "sessionguards-04: everything else keeps its meaning -- additive outside the three script fences, steps 1-6 in order, tables survive, constraints only" test_sessionguards_04
run_test "orchprose-01: step 4's rejected_count=1 row is a short routing cell and the relay detail is a three-bullet list directly under the table; the 0/2 rows and the four-table/fence/steps structure are unchanged" test_orchprose_01
run_test "orchprose-02: the **Dedup.** bullet becomes a lead line plus a two-item exception list with the no-third-exception close kept as prose; the guards' standing wording survives and the **Latch.** bullet is byte-unchanged" test_orchprose_02
run_test "orchprose-03: the new shape pins live in this suite (id-named, extract-scoped, step-4 intro strings intact) and the neighboring antz-flow/receipts/status-probe suites pass unmodified" test_orchprose_03
run_test "testsuite-04: sessionguards-03's include-marker counts re-key to path-reference invocation lines (no marker anywhere, exactly the three scripts on disk) and orchprose-01's structural counts move to 8 fence lines / 4 blocks / no sh fence" test_testsuite_04_marker_counts_rekeyed

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

rm -f "$PROCESS" "$STEP4" "$GUARDS"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 07-e2e.feature)"
[ "$fail_count" -eq 0 ]
