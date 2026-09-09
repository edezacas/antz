#!/usr/bin/env bash
# Unit tests for the fixed-overview-file-name bullet added to the "## Output"
# section of agents/prompts/specifier.prompt, covering every scenario in
# spdd/changes/specifier-readme-fixed-name/01-readmefile.feature
# (readmefile-01..03). The accompanying MODIFY of entities-table-01 (the
# Entities/Operations table bullet no longer names README.md itself) is
# covered in tests/entities-operations-table_test.sh, not here.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/entities-operations-table_test.sh. Run directly:
#   ./tests/readmefile_test.sh
#
# Every scenario here is a deterministic content assertion against the
# static text of agents/prompts/specifier.prompt's "## Output" section
# (grep-style), not a live LLM invocation -- per the sub-spec's Verification
# levels. e2e-qa.feature covers the live-session behavior this instruction
# produces and belongs to the verifier's end-to-end suite, not this unit
# suite.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/entities-operations-table_test.sh) ---

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
# readmefile-01: a dedicated bullet states that the change's overview --
# goal, contract, shared contracts, invariants, out-of-scope, and
# relevant-files pointers -- is written to the fixed file README.md, and
# this statement is its own bullet, not scoped only to the
# Entities/Operations table bullet.
# =============================================================================
test_readmefile_01() {
  ok=0
  require "$OUTPUT_SECTION" 'goal' || ok=1
  require "$OUTPUT_SECTION" 'contract' || ok=1
  require "$OUTPUT_SECTION" 'shared contracts' || ok=1
  require "$OUTPUT_SECTION" 'invariants' || ok=1
  require "$OUTPUT_SECTION" 'out-of-scope' || ok=1
  require "$OUTPUT_SECTION" 'relevant-files pointers' || ok=1
  require "$OUTPUT_SECTION" 'fixed file `README.md`' || ok=1

  # It must be its own bullet: a line starting with "- " that names
  # README.md, distinct from the Entities/Operations table bullet (which
  # starts with "- When a change introduces").
  README_BULLET=$(grep -F -- '`README.md`' "$OUTPUT_SECTION")
  case "$README_BULLET" in
    '- When a change introduces'*)
      echo "  README.md is only mentioned inside the Entities/Operations table bullet, not its own bullet"
      ok=1
      ;;
  esac
  case "$README_BULLET" in
    '- '*) ;;
    *)
      echo "  the README.md-naming line is not its own bullet: $README_BULLET"
      ok=1
      ;;
  esac
  return $ok
}

# =============================================================================
# readmefile-02: the fixed name is stated once, directly -- no repetition
# within or across bullets.
# =============================================================================
test_readmefile_02() {
  ok=0
  occurrences=$(grep -oF 'README.md' "$OUTPUT_SECTION" | wc -l | tr -d ' ')
  if [ "$occurrences" != "1" ]; then
    echo "  expected exactly one occurrence of README.md in the Output section, found $occurrences"
    ok=1
  fi

  # No single bullet (line) contains the literal string more than once.
  while IFS= read -r line; do
    count=$(printf '%s' "$line" | grep -oF 'README.md' | wc -l | tr -d ' ')
    if [ "$count" -gt 1 ]; then
      echo "  a single bullet contains README.md more than once: $line"
      ok=1
    fi
  done < "$OUTPUT_SECTION"

  return $ok
}

# =============================================================================
# readmefile-03: no rejected alternative names are enumerated or discussed --
# the fixed name is stated directly.
# =============================================================================
test_readmefile_03() {
  ok=0
  refuse "$OUTPUT_SECTION" 'OVERVIEW.md' || ok=1
  refuse "$OUTPUT_SECTION" 'SUMMARY.md' || ok=1
  refuse "$OUTPUT_SECTION" 'NOTES.md' || ok=1
  # No justification/discussion wording for the choice of README.md.
  refuse "$OUTPUT_SECTION" 'instead of' || ok=1
  refuse "$OUTPUT_SECTION" 'rather than using' || ok=1
  refuse "$OUTPUT_SECTION" 'chosen over' || ok=1
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "readmefile-01: a dedicated bullet states the change's overview is written to the fixed file README.md, as its own bullet" test_readmefile_01
run_test "readmefile-02: README.md appears exactly once in the Output section and no bullet repeats it" test_readmefile_02
run_test "readmefile-03: no rejected alternative file name is enumerated or discussed" test_readmefile_03

rm -f "$OUTPUT_SECTION"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped"
[ "$fail_count" -eq 0 ]
