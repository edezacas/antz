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
# probe-rejected-count-trailing-space: trailing whitespace (a stray space, or
# CRLF's \r) on the heading line is invisible to a human and still counts --
# unlike trailing text, which does not.
# =============================================================================
test_probe_rejected_count_trailing_space() {
  dir=$(new_change_dir)
  printf '## Rejection 1 \n\nblocker\n' > "$dir/REJECTED.md"
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'rejected_count=1' || { echo "  trailing-space heading was not counted: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-ids-ignore-loose-comments: an id-shaped token in a comment that
# is NOT the tag immediately above a Scenario must NOT be picked up -- only the
# comment tag immediately above each Scenario: line counts. A phantom id (one
# no test will ever satisfy) would keep a sub-spec perpetually in_progress and
# re-delegate coder forever.
# =============================================================================
test_probe_subspec_ids_ignore_loose_comments() {
  dir=$(new_change_dir)
  cat > "$dir/01-api.feature" <<'EOF'
Feature: API

# NOTE: implements invariant-2 of the versioning spec

# api-1
Scenario: creates a resource
  Given a valid payload
  When the request is sent
  Then a 201 is returned
EOF
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1' \
    || { echo "  expected exactly ids=api-1, got: $out"; ok=1; }
  echo "$out" | grep -q 'invariant-2' && { echo "  phantom id invariant-2 leaked: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-ids-tag-reset: a Scenario directly following another Scenario
# (no tag of its own) gets no id -- the tag must be immediately above each
# scenario, never inherited from a previous one.
# =============================================================================
test_probe_subspec_ids_tag_reset() {
  dir=$(new_change_dir)
  cat > "$dir/01-api.feature" <<'EOF'
Feature: API

# api-1
Scenario: first
  Given a
Scenario: second
  Given b
EOF
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1' \
    || { echo "  expected exactly ids=api-1, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-ids-hyphenated-feature: a hyphenated feature name survives the
# extraction whole (user-profile-1, not the split-off profile-1 the old regex
# produced), so the probe stays in sync with the ids the coder tags tests with
# even when the specifier's one-word naming rule is violated.
# =============================================================================
test_probe_subspec_ids_hyphenated_feature() {
  dir=$(new_change_dir)
  printf 'Feature: User profile\n\n# user-profile-1\nScenario: shows the profile\n  Given a user\n' > "$dir/01-user-profile.feature"
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-user-profile.feature ids=user-profile-1' \
    || { echo "  hyphenated id was split: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-change-dir-missing-path: CHANGE_DIR set but pointing at a nonexistent
# directory must fail fast with change_dir=missing and a non-zero exit --
# reporting a clean state (no open questions, 0 rejections, no sub-specs) would
# invite routing straight to verifier on a mistyped slug.
# =============================================================================
test_probe_change_dir_missing_path() {
  root=$(mktemp -d)
  ok=0
  out=$(CHANGE_DIR="$root/spdd/changes/no-such-slug" sh "$PROBE_SCRIPT" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || { echo "  expected non-zero exit for a missing change dir, got 0"; ok=1; }
  echo "$out" | grep -qxF 'change_dir=missing' || { echo "  missing change_dir=missing marker: $out"; ok=1; }
  rm -rf "$root"
  return $ok
}

# =============================================================================
# probe-subspec-ids-scenario-outline: the tag above a `Scenario Outline:` (the
# specifier's documented way to express example tables, and what the repo's
# own archived sub-specs use) must be picked up exactly like a plain
# `Scenario:` -- an empty ids list there would make the orchestrator stop and
# ask the user on every example-table sub-spec.
# =============================================================================
test_probe_subspec_ids_scenario_outline() {
  dir=$(new_change_dir)
  cat > "$dir/01-api.feature" <<'EOF'
Feature: API

# api-1
Scenario Outline: creates a resource
  Given a "<status>" payload
  When the request is sent
  Then a <code> is returned

  Examples:
    | status | code |
    | valid  | 201  |
    | invalid | 400 |
EOF
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1' \
    || { echo "  Scenario Outline: tag was not picked up: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-ids-multiline-tag: the tag comment immediately above a
# Scenario may span several lines (the repo's own convention:
# `# ADD - <id>: description` with the description wrapping), with the id on
# the first line -- the whole comment block counts, not just its last line.
# =============================================================================
test_probe_subspec_ids_multiline_tag() {
  dir=$(new_change_dir)
  cat > "$dir/01-install.feature" <<'EOF'
Feature: install.sh installs the command

  # ADD - command-install-01: install.sh installs the Claude Code copy with
  # the expected frontmatter shape, mirroring how it already installs /antz.
  Scenario: command-install-01
    Given a clean commands directory
    When the user runs the installer
    Then the command file is created
EOF
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-install.feature ids=command-install-01' \
    || { echo "  multi-line tag id was missed: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# probe-subspec-ids-ignore-tag-crossrefs: another scenario's id mentioned in a
# tag's description continuation line (a cross-reference like "same refusal
# message as set-model-cmd-06", present in the repo's own archived specs) is
# NOT a declared id -- only the tag's first line carries the id.
# =============================================================================
test_probe_subspec_ids_ignore_tag_crossrefs() {
  dir=$(new_change_dir)
  cat > "$dir/01-picker.feature" <<'EOF'
Feature: picker

  # ADD - picker-cmd-01: an unknown agent is refused before any question is
  # asked -- same refusal message as set-model-cmd-06.
  Scenario: picker-cmd-01
    Given no file exists
    When the command is invoked
    Then the reply explains the refusal
EOF
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-picker.feature ids=picker-cmd-01' \
    || { echo "  expected exactly ids=picker-cmd-01, got: $out"; ok=1; }
  echo "$out" | grep -q 'set-model-cmd-06' && { echo "  cross-reference leaked as id: $out"; ok=1; }
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
run_test "probe-rejected-count-trailing-space: a heading with trailing whitespace still counts" test_probe_rejected_count_trailing_space
run_test "probe-subspec-ids-from-comments: ids are read from the comment tag above each scenario, in filename order" test_probe_subspec_ids_from_comments
run_test "probe-subspec-ids-ignore-prose: an id-shaped token in ordinary prose (not a comment) is not picked up" test_probe_subspec_ids_ignore_prose
run_test "probe-subspec-ids-ignore-loose-comments: an id-shaped token in a comment not above a Scenario is not picked up" test_probe_subspec_ids_ignore_loose_comments
run_test "probe-subspec-ids-tag-reset: a tagless Scenario following a tagged one inherits no id" test_probe_subspec_ids_tag_reset
run_test "probe-subspec-ids-hyphenated-feature: a hyphenated feature name survives extraction whole" test_probe_subspec_ids_hyphenated_feature
run_test "probe-subspec-ids-scenario-outline: the tag above a Scenario Outline is picked up like a plain Scenario" test_probe_subspec_ids_scenario_outline
run_test "probe-subspec-ids-multiline-tag: an id on the first line of a multi-line tag comment is picked up" test_probe_subspec_ids_multiline_tag
run_test "probe-subspec-ids-ignore-tag-crossrefs: another scenario's id in a tag description line is not picked up" test_probe_subspec_ids_ignore_tag_crossrefs
run_test "probe-subspec-empty-ids: an untagged sub-spec reports an empty ids list without crashing" test_probe_subspec_empty_ids
run_test "probe-no-subspecs: no sub-spec files yet still succeeds, with no subspec= lines" test_probe_no_subspecs
run_test "probe-missing-change-dir: unset CHANGE_DIR fails fast with a clear message" test_probe_missing_change_dir
run_test "probe-change-dir-missing-path: a CHANGE_DIR pointing at a nonexistent directory fails fast with change_dir=missing" test_probe_change_dir_missing_path

rm -f "$PROBE_SCRIPT"

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
