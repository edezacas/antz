#!/usr/bin/env bash
# Unit tests for scripts/orchestration/antz-probe.sh — the POSIX sh probe the
# orchestrator prompt's "Probe disk state" step runs (injected into the
# rendered antz-orchestrator body by install.sh since change
# orchestrator-fast-path). The script computes purely mechanical,
# disk-derivable facts -- OPEN_QUESTIONS.md presence, REJECTED.md's entry
# count, and each sub-spec's declared scenario ids -- so the orchestrator
# prompt itself doesn't have to spell out that procedure in prose.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/set-model-command_test.sh and tests/versioning-rule_test.sh. Run
# directly:
#   ./tests/orchestrator-status-probe_test.sh
#
# Since change orchestrator-fast-path (sub-spec 01) the probe is a real file
# and the prompt's fence carries only its include marker, so this suite runs
# the file directly -- no extraction from the prompt anymore (testharness-02).
#
# Evolved by change orchestrator-fast-path (sub-spec 05, receipts): the probe
# also reads the coder's result receipts (spdd/changes/<slug>/NN-<feature>
# .result, the classification authority since receipts-07) and extends every
# subspec= line with receipt=/covered=/complete=/class= -- classification
# becomes file reading. The pre-existing ids tests below now assert the full
# extended line (with a receipt-less fixture: receipt=missing covered=0/N
# complete=no class=in_progress); the receipts-06 runtime tests cover the
# receipt-driven fields themselves. The probe's other outputs
# (open_questions=, rejected_count=, the change_dir=missing short-circuit,
# the empty-ids report) are unchanged.
#
# Grown by change fix-orchestrator-flow (sub-spec 02-receipts): the sentinel
# fixtures below pin that the probe accepts the literal `none`
# test_command= value as well-formed non-empty (complete may be yes) with no
# probe code change -- scripts/orchestration/antz-probe.sh stays
# byte-unchanged by that change.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
PROBE_SH="$SCRIPT_DIR/scripts/orchestration/antz-probe.sh"

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

# ---- the script under test (a file, run directly) ---------------------------

run_probe() {
  # $1 = change dir. Runs the probe script with CHANGE_DIR set.
  CHANGE_DIR="$1" sh "$PROBE_SH"
}

new_change_dir() {
  mktemp -d
}

# ---- receipts-06 helpers -----------------------------------------------------

# The exact full subspec= line the probe emits for a sub-spec with no receipt
# file: the ids are reported as always, and the receipt fields read
# receipt=missing covered=0/N complete=no class=in_progress.
subspec_line_no_receipt() {
  # $1 = feature filename, $2 = ids, $3 = declared id count
  printf 'subspec=%s ids=%s receipt=missing covered=0/%s complete=no class=in_progress' "$1" "$2" "$3"
}

# Writes a feature file declaring the given ids and, optionally, a receipt
# named after it. $1 = change dir, $2 = feature filename, $3 = ids
# (comma-separated), $4 = receipt content ("-" for no receipt).
write_subspec_fixture() {
  dir="$1"; fname="$2"; ids="$3"; receipt="$4"
  {
    printf 'Feature: fixture\n'
    oldifs=$IFS
    IFS=,
    for id in $ids; do
      printf '\n# %s\nScenario: %s\n  Given a\n' "$id" "$id"
    done
    IFS=$oldifs
  } > "$dir/$fname"
  if [ "$receipt" != "-" ]; then
    printf '%s\n' "$receipt" > "$dir/${fname%.feature}.result"
  fi
}

# =============================================================================
# probe-extracted: the script under test is the real file (guards every other
# test against a silent no-op if the file ever goes missing or its shape
# changes).
# =============================================================================
test_probe_extracted() {
  [ -s "$PROBE_SH" ] || { echo "  no probe script at scripts/orchestration/antz-probe.sh"; return 1; }
  grep -q 'CHANGE_DIR must be set' "$PROBE_SH" || { echo "  the file doesn't look like the probe script"; return 1; }
  return 0
}

# =============================================================================
# testharness-02: the suite runs scripts/orchestration/antz-probe.sh directly
# (no extraction from the prompt) -- the file exists, parses as POSIX sh,
# keeps its shebang, and the prompt's probe fence carries exactly its include
# marker line, so there is no embedded probe left to extract.
# =============================================================================
test_testharness_02_file_source() {
  ok=0
  [ "$PROBE_SH" = "$SCRIPT_DIR/scripts/orchestration/antz-probe.sh" ] \
    || { echo "  the suite is not running scripts/orchestration/antz-probe.sh"; ok=1; }
  sh -n "$PROBE_SH" || { echo "  probe file fails sh -n"; ok=1; }
  [ "$(head -n 1 "$PROBE_SH")" = '#!/bin/sh' ] \
    || { echo "  probe file lost its shebang first line"; ok=1; }
  body=$(awk '/^   ```sh$/{p=1; next} /^   ```$/{p=0} p' "$ORCHESTRATOR_PROMPT" | sed 's/^   //')
  [ "$body" = '# antz-include: scripts/orchestration/antz-probe.sh' ] \
    || { echo "  prompt probe fence is not a bare include marker: $body"; ok=1; }
  return $ok
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

  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-api.feature 'api-1,api-2' 2)" \
    || { echo "  wrong line for 01-api.feature: $out"; ok=1; }
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 02-client.feature 'client-1' 1)" \
    || { echo "  wrong line for 02-client.feature: $out"; ok=1; }

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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-api.feature 'api-1' 1)" \
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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-api.feature '' 0)" \
    || { echo "  expected receipt-less empty-ids line for untagged sub-spec, got: $out"; ok=1; }
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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-api.feature 'api-1' 1)" \
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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-api.feature 'api-1' 1)" \
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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-user-profile.feature 'user-profile-1' 1)" \
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
  out=$(CHANGE_DIR="$root/spdd/changes/no-such-slug" sh "$PROBE_SH" 2>&1)
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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-api.feature 'api-1' 1)" \
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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-install.feature 'command-install-01' 1)" \
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
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-picker.feature 'picker-cmd-01' 1)" \
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
  out=$(env -u CHANGE_DIR sh "$PROBE_SH" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || { echo "  expected non-zero exit with CHANGE_DIR unset, got 0"; ok=1; }
  case "$out" in *"CHANGE_DIR must be set"*) ;; *) echo "  missing guard message: $out"; ok=1 ;; esac
  return $ok
}

# =============================================================================
# receipts-06: the probe reads the coder's receipts and extends every
# subspec= line with receipt=<file|missing> covered=<n>/<N>
# complete=<yes|no> class=<done|blocked|in_progress> -- classification
# becomes file reading. complete=yes requires the receipt to exist, carry
# exactly one non-empty test_command= line, and name exactly the declared id
# set (a foreign id is a mismatch: covered may still read N/N but
# complete=no). class= applies the mapping: any result=blocked line ->
# blocked (checked first, regardless of coverage); else complete=yes with
# all results green or skip -> done; else in_progress.
# =============================================================================

# receipts-06: every subspec= line carries the four receipt fields, in the
# field order the change contract pins, after the unchanged ids= field.
test_receipts_06_line_shape() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' '-'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qE '^subspec=01-api\.feature ids=api-1,api-2 receipt=[^ ]* covered=[0-9]+/[0-9]+ complete=(yes|no) class=(done|blocked|in_progress)$' \
    || { echo "  subspec line lacks the receipt fields in order: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: no receipt file -> receipt=missing, covered=0/N, complete=no,
# class=in_progress (never vacuously done).
test_receipts_06_receipt_missing() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' '-'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF "$(subspec_line_no_receipt 01-api.feature 'api-1,api-2' 2)" \
    || { echo "  expected receipt=missing fields, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: a complete receipt with every id green -> class=done.
test_receipts_06_done_all_green() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' 'test_command=sh tests/api_test.sh
id=api-1 result=green reason=api-1 unit test
id=api-2 result=green reason=api-2 unit test'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1,api-2 receipt=01-api.result covered=2/2 complete=yes class=done' \
    || { echo "  expected complete green receipt classified done, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: an ordinary skip (result=skip, honest reason) is green-class:
# complete=yes -> done.
test_receipts_06_done_ordinary_skip() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-ui.feature 'ui-1,ui-2' 'test_command=sh tests/ui_test.sh
id=ui-1 result=green reason=ui-1 unit test
id=ui-2 result=skip reason=visual-only scenario, not unit-testable'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-ui.feature ids=ui-1,ui-2 receipt=01-ui.result covered=2/2 complete=yes class=done' \
    || { echo "  expected skip row classified done, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: any result=blocked line makes the sub-spec blocked, checked
# first regardless of coverage -- a partial receipt (1/2 covered,
# complete=no) with a blocked id is blocked, never in_progress.
test_receipts_06_blocked_first_regardless_of_coverage() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' 'test_command=sh tests/api_test.sh
id=api-1 result=blocked reason=BLOCKED: shared contract needs changing first'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1,api-2 receipt=01-api.result covered=1/2 complete=no class=blocked' \
    || { echo "  expected partial blocked receipt classified blocked, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: a complete receipt carrying a blocked id is blocked (blocked
# outranks done -- done requires every id green/ordinary-skip).
test_receipts_06_blocked_outranks_complete() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' 'test_command=sh tests/api_test.sh
id=api-1 result=green reason=api-1 unit test
id=api-2 result=blocked reason=BLOCKED: escalation pending'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1,api-2 receipt=01-api.result covered=2/2 complete=yes class=blocked' \
    || { echo "  expected complete blocked receipt classified blocked, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: a receipt without any test_command= line is incomplete ->
# complete=no, class=in_progress.
test_receipts_06_no_test_command_incomplete() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1' 'id=api-1 result=green reason=api-1 unit test'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1 receipt=01-api.result covered=1/1 complete=no class=in_progress' \
    || { echo "  expected receipt without test_command classified in_progress, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: two test_command= lines violate the one-line grammar ->
# complete=no, class=in_progress.
test_receipts_06_two_test_commands_incomplete() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1' 'test_command=sh tests/api_test.sh
test_command=sh tests/other_test.sh
id=api-1 result=green reason=api-1 unit test'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1 receipt=01-api.result covered=1/1 complete=no class=in_progress' \
    || { echo "  expected two test_command lines classified in_progress, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: an empty test_command= value is not a non-empty command line
# -> complete=no, class=in_progress.
test_receipts_06_empty_test_command_incomplete() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1' 'test_command=
id=api-1 result=green reason=api-1 unit test'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1 receipt=01-api.result covered=1/1 complete=no class=in_progress' \
    || { echo "  expected empty test_command value classified in_progress, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: a foreign id (not declared by the sub-spec) is a mismatch --
# covered may still read N/N but complete=no, class=in_progress.
test_receipts_06_foreign_id_mismatch() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' 'test_command=sh tests/api_test.sh
id=api-1 result=green reason=api-1 unit test
id=api-2 result=green reason=api-2 unit test
id=other-9 result=green reason=not declared here'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1,api-2 receipt=01-api.result covered=2/2 complete=no class=in_progress' \
    || { echo "  expected foreign id to force complete=no, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: a duplicate id line violates the exact id-set grammar ->
# complete=no, class=in_progress.
test_receipts_06_duplicate_id_mismatch() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1' 'test_command=sh tests/api_test.sh
id=api-1 result=green reason=api-1 unit test
id=api-1 result=green reason=api-1 unit test again'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1 receipt=01-api.result covered=1/1 complete=no class=in_progress' \
    || { echo "  expected duplicate id line classified in_progress, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: a declared id with no receipt line is uncovered -> covered
# reads below N/N, complete=no, class=in_progress (never a silent omission
# counted as done).
test_receipts_06_missing_declared_id_incomplete() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' 'test_command=sh tests/api_test.sh
id=api-1 result=green reason=api-1 unit test'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1,api-2 receipt=01-api.result covered=1/2 complete=no class=in_progress' \
    || { echo "  expected uncovered id to force complete=no, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: an id line with an empty reason violates the grammar ->
# complete=no, class=in_progress.
test_receipts_06_empty_reason_incomplete() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1' 'test_command=sh tests/api_test.sh
id=api-1 result=green reason='
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1 receipt=01-api.result covered=1/1 complete=no class=in_progress' \
    || { echo "  expected empty-reason id line classified in_progress, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: a receipt for an untagged sub-spec (empty declared ids) is
# never vacuously done -- with no ids there is nothing to classify, so the
# probe reports complete=no class=in_progress (the orchestrator's own
# stop-and-ask rule for empty ids stays prompt law on top).
test_receipts_06_empty_ids_never_done() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature '' 'test_command=sh tests/api_test.sh'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids= receipt=01-api.result covered=0/0 complete=no class=in_progress' \
    || { echo "  expected empty-ids sub-spec never vacuously done, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# =============================================================================
# receipts-06 (fix-orchestrator-flow/02-receipts, property pin): the probe
# accepts the literal `none` sentinel (the receipt grammar's one defined
# non-command value, written when no suite is genuinely discoverable) as a
# well-formed NON-EMPTY test_command= value -- any non-empty value already
# satisfies the grammar check, so this needs no probe code change and pins
# that a future grammar tightening cannot silently reject the sentinel.
# =============================================================================

# receipts-06: test_command=none + exactly the declared id set, all green ->
# complete=yes class=done (the sentinel is accepted, the mapping unchanged).
test_receipts_06_none_sentinel_all_green_done() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-api.feature 'api-1,api-2' 'test_command=none
id=api-1 result=green reason=api-1 unit test
id=api-2 result=green reason=api-2 unit test'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-api.feature ids=api-1,api-2 receipt=01-api.result covered=2/2 complete=yes class=done' \
    || { echo "  expected the none sentinel accepted as a well-formed non-empty test_command= value (complete=yes class=done), got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# receipts-06: the sentinel receipt with an ordinary skip row among the green
# ids -> still complete=yes class=done (green-or-ordinary-skip, unchanged).
test_receipts_06_none_sentinel_skip_row_done() {
  dir=$(new_change_dir)
  write_subspec_fixture "$dir" 01-ui.feature 'ui-1,ui-2' 'test_command=none
id=ui-1 result=green reason=ui-1 unit test
id=ui-2 result=skip reason=visual-only scenario, not unit-testable'
  ok=0
  out=$(run_probe "$dir")
  echo "$out" | grep -qxF 'subspec=01-ui.feature ids=ui-1,ui-2 receipt=01-ui.result covered=2/2 complete=yes class=done' \
    || { echo "  expected none-sentinel receipt with a skip row classified done, got: $out"; ok=1; }
  rm -rf "$dir"
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "probe-extracted: scripts/orchestration/antz-probe.sh is found and looks correct" test_probe_extracted
run_test "testharness-02: the probe suite runs scripts/orchestration/antz-probe.sh directly (no extraction from the prompt)" test_testharness_02_file_source
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
run_test "receipts-06: every subspec= line carries receipt= covered= complete= class= in the pinned field order" test_receipts_06_line_shape
run_test "receipts-06: no receipt file reads receipt=missing covered=0/N complete=no class=in_progress" test_receipts_06_receipt_missing
run_test "receipts-06: a complete all-green receipt classifies done" test_receipts_06_done_all_green
run_test "receipts-06: an ordinary skip row in a complete receipt classifies done" test_receipts_06_done_ordinary_skip
run_test "receipts-06: any result=blocked line classifies blocked, checked first regardless of coverage" test_receipts_06_blocked_first_regardless_of_coverage
run_test "receipts-06: a complete receipt with a blocked id still classifies blocked (blocked outranks done)" test_receipts_06_blocked_outranks_complete
run_test "receipts-06: a receipt with no test_command= line is incomplete, class in_progress" test_receipts_06_no_test_command_incomplete
run_test "receipts-06: two test_command= lines violate the grammar, class in_progress" test_receipts_06_two_test_commands_incomplete
run_test "receipts-06: an empty test_command= value is not a non-empty command line, class in_progress" test_receipts_06_empty_test_command_incomplete
run_test "receipts-06: a foreign id forces complete=no even when covered reads N/N" test_receipts_06_foreign_id_mismatch
run_test "receipts-06: a duplicate id line forces complete=no" test_receipts_06_duplicate_id_mismatch
run_test "receipts-06: a declared id with no receipt line is uncovered, complete=no" test_receipts_06_missing_declared_id_incomplete
run_test "receipts-06: an id line with an empty reason forces complete=no" test_receipts_06_empty_reason_incomplete
run_test "receipts-06: an empty-ids sub-spec is never vacuously done, even with a receipt present" test_receipts_06_empty_ids_never_done
run_test "receipts-06: the literal none sentinel is a well-formed non-empty test_command= value -- all-green ids give complete=yes class=done" test_receipts_06_none_sentinel_all_green_done
run_test "receipts-06: a none-sentinel receipt with an ordinary skip row still gives complete=yes class=done (mapping unchanged)" test_receipts_06_none_sentinel_skip_row_done

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
