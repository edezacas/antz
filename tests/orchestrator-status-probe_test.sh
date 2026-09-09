#!/usr/bin/env bash
# Unit tests for the POSIX sh probe script embedded in
# agents/prompts/orchestrator.prompt (the "Probe disk state" step of the
# orchestrator's Process). The script computes purely mechanical,
# disk-derivable facts -- OPEN_QUESTIONS.md presence, REJECTED.md's entry
# count, and each sub-spec's declared scenario ids -- so the orchestrator
# prompt itself doesn't have to spell out that procedure in prose.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/set-model-command_test.sh and tests/versioning-rule_test.sh. Run
# directly:
#   ./tests/orchestrator-status-probe_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"

pass_count=0
fail_count=0

# ---- tiny test runner ------------------------------------------------------

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

# ---- extracting the embedded script from the prompt -------------------------

extract_script() {
  # Prints just the fenced ```sh ... ``` script embedded in the prompt body.
  awk '/^   ```sh$/{flag=1; next} /^   ```$/{flag=0} flag' "$ORCHESTRATOR_PROMPT" | sed 's/^   //'
}

PROBE_SCRIPT=$(mktemp)
extract_script > "$PROBE_SCRIPT"
chmod +x "$PROBE_SCRIPT"

run_probe() {
  # $1 = change dir. Runs the extracted probe script with CHANGE_DIR set.
  CHANGE_DIR="$1" sh "$PROBE_SCRIPT"
}

new_change_dir() {
  mktemp -d
}

# =============================================================================
# probe-extracted: the script was actually found and extracted (guards every
# other test against a silent no-op if the fence markers ever change shape).
# =============================================================================
test_probe_extracted() {
  [ -s "$PROBE_SCRIPT" ] || { echo "  no script extracted from $ORCHESTRATOR_PROMPT"; return 1; }
  grep -q 'CHANGE_DIR must be set' "$PROBE_SCRIPT" || { echo "  extracted content doesn't look like the probe script"; return 1; }
  return 0
}

# =============================================================================
# probe-open-questions: OPEN_QUESTIONS.md present short-circuits the probe --
# only open_questions=yes is printed, nothing else, exit 0.
# =============================================================================
test_probe_open_questions() {
  dir=$(new_change_dir)
  : > "$dir/OPEN_QUESTIONS.md"
  ok=0

  out=$(run_probe "$dir")
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status"; ok=1; }
  [ "$out" = "open_questions=yes" ] || { echo "  expected exactly 'open_questions=yes', got: $out"; ok=1; }

  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-no-open-questions: without OPEN_QUESTIONS.md, prints open_questions=no
# then rejected_count=0 (no REJECTED.md yet).
# =============================================================================
test_probe_no_open_questions() {
  dir=$(new_change_dir)
  ok=0

  out=$(run_probe "$dir")
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status"; ok=1; }
  echo "$out" | grep -qxF 'open_questions=no' || { echo "  missing open_questions=no: $out"; ok=1; }
  echo "$out" | grep -qxF 'rejected_count=0' || { echo "  missing rejected_count=0: $out"; ok=1; }

  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-rejected-count: counts exact '## Rejection <n>' headings only.
# =============================================================================
test_probe_rejected_count_one() {
  dir=$(new_change_dir)
  printf '## Rejection 1\n\nsome blocker text\n' > "$dir/REJECTED.md"
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'rejected_count=1' || { echo "  expected rejected_count=1, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

test_probe_rejected_count_two() {
  dir=$(new_change_dir)
  printf '## Rejection 1\n\nfirst blocker\n\n## Rejection 2\n\nsecond blocker\n' > "$dir/REJECTED.md"
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'rejected_count=2' || { echo "  expected rejected_count=2, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-rejected-count-malformed: a heading with trailing text on the same
# line does NOT count -- the convention requires nothing else on that line.
# =============================================================================
test_probe_rejected_count_malformed_not_counted() {
  dir=$(new_change_dir)
  printf '## Rejection 1: cross-feature coherence issue\n\nblocker text\n' > "$dir/REJECTED.md"
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'rejected_count=0' || { echo "  malformed heading was counted: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-ids: scenario ids are read from comment lines (the specifier's
# tagging convention), in filename (dependency) order.
# =============================================================================
test_probe_subspec_ids_from_comments() {
  dir=$(new_change_dir)
  cat > "$dir/01-api.feature" <<'EOF'
Feature: API

# api-1
Scenario: creates a resource
  Given a valid payload
  When the request is sent
  Then a 201 is returned

# api-2
Scenario: rejects an invalid payload
  Given an invalid payload
  When the request is sent
  Then a 400 is returned
EOF
  cat > "$dir/02-client.feature" <<'EOF'
Feature: Client

# client-1
Scenario: renders the result
  Given a successful API response
  When the page loads
  Then the result is shown
EOF
  ok=0
  out=$(run_probe "$dir")

  first_line=$(echo "$out" | grep '^subspec=')
  order=$(echo "$first_line" | head -n1)
  case "$order" in
    subspec=01-api.feature*) ;;
    *) echo "  expected 01-api.feature listed first, got: $order"; ok=1 ;;
  esac

  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1,api-2' \
    || { echo "  wrong ids for 01-api.feature: $out"; ok=1; }
  echo "$out" | grep -qxF 'subspec=02-client.feature ids=client-1' \
    || { echo "  wrong ids for 02-client.feature: $out"; ok=1; }

  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-ids-ignore-prose: an id-shaped token that appears in ordinary
# prose (not a comment line) must NOT be picked up -- only the comment-tagged
# convention counts, to avoid false ids the test suite will never satisfy.
# =============================================================================
test_probe_subspec_ids_ignore_prose() {
  dir=$(new_change_dir)
  cat > "$dir/01-api.feature" <<'EOF'
Feature: API

Contract: request bodies are utf-8 encoded, per RFC-2.

# api-1
Scenario: creates a resource
  Given a valid payload
  When the request is sent
  Then a 201 is returned
EOF
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1' \
    || { echo "  prose-only tokens leaked into ids: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-empty-ids: a sub-spec with no comment-tagged ids yet doesn't
# crash the probe -- it just reports an empty ids list.
# =============================================================================
test_probe_subspec_empty_ids() {
  dir=$(new_change_dir)
  printf 'Feature: API\n\nScenario: untagged\n  Given nothing\n' > "$dir/01-api.feature"
  ok=0
  out=$(run_probe "$dir")
  status=$?
  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status"; ok=1; }
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=' \
    || { echo "  expected empty ids for untagged sub-spec, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-no-subspecs: no [0-9][0-9]-*.feature files present -- probe still
# succeeds, printing only the open_questions/rejected_count facts.
# =============================================================================
test_probe_no_subspecs() {
  dir=$(new_change_dir)
  ok=0
  out=$(run_probe "$dir")
  status=$?
  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status"; ok=1; }
  echo "$out" | grep -q '^subspec=' && { echo "  unexpected subspec line with no sub-spec files: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-missing-change-dir: CHANGE_DIR unset fails fast with a clear message,
# per the script's set -u guard.
# =============================================================================
test_probe_missing_change_dir() {
  ok=0
  out=$(env -u CHANGE_DIR sh "$PROBE_SCRIPT" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || { echo "  expected non-zero exit with CHANGE_DIR unset, got 0"; ok=1; }
  case "$out" in *"CHANGE_DIR must be set"*) ;; *) echo "  missing guard message: $out"; ok=1 ;; esac
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "probe-extracted: the embedded probe script is found and looks correct" test_probe_extracted
run_test "probe-open-questions: OPEN_QUESTIONS.md present short-circuits to exactly one line" test_probe_open_questions
run_test "probe-no-open-questions: prints open_questions=no and rejected_count=0 with no REJECTED.md" test_probe_no_open_questions
run_test "probe-rejected-count-one: counts a single exact '## Rejection 1' heading" test_probe_rejected_count_one
run_test "probe-rejected-count-two: counts two exact '## Rejection N' headings" test_probe_rejected_count_two
run_test "probe-rejected-count-malformed: a heading with trailing text on the line is not counted" test_probe_rejected_count_malformed_not_counted
run_test "probe-subspec-ids-from-comments: ids are read from the comment tag above each scenario, in filename order" test_probe_subspec_ids_from_comments
run_test "probe-subspec-ids-ignore-prose: an id-shaped token in ordinary prose (not a comment) is not picked up" test_probe_subspec_ids_ignore_prose
run_test "probe-subspec-empty-ids: an untagged sub-spec reports an empty ids list without crashing" test_probe_subspec_empty_ids
run_test "probe-no-subspecs: no sub-spec files yet still succeeds, with no subspec= lines" test_probe_no_subspecs
run_test "probe-missing-change-dir: unset CHANGE_DIR fails fast with a clear message" test_probe_missing_change_dir

rm -f "$PROBE_SCRIPT"

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
