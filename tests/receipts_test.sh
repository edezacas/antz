#!/usr/bin/env bash
# Unit tests for the receipts convention of change orchestrator-fast-path,
# covering every unit-level scenario in
# spdd/changes/orchestrator-fast-path/05-receipts.feature except receipts-06
# (the probe's extended subspec= line, covered at runtime by
# tests/orchestrator-status-probe_test.sh).
#
# Covered here:
#   receipts-01..05 -- the coder prompt's receipt-writing duty (a dedicated
#       "## Receipt" section): the file name mirroring the sub-spec, the
#       discovered test_command=, the per-id result vocabulary, the exact
#       declared id set, the in-place rewrite, and the planning-refusal
#       receipt;
#   receipts-07..09 -- the orchestrator prompt's rewritten step 3
#       (classification is file reading from the probe's receipt fields; the
#       doubtful-receipt exception is the one suite re-run; no pre-verifier
#       gate at step 4);
#   receipts-10 -- the identical receipt-convention gotcha bullet in
#       AGENTS.md and CLAUDE.md.
#
# The disk receipt is the classification authority; a role's conversational
# report is never an input to it. All content assertions are static greps
# (the duties are prompt prose law, not machinery); every reported test name
# embeds its scenario id so a failure maps straight back to the scenario.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/orchestrator-sessionguards_test.sh. Run directly:
#   ./tests/receipts_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/orchestrator-sessionguards_test.sh) ----

run_test() {
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
  awk -v sec="$2" '
    $0 == "## " sec { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
  ' "$1" > "$3"
}

# ---- section extracts --------------------------------------------------------

RECEIPT=$(mktemp)
extract_section "$CODER_PROMPT" "Receipt" "$RECEIPT"

# The orchestrator prompt's step 3: from its numbered heading down to (not
# including) step 4's numbered heading. Fence content is indented, so the
# column-0 numbered headings match only the steps.
STEP3=$(mktemp)
awk '/^3\. \*\*Classify each sub-spec\*\*/ { flag=1 }
     /^4\. / { flag=0 }
     flag { print }' "$ORCHESTRATOR_PROMPT" > "$STEP3"

STEP4=$(mktemp)
awk '/^4\. Once every sub-spec is `done`/ { flag=1 }
     /^5\. / { flag=0 }
     flag { print }' "$ORCHESTRATOR_PROMPT" > "$STEP4"

# =============================================================================
# receipts-01: the coder writes the receipt at session end, named after the
# sub-spec file, with the discovered unit-suite run command recorded in
# exactly one test_command= line and one id line per declared scenario id.
# =============================================================================
test_receipts_01() {
  ok=0
  [ -s "$RECEIPT" ] || { echo "  the coder prompt has no '## Receipt' section"; return 1; }
  # The artifact: path, naming rule, when it is written.
  require "$RECEIPT" 'spdd/changes/<slug>/NN-<feature>.result' || ok=1
  require "$RECEIPT" 'named after the sub-spec' || ok=1
  require "$RECEIPT" '01-api.feature' || ok=1
  require "$RECEIPT" '01-api.result' || ok=1
  require "$RECEIPT" 'finishes or advances a sub-spec' || ok=1
  # Exactly one test_command= line, its value the discovered run command.
  require "$RECEIPT" 'exactly one `test_command=` line' || ok=1
  require "$RECEIPT" 'test_command=<discovered unit-suite run command>' || ok=1
  # Discovery moved to the coder, the way any contributor would do it.
  require "$RECEIPT" 'the way any contributor would' || ok=1
  require "$RECEIPT" 'package.json' || ok=1
  require "$RECEIPT" 'Makefile' || ok=1
  # One id line per declared scenario id, of the pinned form.
  require "$RECEIPT" 'one `id=` line per scenario id' || ok=1
  require "$RECEIPT" 'id=<feature>-<index> result=<green|skip|blocked> reason=<text>' || ok=1
  return $ok
}

# =============================================================================
# receipts-02 (Scenario Outline, one row per outcome): the receipt carries
# the row's line for that id -- green (unit test name), ordinary skip (why),
# blocked (the BLOCKED: convention).
# =============================================================================
test_receipts_02_green_row() {
  ok=0
  require "$RECEIPT" 'result=green' || ok=1
  require "$RECEIPT" 'reason=<unit test name>' || ok=1
  return $ok
}

test_receipts_02_skip_row() {
  ok=0
  require "$RECEIPT" 'result=skip reason=<why>' || ok=1
  return $ok
}

test_receipts_02_blocked_row() {
  ok=0
  require "$RECEIPT" 'result=blocked reason=BLOCKED: <why>' || ok=1
  return $ok
}

# =============================================================================
# receipts-03: the receipt's id set equals the sub-spec's declared id set
# exactly -- each id once, in scenario order; a foreign id never appears; a
# declared id with no test yet still gets its line, never a silent omission.
# =============================================================================
test_receipts_03() {
  ok=0
  require "$RECEIPT" 'exact declared id set' || ok=1
  require "$RECEIPT" 'scenario order' || ok=1
  require "$RECEIPT" 'each once' || ok=1
  require "$RECEIPT" 'never appears' || ok=1
  require "$RECEIPT" 'a declared id with no test yet still gets its line' || ok=1
  require "$RECEIPT" 'never a silent omission' || ok=1
  # The non-empty reason duty is stated per line.
  require "$RECEIPT" 'non-empty reason' || ok=1
  return $ok
}

# =============================================================================
# receipts-04: a later coder session on the same sub-spec rewrites the same
# receipt in place -- never a second, accumulated sibling file; the file
# always holds the newest session's outcomes and test command.
# =============================================================================
test_receipts_04() {
  ok=0
  require "$RECEIPT" 'rewritten in place' || ok=1
  require "$RECEIPT" 'never' || ok=1
  require "$RECEIPT" 'the newest session' || ok=1
  return $ok
}

# =============================================================================
# receipts-05: a planning-stage refusal (the existing whole-sub-spec BLOCKED:
# stub, tagged with the sub-spec's first scenario id) still produces a
# truthful receipt: every declared id result=blocked with the same BLOCKED:
# reason, and test_command= still records the discovered (or honestly
# undiscoverable) suite command -- the receipt is never empty.
# =============================================================================
test_receipts_05() {
  ok=0
  require "$RECEIPT" 'planning-stage refusal' || ok=1
  require "$RECEIPT" 'first scenario id' || ok=1
  require "$RECEIPT" 'result=blocked' || ok=1
  require "$RECEIPT" 'the same `BLOCKED: <why>` reason' || ok=1
  require "$RECEIPT" 'honestly undiscoverable' || ok=1
  require "$RECEIPT" 'never empty' || ok=1
  return $ok
}

# =============================================================================
# receipts-07: the orchestrator's step 3 classifies from the probe's receipt
# fields alone -- done (complete receipt, green/ordinary-skip), blocked (any
# result=blocked line, stop at the first one found, relay its BLOCKED:
# reason, route to specifier as today), in_progress (missing/incomplete/
# uncovered -- delegate to a fresh coder session as today) -- and no longer
# instructs discovering the unit-suite command or running the suite for
# classification.
# =============================================================================
test_receipts_07() {
  ok=0
  # Classification is file reading from the probe's receipt fields.
  require "$STEP3" 'file reading' || ok=1
  require "$STEP3" 'receipt fields' || ok=1
  require "$STEP3" '`receipt=`' || ok=1
  require "$STEP3" '`covered=`' || ok=1
  require "$STEP3" '`complete=`' || ok=1
  require "$STEP3" '`class=`' || ok=1
  # The three classes, with the pinned meanings.
  require "$STEP3" 'class=blocked' || ok=1
  require "$STEP3" 'class=done' || ok=1
  require "$STEP3" 'class=in_progress' || ok=1
  require "$STEP3" 'checked first regardless of coverage' || ok=1
  # The blocked stop-and-relay behavior is kept verbatim in spirit.
  require "$STEP3" 'Stop at the first one found' || ok=1
  require "$STEP3" 'relay its `BLOCKED:` reason' || ok=1
  require "$STEP3" 'route it to `specifier`' || ok=1
  # In-progress routing is kept: fresh coder session, one per sub-spec,
  # sequentially (the existing sequential-sessions law survives).
  require "$STEP3" 'delegate to a fresh `coder` session' || ok=1
  require "$STEP3" 'one session per sub-spec' || ok=1
  require "$STEP3" '**sequentially, never in parallel**' || ok=1
  # The empty-ids stop-and-ask rule is kept (never vacuously done).
  require "$STEP3" 'An empty `ids` list' || ok=1
  require "$STEP3" 'Stop and ask the user' || ok=1
  require "$STEP3" "never treat it as vacuously \`done\`" || ok=1
  # No suite discovery/run for classification: the suite instructions exist
  # only inside the doubtful-receipt exception bullet (receipts-08), and the
  # old run-for-classification sentence is gone.
  refuse "$STEP3" 'Run it, then classify each sub-spec from its `ids`' || ok=1
  require "$STEP3" 'never run for classification' || ok=1
  return $ok
}

# =============================================================================
# receipts-08: the one suite exception -- a doubtful receipt (missing,
# incomplete, or mismatched: complete=no) is settled by re-running the unit
# suite once, for that doubtful sub-spec only, using the receipt's
# test_command= value when it carries one, else discovering the command; the
# sub-spec is then classified from the actual run result, the receipt doubt
# is reported, and the orchestrator never writes, fixes, or fabricates the
# receipt itself.
# =============================================================================
test_receipts_08() {
  ok=0
  require "$STEP3" 'complete=no' || ok=1
  require "$STEP3" 're-run the unit suite once' || ok=1
  require "$STEP3" 'for that doubtful sub-spec only' || ok=1
  require "$STEP3" "the receipt's \`test_command=\` value when the receipt carries one" || ok=1
  require "$STEP3" 'the way any contributor would' || ok=1
  require "$STEP3" 'from the actual run result' || ok=1
  require "$STEP3" 'report the receipt doubt' || ok=1
  require "$STEP3" 'Never write, fix, or fabricate the receipt yourself' || ok=1
  require "$STEP3" "the receipt stays the coder's artifact" || ok=1
  return $ok
}

# =============================================================================
# receipts-09: no pre-verifier gate -- step 4 routes to the verifier on
# receipts alone, without running the unit suite at all (no final gate
# re-test); the verifier's own e2e Integration Verification suite remains
# the independent gate.
# =============================================================================
test_receipts_09() {
  ok=0
  require "$STEP4" 'without running the unit suite' || ok=1
  require "$STEP4" 'no "final gate" re-test' || ok=1
  require "$STEP4" "the verifier's own e2e Integration Verification suite remains the independent gate" || ok=1
  return $ok
}

# =============================================================================
# receipts-10: AGENTS.md and CLAUDE.md each carry an identical
# receipt-convention gotcha bullet: the file name written by the coder at
# session end, the test_command= + per-id result grammar, BLOCKED: as the
# blocked reason, and that the orchestrator classifies by reading receipts --
# running the unit suite only for a doubtful receipt, never as a pre-verifier
# gate.
# =============================================================================
receipt_bullet() {
  # $1 = md file; prints the first receipt-convention gotcha bullet line.
  grep -F -- '- Receipts (`spdd/changes/<slug>/NN-<feature>.result`)' "$1" | head -n 1
}

test_receipts_10() {
  ok=0
  a=$(receipt_bullet "$AGENTS_MD")
  c=$(receipt_bullet "$CLAUDE_MD")
  [ -n "$a" ] || { echo "  AGENTS.md has no receipt-convention gotcha bullet"; return 1; }
  [ -n "$c" ] || { echo "  CLAUDE.md has no receipt-convention gotcha bullet"; return 1; }
  [ "$a" = "$c" ] || {
    echo "  the receipt-convention bullet differs between AGENTS.md and CLAUDE.md"
    printf '%s\n%s\n' "$a" "$c" | head -4
    return 1
  }
  printf '%s\n' "$a" > /tmp/opencode/receipts-bullet.txt
  b=/tmp/opencode/receipts-bullet.txt
  require "$b" 'spdd/changes/<slug>/NN-<feature>.result' || ok=1
  require "$b" 'written by the coder' || ok=1
  require "$b" 'at the end of each session' || ok=1
  require "$b" 'test_command=' || ok=1
  require "$b" 'result=green|skip|blocked' || ok=1
  require "$b" '`BLOCKED:`' || ok=1
  require "$b" 'classifies by reading' || ok=1
  require "$b" 'only for a doubtful receipt' || ok=1
  require "$b" 'never as a pre-verifier gate' || ok=1
  return $ok
}

# =============================================================================
# receipts-10 (companion): the probe gotcha's described facts gain the
# receipt fields, and the stale sourcing/classification wording around it is
# updated in both docs identically where the docs' shared-bullet convention
# applies: the probe bullet names the receipts among the facts it computes,
# the stale "requires actually running the unit suite" classification
# sentence is gone, and the REJECTED.md gotcha no longer calls the probe
# script "embedded".
# =============================================================================
test_receipts_10_gotcha_updates() {
  ok=0
  for doc in "$AGENTS_MD" "$CLAUDE_MD"; do
    require "$doc" 'and each sub-spec'"'"'s declared scenario ids plus its receipt classification fields' || ok=1
    require "$doc" 'read from the coder'"'"'s `NN-<feature>.result` receipts' || ok=1
  done
  # The probe no longer "deliberately stops short of ... classifying": it
  # now reads receipts and classifies mechanically; discovery of the test
  # command moved to the coder.
  refuse "$AGENTS_MD" 'deliberately stops short of running the unit suite or classifying pass/fail/`BLOCKED` itself' || ok=1
  refuse "$CLAUDE_MD" 'deliberately stops short of running the unit suite or classifying pass/fail/`BLOCKED` itself' || ok=1
  for doc in "$AGENTS_MD" "$CLAUDE_MD"; do
    require "$doc" 'discovering a project' || ok=1
  done
  # The classification sentence of the disk-only conventions bullet no
  # longer claims classification requires running the suite.
  refuse "$AGENTS_MD" 'Classifying a sub-spec in-progress vs. done requires actually running' || ok=1
  refuse "$CLAUDE_MD" 'Classifying a sub-spec in-progress vs. done requires actually running' || ok=1
  for doc in "$AGENTS_MD" "$CLAUDE_MD"; do
    require "$doc" 'reads the receipt the coder wrote for it' || ok=1
  done
  # The stale "embedded probe script" wording in the REJECTED.md gotcha is
  # fixed in both docs (flagged-but-shared gotcha this sub-spec touches).
  refuse "$AGENTS_MD" "orchestrator.prompt\`'s embedded probe script" || ok=1
  refuse "$CLAUDE_MD" "orchestrator.prompt\`'s embedded probe script" || ok=1
  for doc in "$AGENTS_MD" "$CLAUDE_MD"; do
    require "$doc" "via \`orchestrator.prompt\`'s probe script (source of truth: \`scripts/orchestration/antz-probe.sh\`; see below)" || ok=1
  done
  return $ok
}

# ---- run everything ----------------------------------------------------------

run_test "receipts-01: the coder prompt states the receipt duty -- NN-<feature>.result named after the sub-spec, exactly one test_command= line with the discovered command, one id line per declared id" test_receipts_01
run_test "receipts-02 (green row): a passing unit test records result=green reason=<unit test name>" test_receipts_02_green_row
run_test "receipts-02 (skip row): an ordinary skip records result=skip reason=<why>" test_receipts_02_skip_row
run_test "receipts-02 (blocked row): a BLOCKED: stub records result=blocked reason=BLOCKED: <why>" test_receipts_02_blocked_row
run_test "receipts-03: the receipt's id set equals the declared id set exactly -- scenario order, no foreign id, no silent omission" test_receipts_03
run_test "receipts-04: a later session rewrites the same receipt in place -- the file always holds the newest session's state" test_receipts_04
run_test "receipts-05: a planning-stage refusal still produces a truthful receipt -- every id result=blocked, the same BLOCKED: reason, test_command= never empty" test_receipts_05
run_test "receipts-07: the orchestrator's step 3 classifies from the probe's receipt fields alone and no longer runs the suite for classification" test_receipts_07
run_test "receipts-08: the doubtful-receipt exception -- one suite re-run for that doubtful sub-spec only, classified from the actual run, receipt never fabricated" test_receipts_08
run_test "receipts-09: no pre-verifier gate -- step 4 routes to the verifier without running the unit suite; the verifier's e2e suite stays the independent gate" test_receipts_09
run_test "receipts-10: AGENTS.md and CLAUDE.md carry an identical receipt-convention gotcha bullet" test_receipts_10
run_test "receipts-10 (gotcha updates): the probe gotcha gains the receipt fields and the stale embedded/running-the-suite wording is fixed in both docs" test_receipts_10_gotcha_updates

# ---- e2e-only scenario: explicit SKIP stub -----------------------------------
# e2e-03 (spdd/changes/orchestrator-fast-path/07-e2e.feature) is the change's
# verifier-owned end-to-end QA suite: the receipt lifecycle it observes
# (coder sessions writing receipts, the orchestrator classifying from disk,
# every report's closing block mirroring the receipts) happens in live /antz
# sessions, which a unit suite cannot spawn. Explicit stub so the scenario
# id is accounted for (suite convention: see tests/versioning-rule_test.sh).
skip_test "e2e-03: a live /antz flow's coder sessions write NN-<feature>.result receipts that the orchestrator classifies from disk without running the unit suite, and every report's closing block mirrors its receipt" \
  "e2e-only: observable only in live /antz sessions (coder receipts + orchestrator classification), run by the verifier (07-e2e.feature)"

rm -f "$RECEIPT" "$STEP3" "$STEP4"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 07-e2e.feature)"
[ "$fail_count" -eq 0 ]
