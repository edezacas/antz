#!/usr/bin/env bash
# Unit tests for the optional Entities/Operations table instruction added to
# the "## Output" section of agents/prompts/specifier.prompt, covering every
# scenario in
# spdd/changes/specifier-entities-operations-table/01-entities-operations-table.feature
# (entities-table-01..05), re-scoped in place for the two-line table-bullet
# rewrite of spdd/changes/style-rewrite/01-specifier.feature
# (specifier-01..02).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/versioning-rule_test.sh and tests/set-model-command_test.sh. Run
# directly:
#   ./tests/entities-operations-table_test.sh
#
# Every scenario here is a deterministic content assertion against the
# static text of agents/prompts/specifier.prompt's "## Output" section
# (grep-style), not a live LLM invocation -- per the sub-spec's Verification
# levels. The change's e2e-entities-01/02 scenarios (e2e-qa.feature) require
# a live specifier session and belong to the verifier's end-to-end suite,
# not this unit suite; they appear below as explicit SKIP stubs so no
# scenario id is silently unaccounted for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/versioning-rule_test.sh) -------------

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
  # unit-level TDD (never a silent omission).
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

# The "## Output" section runs from its own heading to the next top-level
# "## " heading (or end of file). Extracted once so every test below reads
# only the section the sub-spec is scoped to, not the whole prompt.
OUTPUT_SECTION=$(mktemp)
awk '
  /^## Output/ { flag=1 }
  flag && /^## / && !/^## Output/ { flag=0 }
  flag { print }
' "$SPECIFIER_PROMPT" > "$OUTPUT_SECTION"

# =============================================================================
# entities-table-01: the Output section states the option to include a
# structured Entities/Operations table when a change introduces a new data
# shape or multiple named operations. MODIFIED by
# spdd/archive/specifier-readme-fixed-name/01-readmefile.feature: the bullet
# introducing the table no longer names `README.md` itself -- it relies on
# the Output section's own fixed-file bullet instead (see
# readmefile_test.sh's readmefile-01). RE-SCOPED by
# spdd/changes/style-rewrite/01-specifier.feature (specifier-01): the trigger
# pins survive on the rewritten first bullet; the stacked permission phrase
# "you may optionally include" is retired and becomes a refusal.
# =============================================================================
test_entities_table_01() {
  ok=0
  require "$OUTPUT_SECTION" 'a new data shape (entity, model, or interface)' || ok=1
  require "$OUTPUT_SECTION" 'multiple named operations (endpoints, CLI commands/flags, steps, events)' || ok=1
  # Retired by the style rewrite: optionality is stated positively in the
  # second bullet ("includes no table"), not as a stacked permission phrase.
  refuse "$OUTPUT_SECTION" 'you may optionally include' || ok=1
  return $ok
}

# =============================================================================
# entities-table-01 (MODIFY, continued): the bullet introducing the table
# does not itself contain the literal string "README.md" anymore.
# =============================================================================
test_entities_table_01_no_readme_mention() {
  ok=0
  # Extract just the Entities/Operations table bullet (the line starting
  # with "- When a change introduces a new data shape").
  TABLE_BULLET=$(grep -F -- '- When a change introduces a new data shape' "$OUTPUT_SECTION")
  if [ -z "$TABLE_BULLET" ]; then
    echo "  could not find the Entities/Operations table bullet"
    return 1
  fi
  case "$TABLE_BULLET" in
    *README.md*)
      echo "  found forbidden text: README.md (in the table bullet)"
      ok=1
      ;;
  esac
  return $ok
}

# =============================================================================
# entities-table-02: the exact column sets are specified for each table kind.
# Unchanged by the style rewrite -- both column strings survive verbatim on
# the rewritten first bullet.
# =============================================================================
test_entities_table_02() {
  ok=0
  require "$OUTPUT_SECTION" 'entities table with columns Name, Path, New-or-Existing, Notes' || ok=1
  require "$OUTPUT_SECTION" 'operations table with columns Type, Identifier, Description' || ok=1
  return $ok
}

# =============================================================================
# entities-table-03: the table is a scannable complement, never a
# replacement for the Gherkin scenarios. RE-SCOPED by style-rewrite
# specifier-01: both phrases survive on the rewritten second bullet, now
# pinning the fuller "the tagged Gherkin scenarios ..." form.
# =============================================================================
test_entities_table_03() {
  ok=0
  require "$OUTPUT_SECTION" 'scannable complement to the prose contract sections' || ok=1
  require "$OUTPUT_SECTION" 'the tagged Gherkin scenarios remain the actual testable behavior spec, never replaced by the table' || ok=1
  return $ok
}

# =============================================================================
# entities-table-04: the table is optional per change -- the negation stack
# ("never mandatory", "should not be forced to produce a near-empty table")
# is re-scoped by style-rewrite specifier-01 to its positive survivor: a
# change with neither a new data shape nor multiple named operations includes
# no table.
# =============================================================================
test_entities_table_04() {
  ok=0
  require "$OUTPUT_SECTION" 'a change with neither a new data shape nor multiple named operations includes no table' || ok=1
  refuse "$OUTPUT_SECTION" 'never mandatory' || ok=1
  refuse "$OUTPUT_SECTION" 'should not be forced' || ok=1
  return $ok
}

# =============================================================================
# entities-table-05: the rigid "fill every section or mark not applicable"
# behavior of the open-spdd canvas template is not adopted. RE-SCOPED by
# style-rewrite specifier-01: the refusal sentences themselves were part of
# the retired triple negation, so this scenario's surviving pins are all
# refusals -- the retired strings are gone and the negative sentinel "You
# must mark every section" must never appear stated as a requirement.
# =============================================================================
test_entities_table_05() {
  ok=0
  refuse "$OUTPUT_SECTION" "Don't require marking every section" || ok=1
  refuse "$OUTPUT_SECTION" "don't mandate filling a table" || ok=1
  refuse "$OUTPUT_SECTION" 'always-fill-every-section' || ok=1
  # Negative sentinel: the removal phrasing must not have been reworded into
  # a requirement.
  refuse "$OUTPUT_SECTION" 'You must mark every section' || ok=1
  return $ok
}

# =============================================================================
# specifier-01 (style-rewrite 01-specifier.feature): the two table bullets
# become the plan's two-line rewrite -- the triple negation is gone, the
# pinned semantics survive verbatim.
# =============================================================================
test_specifier_01() {
  ok=0
  # Shape: the old two table bullets are replaced by exactly two one-line
  # bullets, sitting in the "## Output" section between the overview bullet
  # and the sub-spec-naming bullet.
  REGION=$(awk '
    /^- Write the change.s overview/ { flag=1; next }
    /^- Name sub-spec files/ { flag=0 }
    flag { print }
  ' "$OUTPUT_SECTION")
  region_lines=$(printf '%s\n' "$REGION" | grep -c '')
  region_bullets=$(printf '%s\n' "$REGION" | grep -c '^- ')
  if [ "$region_lines" != "2" ] || [ "$region_bullets" != "2" ]; then
    echo "  the rewrite region must be exactly two one-line bullets, found $region_lines lines / $region_bullets bullets"
    ok=1
  fi
  BULLET1=$(printf '%s\n' "$REGION" | head -n 1)
  BULLET2=$(printf '%s\n' "$REGION" | tail -n 1)
  case "$BULLET1" in
    '- When a change introduces a new data shape'*) ;;
    *)
      echo "  first bullet does not start with '- When a change introduces a new data shape'"
      ok=1
      ;;
  esac
  # Bullet 1, on its own line, states the trigger, both tables with their
  # exact column sets, and the pruning rule.
  for s in 'a new data shape (entity, model, or interface)' \
           'multiple named operations (endpoints, CLI commands/flags, steps, events)' \
           'entities table with columns Name, Path, New-or-Existing, Notes' \
           'operations table with columns Type, Identifier, Description' \
           "pruning columns per the Specification Rules' example-table rule"; do
    printf '%s' "$BULLET1" | grep -qF -- "$s" \
      || { echo "  first bullet missing: $s"; ok=1; }
  done
  # The first bullet never names README.md (the fixed-file bullet stays the
  # one place that does).
  case "$BULLET1" in
    *README.md*)
      echo "  found forbidden text: README.md (in the rewritten first bullet)"
      ok=1
      ;;
  esac
  # Bullet 2, on its own line, states the complement status, the scenarios'
  # primacy, and the no-table case -- positively.
  for s in 'scannable complement to the prose contract sections' \
           'the tagged Gherkin scenarios remain the actual testable behavior spec, never replaced by the table' \
           'a change with neither a new data shape nor multiple named operations includes no table'; do
    printf '%s' "$BULLET2" | grep -qF -- "$s" \
      || { echo "  second bullet missing: $s"; ok=1; }
  done
  # The triple-negation strings are gone from the WHOLE prompt, not just the
  # section.
  for s in 'you may optionally include' \
           'This table is never mandatory' \
           'should not be forced to produce a near-empty table' \
           "Don't require marking every section" \
           "don't mandate filling a table" \
           'always-fill-every-section'; do
    refuse "$SPECIFIER_PROMPT" "$s" || ok=1
  done
  return $ok
}

# =============================================================================
# specifier-02 (style-rewrite 01-specifier.feature): the suite pins follow
# the rewrite loudly -- the legacy entities-table-01..05 pins are re-scoped
# in place (retained pins passing, retired strings refused), this suite
# carries test functions named after the sub-spec's ids and exits 0, and the
# neighboring specifier suites pass unmodified.
# =============================================================================
SELF="$SCRIPT_DIR/tests/entities-operations-table_test.sh"

test_specifier_02() {
  ok=0
  # Guarded child run: the assertions below inspect this whole suite from
  # outside (exit 0, every pin green, both scenario ids registered); the
  # child skips this block so the inspection doesn't recurse.
  if [ -n "${ANTZ_ENTITIES_TABLE_CHILD:-}" ]; then
    return 0
  fi
  child_out=$(ANTZ_ENTITIES_TABLE_CHILD=1 sh "$SELF" 2>&1)
  child_rc=$?
  if [ "$child_rc" -ne 0 ]; then
    echo "  tests/entities-operations-table_test.sh must exit 0 after the re-scope (rc=$child_rc):"
    printf '%s\n' "$child_out" | grep '^FAIL' || true
    ok=1
  fi
  if printf '%s\n' "$child_out" | grep -q '^FAIL'; then
    echo "  no pin may fail in the re-scoped suite:"
    printf '%s\n' "$child_out" | grep '^FAIL'
    ok=1
  fi
  # The suite carries new test functions named after this sub-spec's ids, so
  # a failure maps back to the scenario.
  printf '%s\n' "$child_out" | grep -q '^PASS: specifier-01' \
    || { echo "  the suite must register a passing test named specifier-01"; ok=1; }
  printf '%s\n' "$child_out" | grep -q '^PASS: specifier-02' \
    || { echo "  the suite must register a passing test named specifier-02"; ok=1; }
  # The legacy re-scoped functions stay registered and green.
  for n in 01 02 03 04 05; do
    printf '%s\n' "$child_out" | grep -q "^PASS: entities-table-$n" \
      || { echo "  the re-scoped legacy pin entities-table-$n is not registered and green"; ok=1; }
  done
  # Neighboring specifier suites pass unmodified -- their extracts (keyed on
  # the "## Output" heading and on bullets this sub-spec does not touch)
  # never read the rewritten bullets.
  for t in tests/readmefile_test.sh tests/conventions_test.sh; do
    nout=$(CDPATH= sh "$SCRIPT_DIR/$t" 2>&1) || {
      echo "  $t must pass unmodified:"
      printf '%s\n' "$nout" | grep '^FAIL' || true
      ok=1
    }
  done
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "entities-table-01: Output section states the optional Entities/Operations table for a new data shape or multiple named operations" test_entities_table_01
run_test "entities-table-01: the table-introducing bullet no longer contains the literal string README.md" test_entities_table_01_no_readme_mention
run_test "entities-table-02: exact column sets stated for the entities table and the operations table" test_entities_table_02
run_test "entities-table-03: table is a scannable complement, Gherkin scenarios remain the actual testable behavior spec" test_entities_table_03
run_test "entities-table-04: optionality stated positively (a change with neither trigger includes no table) with the retired negation stack refused" test_entities_table_04
run_test "entities-table-05: the retired canvas-rigidity strings are all refused and 'You must mark every section' never appears" test_entities_table_05
run_test "specifier-01: the two table bullets become the plan's two-line rewrite with the triple negation gone and the semantics intact" test_specifier_01
run_test "specifier-02: the re-scoped suite exits 0 with both scenario ids and the legacy pins registered and green, and the neighboring specifier suites pass unmodified" test_specifier_02

# ---- e2e-only scenarios: explicit SKIP stubs ---------------------------------
# e2e-entities-01/02 (spdd/changes/specifier-entities-operations-table/e2e-qa.feature)
# require a live specifier session and inspecting the artifacts it produces --
# not reducible to a static grep on specifier.prompt. They belong to the
# verifier's end-to-end suite, not this unit suite. Explicit stubs so every
# scenario id is accounted for.

E2E_REASON="e2e-only: observable only in a live specifier session (verifier's e2e-qa.feature)"

skip_test "e2e-entities-01: a change introducing a new entity and multiple named operations gets a scannable table in README.md" "$E2E_REASON"
skip_test "e2e-entities-02: a change with no new data shape and a single operation produces no table, not flagged as incomplete" "$E2E_REASON"

rm -f "$OUTPUT_SECTION"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see e2e-qa.feature)"
[ "$fail_count" -eq 0 ]
