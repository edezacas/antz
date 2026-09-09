#!/usr/bin/env bash
# Unit tests for the optional Entities/Operations table instruction added to
# the "## Output" section of agents/prompts/specifier.prompt, covering every
# scenario in
# spdd/changes/specifier-entities-operations-table/01-entities-operations-table.feature
# (entities-table-01..05).
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
# spdd/changes/specifier-readme-fixed-name/01-readmefile.feature: the bullet
# introducing the table no longer names `README.md` itself -- it relies on
# the Output section's own fixed-file bullet instead (see
# readmefile_test.sh's readmefile-01).
# =============================================================================
test_entities_table_01() {
  ok=0
  require "$OUTPUT_SECTION" 'a new data shape (entity, model, or interface)' || ok=1
  require "$OUTPUT_SECTION" 'multiple named operations (endpoints, CLI commands/flags, steps, events)' || ok=1
  require "$OUTPUT_SECTION" 'you may optionally include a structured table' || ok=1
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
# =============================================================================
test_entities_table_02() {
  ok=0
  require "$OUTPUT_SECTION" 'entities table with columns Name, Path, New-or-Existing, Notes' || ok=1
  require "$OUTPUT_SECTION" 'operations table with columns Type, Identifier, Description' || ok=1
  return $ok
}

# =============================================================================
# entities-table-03: the table is a scannable complement, never a
# replacement for the Gherkin scenarios.
# =============================================================================
test_entities_table_03() {
  ok=0
  require "$OUTPUT_SECTION" 'scannable complement to the prose contract sections' || ok=1
  require "$OUTPUT_SECTION" 'Gherkin scenarios remain the actual testable behavior spec, never replaced by the table' || ok=1
  return $ok
}

# =============================================================================
# entities-table-04: the table is optional per change, never mandatory --
# explicitly not forced when there is no new data shape and at most one
# operation.
# =============================================================================
test_entities_table_04() {
  ok=0
  require "$OUTPUT_SECTION" 'This table is never mandatory' || ok=1
  require "$OUTPUT_SECTION" 'a change with no new data shape and only one operation should not be forced to produce a near-empty table' || ok=1
  return $ok
}

# =============================================================================
# entities-table-05: the rigid "fill every section or mark not applicable"
# behavior of the open-spdd canvas template is explicitly not adopted --
# only the table format itself is.
# =============================================================================
test_entities_table_05() {
  ok=0
  require "$OUTPUT_SECTION" 'require marking every section "not applicable" when empty' || ok=1
  require "$OUTPUT_SECTION" 'mandate filling a table regardless of relevance' || ok=1
  require "$OUTPUT_SECTION" 'only the table format itself is adopted as an available tool, not a rigid always-fill-every-section requirement' || ok=1
  # Negative sentinel: don't require/mandate wording must be phrased as a
  # refusal (Don't/don't), not accidentally stated as a requirement.
  refuse "$OUTPUT_SECTION" 'You must mark every section' || ok=1
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "entities-table-01: Output section states the optional Entities/Operations table for a new data shape or multiple named operations" test_entities_table_01
run_test "entities-table-01: the table-introducing bullet no longer contains the literal string README.md" test_entities_table_01_no_readme_mention
run_test "entities-table-02: exact column sets stated for the entities table and the operations table" test_entities_table_02
run_test "entities-table-03: table is a scannable complement, Gherkin scenarios remain the actual testable behavior spec" test_entities_table_03
run_test "entities-table-04: table is not mandatory; a single-operation, no-new-data-shape change is not forced to produce a near-empty table" test_entities_table_04
run_test "entities-table-05: no rigid always-fill-every-section requirement is adopted, only the table format itself" test_entities_table_05

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
