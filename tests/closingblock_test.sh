#!/usr/bin/env bash
# Unit tests for the closing block and the version bump of change
# orchestrator-fast-path (spdd/changes/orchestrator-fast-path/06-closingblock.feature,
# scenarios closingblock-01..07):
#
#   closingblock-01    -- every role prompt's report section requires a
#                         closing block of exactly three consecutive lines
#                         (status= / ids= / results=), a mirror only, with
#                         the disk receipt as the authority;
#   closingblock-02    -- the per-role value vocabularies (Scenario Outline,
#                         one test per row: specifier, coder, verifier,
#                         orchestrator);
#   closingblock-03    -- the coder's report names its receipt, mirrors its
#                         id lines exactly, and closes a refused session
#                         honestly (status=blocked + the BLOCKED: reason);
#   closingblock-04    -- the never-a-routing-input rule in every report
#                         section, plus the byte-identical closing-block
#                         gotcha bullet in AGENTS.md and CLAUDE.md;
#   closingblock-05    -- the specifier prompt's historical byte-for-byte pin
#                         is lifted for exactly this additive edit: the diff
#                         vs git HEAD is purely additive and carries the
#                         closing-block wording, no existing line reworded
#                         or removed;
#   closingblock-06    -- the bump is present: VERSION agrees with the
#                         newest (topmost) CHANGELOG entry, the
#                         '## [4.3.0] - 2026-09-11' section sits above
#                         [4.2.1] and describes all three improvements plus
#                         the closing-block convention, earlier entries are
#                         byte-for-byte untouched;
#   closingblock-07    -- the entry grades minor, stated and justified
#                         against the versioning table.
#
# VERSION is NOT pinned as a byte-exact literal: the repo recorded lesson
# (tests/docs-bump_test.sh comments -- its "asserted VERSION == 4.0.0" pin
# broke on the next bump) is that a cross-change pin breaks on the next
# legitimate bump. Instead the tests assert VERSION is a semver agreeing
# with the newest (topmost) CHANGELOG entry -- which today reads exactly
# 4.3.0, the value this sub-spec models -- and pin the immutable-history
# heading '## [4.3.0] - 2026-09-11' above [4.2.1].
#
# All content assertions are static greps/cmps (the duties are prompt prose
# law, not machinery); every reported test name embeds its scenario id so a
# failure maps straight back to the scenario.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/receipts_test.sh. Run directly:
#   ./tests/closingblock_test.sh
#
# Skills activated for this session: none matched (available skills --
# angular-conventions, customize-opencode, diagnose-crash, find-skills,
# init-project, omarchy -- none matches prompt-prose/docs/version
# bookkeeping).

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
VERIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/verifier.prompt"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/receipts_test.sh) ----------------------

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

# ---- report-section extracts -------------------------------------------------
# Each role's report section, extracted once so every test reads only the
# scoped text (a required phrase elsewhere in the prompt must never satisfy
# a report-section assertion).

SPECIFIER_REPORT=$(mktemp)
CODER_REPORT=$(mktemp)
VERIFIER_REPORT=$(mktemp)
ORCHESTRATOR_REPORT=$(mktemp)
extract_section "$SPECIFIER_PROMPT" 'Output, written to `spdd/changes/<change-slug>/`' "$SPECIFIER_REPORT"
extract_section "$CODER_PROMPT" "Output" "$CODER_REPORT"
extract_section "$VERIFIER_PROMPT" "Report Format" "$VERIFIER_REPORT"
extract_section "$ORCHESTRATOR_PROMPT" "Report Format" "$ORCHESTRATOR_REPORT"

# The AGENTS.md/CLAUDE.md closing-block gotcha bullet (single line each),
# extracted by its fixed prefix so a stray phrase elsewhere in the docs can
# never satisfy or trip a bullet-scoped assertion.
extract_bullet() {
  # $1 = md file, $2 = fixed bullet prefix; prints the first matching line
  grep -F -- "$2" "$1" | head -n 1
}
AGENTS_CLOSING=$(mktemp)
CLAUDE_CLOSING=$(mktemp)
printf '%s\n' "$(extract_bullet "$AGENTS_MD" '- Closing block')" > "$AGENTS_CLOSING"
printf '%s\n' "$(extract_bullet "$CLAUDE_MD" '- Closing block')" > "$CLAUDE_CLOSING"

# This change's CHANGELOG entry: the [4.3.0] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry can never satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.3\.0\]/,/^## \[/{/^## \[4\.3\.0\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# =============================================================================
# closingblock-01: every role prompt's report section requires the report to
# end with a closing block of exactly three consecutive lines -- "status=",
# "ids=", "results=" -- grep-able, short, deterministic; and states the block
# is a mirror only, with the disk receipt as the authority wherever both
# exist.
# =============================================================================

check_closing_block_grammar() {
  # $1 = a role's extracted report section
  ok=0
  require "$1" 'closing block' || ok=1
  require "$1" 'three consecutive lines' || ok=1
  require "$1" '`status=<value>`' || ok=1
  require "$1" '`ids=<id,id,...>`' || ok=1
  require "$1" '`results=<value>`' || ok=1
  require "$1" 'grep-able' || ok=1
  # Mirror only + receipt authority, wherever both exist.
  require "$1" 'mirror only' || ok=1
  require "$1" 'no routing, count, or decision ever derives from it' || ok=1
  require "$1" 'the receipt is the authority' || ok=1
  return $ok
}

test_closingblock_01_specifier_report_requires_block() {
  check_closing_block_grammar "$SPECIFIER_REPORT"
}

test_closingblock_01_coder_report_requires_block() {
  check_closing_block_grammar "$CODER_REPORT"
}

test_closingblock_01_verifier_report_requires_block() {
  check_closing_block_grammar "$VERIFIER_REPORT"
}

test_closingblock_01_orchestrator_report_requires_block() {
  check_closing_block_grammar "$ORCHESTRATOR_REPORT"
}

# =============================================================================
# closingblock-02 (Scenario Outline, one test per row): each role's closing
# block fills the three lines per its pinned vocabulary, mirroring disk state.
# =============================================================================

test_closingblock_02_specifier_vocabulary() {
  # specifier | spec_complete | the declared ids of the sub-specs it wrote | none
  ok=0
  require "$SPECIFIER_REPORT" 'status=spec_complete' || ok=1
  require "$SPECIFIER_REPORT" 'the declared ids of the sub-specs you wrote' || ok=1
  require "$SPECIFIER_REPORT" 'results=none' || ok=1
  return $ok
}

test_closingblock_02_coder_vocabulary() {
  # coder | done, blocked | its sub-spec's declared ids | comma-joined
  # "id=<id> result=<green|skip|blocked>" tokens mirroring its receipt, in
  # receipt order
  ok=0
  require "$CODER_REPORT" '`done`' || ok=1
  require "$CODER_REPORT" '`blocked`' || ok=1
  require "$CODER_REPORT" "your sub-spec's declared ids" || ok=1
  require "$CODER_REPORT" 'id=<id> result=<green|skip|blocked>' || ok=1
  require "$CODER_REPORT" 'mirroring your receipt' || ok=1
  require "$CODER_REPORT" 'in receipt order' || ok=1
  return $ok
}

test_closingblock_02_verifier_vocabulary() {
  # verifier | approved, rejected (approved-with-warnings folds to approved;
  # the prose verdict stays authoritative) | the change's declared ids |
  # comma-joined tokens from the receipts as found on disk at verification end
  ok=0
  require "$VERIFIER_REPORT" '`approved`' || ok=1
  require "$VERIFIER_REPORT" '`rejected`' || ok=1
  require "$VERIFIER_REPORT" 'approved-with-warnings folds to `approved`' || ok=1
  require "$VERIFIER_REPORT" 'the prose verdict stays authoritative' || ok=1
  require "$VERIFIER_REPORT" "the change's declared ids" || ok=1
  require "$VERIFIER_REPORT" 'id=<id> result=<green|skip|blocked>' || ok=1
  require "$VERIFIER_REPORT" 'as found on disk at verification end' || ok=1
  return $ok
}

test_closingblock_02_orchestrator_vocabulary() {
  # orchestrator | delegated-specifier, delegated-coder, delegated-verifier,
  # stopped, released, waiting-user | the ids from the probe |
  # comma-joined "<subspec-file>=<done|blocked|in_progress>" per sub-spec,
  # from the probe's class fields
  ok=0
  require "$ORCHESTRATOR_REPORT" 'delegated-specifier' || ok=1
  require "$ORCHESTRATOR_REPORT" 'delegated-coder' || ok=1
  require "$ORCHESTRATOR_REPORT" 'delegated-verifier' || ok=1
  require "$ORCHESTRATOR_REPORT" 'stopped' || ok=1
  require "$ORCHESTRATOR_REPORT" 'released' || ok=1
  require "$ORCHESTRATOR_REPORT" 'waiting-user' || ok=1
  require "$ORCHESTRATOR_REPORT" 'the ids from the probe' || ok=1
  require "$ORCHESTRATOR_REPORT" '<subspec-file>=<done|blocked|in_progress>' || ok=1
  require "$ORCHESTRATOR_REPORT" "the probe's class fields" || ok=1
  return $ok
}

# =============================================================================
# closingblock-03: the coder's report body names the receipt file it wrote or
# updated; its results= tokens match that receipt's id lines exactly (the
# receipt is the authority; a deviation is a bug, absorbed by the bounded
# REJECTED.md retry); a session that refused before touching the sub-spec
# still closes honestly (status=blocked with the BLOCKED: reason in prose).
# =============================================================================

test_closingblock_03_coder_names_receipt_and_mirrors_exactly() {
  ok=0
  require "$CODER_REPORT" 'receipt file you wrote or updated' || ok=1
  require "$CODER_REPORT" 'match' || ok=1
  require "$CODER_REPORT" 'exactly' || ok=1
  require "$CODER_REPORT" 'the disk receipt is the authority' || ok=1
  require "$CODER_REPORT" 'REJECTED.md' || ok=1
  return $ok
}

test_closingblock_03_refused_session_closes_honestly() {
  ok=0
  require "$CODER_REPORT" 'status=blocked' || ok=1
  require "$CODER_REPORT" 'BLOCKED:' || ok=1
  require "$CODER_REPORT" 'closes honestly' || ok=1
  return $ok
}

# =============================================================================
# closingblock-04: the block is a mirror only -- enforced in prose and docs.
# Every role's report section states the block is never an input to any
# routing state or count (extending prompts-06's skills-line rule);
# AGENTS.md and CLAUDE.md state the closing-block convention identically
# (byte-identical bullet).
# =============================================================================

test_closingblock_04_never_a_routing_input_in_every_report_section() {
  ok=0
  for section in "$SPECIFIER_REPORT" "$CODER_REPORT" "$VERIFIER_REPORT" "$ORCHESTRATOR_REPORT"; do
    require "$section" 'never an input to any routing state or count' || ok=1
  done
  return $ok
}

test_closingblock_04_docs_bullet_present_and_identical() {
  ok=0
  [ -s "$AGENTS_CLOSING" ] || { echo "  AGENTS.md has no closing-block gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_CLOSING" ] || { echo "  CLAUDE.md has no closing-block gotcha bullet"; ok=1; }
  for bullet in "$AGENTS_CLOSING" "$CLAUDE_CLOSING"; do
    require "$bullet" 'closing block' || ok=1
    require "$bullet" 'three consecutive lines' || ok=1
    require "$bullet" 'mirror only' || ok=1
    require "$bullet" 'the receipt is the authority' || ok=1
    require "$bullet" 'never an input to any routing state or count' || ok=1
  done
  cmp -s "$AGENTS_CLOSING" "$CLAUDE_CLOSING" \
    || { echo "  closing-block bullet differs between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

# =============================================================================
# closingblock-05: the specifier prompt's historical byte-for-byte pin
# (tests/skills-activation-prompts_test.sh prompts-05) is lifted for exactly
# this additive edit: the diff vs git HEAD is purely additive and the added
# lines carry the closing-block requirement; no existing line is reworded or
# removed (every pre-change line survives verbatim).
# =============================================================================

test_closingblock_05_specifier_diff_purely_additive_closing_block_only() {
  ok=0
  DIFF_FILE=$(mktemp)
  git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/specifier.prompt > "$DIFF_FILE"
  if [ ! -s "$DIFF_FILE" ]; then
    echo "  specifier.prompt has no diff vs HEAD (the closing-block edit is missing)"
    ok=1
  else
    # Purely additive: no removed content lines (a removed content line
    # starts with '-' followed by a non-'-' character; '^---' headers
    # excluded).
    if [ -n "$(grep -E '^-[^-]' "$DIFF_FILE")" ]; then
      echo "  specifier.prompt has removed lines (the edit must be purely additive)"
      ok=1
    fi
    # Every added content line carries the closing-block requirement (the
    # edit is exactly that requirement, nothing else).
    added=$(grep -E '^\+[^+]' "$DIFF_FILE")
    if [ -z "$added" ]; then
      echo "  specifier.prompt diff has no added content lines"
      ok=1
    elif printf '%s\n' "$added" | grep -qv 'closing block'; then
      echo "  specifier.prompt has an added line that is not the closing-block requirement:"
      printf '%s\n' "$added" | grep -v 'closing block'
      ok=1
    fi
  fi
  rm -f "$DIFF_FILE"
  return $ok
}

test_closingblock_05_specifier_no_existing_line_reworded_or_removed() {
  ok=0
  HEAD_SPECIFIER=$(mktemp)
  if ! git -C "$SCRIPT_DIR" show HEAD:agents/prompts/specifier.prompt > "$HEAD_SPECIFIER" 2>/dev/null; then
    echo "  cannot read HEAD:agents/prompts/specifier.prompt (is the change already committed?)"
    rm -f "$HEAD_SPECIFIER"
    return 1
  fi
  while IFS= read -r line; do
    if ! grep -qxF -- "$line" "$SPECIFIER_PROMPT"; then
      echo "  pre-change specifier prompt line no longer present verbatim: $line"
      ok=1
    fi
  done < "$HEAD_SPECIFIER"
  rm -f "$HEAD_SPECIFIER"
  return $ok
}

# =============================================================================
# closingblock-06: the bump is present -- VERSION is a semver agreeing with
# the newest (topmost) CHANGELOG entry (today exactly 4.3.0, the value this
# sub-spec models), the CHANGELOG.md carries a '## [4.3.0] - 2026-09-11'
# section above the [4.2.1] section describing all three improvements plus
# the closing-block convention, and every earlier entry is byte-for-byte
# untouched.
# =============================================================================

test_closingblock_06_version_agrees_with_newest_entry() {
  ok=0
  version=$(cat "$VERSION_FILE")
  printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "  VERSION reads '$version', not a semver (X.Y.Z)"; ok=1; }
  newest=$(sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$CHANGELOG_MD" | head -n 1)
  if [ -z "$newest" ]; then
    echo "  CHANGELOG.md has no '## [...]' entry headings"; ok=1
  elif [ "$version" != "$newest" ]; then
    echo "  VERSION reads '$version' but the newest CHANGELOG entry is '$newest'"
    ok=1
  fi
  return $ok
}

test_closingblock_06_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_closingblock_06_430_section_above_421() {
  ok=0
  l30=$(grep -nF '## [4.3.0] - 2026-09-11' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1)
  l21=$(grep -nF '## [4.2.1]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1)
  [ -n "$l30" ] || { echo "  missing '## [4.3.0] - 2026-09-11' in CHANGELOG.md"; ok=1; }
  [ -n "$l21" ] || { echo "  missing '## [4.2.1]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l30" ] && [ -n "$l21" ] && [ "$l30" -ge "$l21" ]; then
    echo "  '## [4.3.0]' does not sit above '## [4.2.1]'"; ok=1
  fi
  return $ok
}

test_closingblock_06_entry_describes_change_1_script_extraction() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.3.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'scripts/orchestration/' || ok=1
  require "$CHANGELOG_ENTRY" 'install.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'no behavior change' || ok=1
  return $ok
}

test_closingblock_06_entry_describes_change_2_session_guards() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.3.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'dedup' || ok=1
  require "$CHANGELOG_ENTRY" 'latch' || ok=1
  return $ok
}

test_closingblock_06_entry_describes_change_3_receipts() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.3.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'receipt' || ok=1
  require "$CHANGELOG_ENTRY" 'test_command=' || ok=1
  require "$CHANGELOG_ENTRY" 'classification' || ok=1
  require "$CHANGELOG_ENTRY" 'doubtful' || ok=1
  return $ok
}

test_closingblock_06_entry_describes_closing_block() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.3.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'closing block' || ok=1
  require "$CHANGELOG_ENTRY" 'mirror' || ok=1
  return $ok
}

test_closingblock_06_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [4.2.1] - 2026-09-11' || ok=1
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[4\.2\.1\]/,$p' > "$CHANGELOG_ENTRY.head"
    sed -n '/^## \[4\.2\.1\]/,$p' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY.work"
    cmp -s "$CHANGELOG_ENTRY.head" "$CHANGELOG_ENTRY.work" \
      || { echo "  CHANGELOG.md's entries from [4.2.1] down differ from git HEAD's (earlier entries are immutable history)"; ok=1; }
    rm -f "$CHANGELOG_ENTRY.head" "$CHANGELOG_ENTRY.work"
  fi
  return $ok
}

# =============================================================================
# closingblock-07: the grade is minor, stated and justified against the
# versioning table (most severe component wins): change 1 alters install.sh's
# rendered agent bodies (a behavior change to the render = minor); change 3
# changes role behavior; not patch (not wording-only) and not major (the
# workflow contract, the antz:generated marker format, the access model, the
# directory layout, and the install locations are all unchanged -- the
# receipt file is additive inside the existing change directory).
# =============================================================================

test_closingblock_07_entry_grades_minor_with_justification() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.3.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'minor' || ok=1
  require "$CHANGELOG_ENTRY" 'not patch' || ok=1
  require "$CHANGELOG_ENTRY" 'not major' || ok=1
  require "$CHANGELOG_ENTRY" 'behavior change' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered agent bodies' || ok=1
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'marker format' || ok=1
  require "$CHANGELOG_ENTRY" 'access model' || ok=1
  require "$CHANGELOG_ENTRY" 'directory layout' || ok=1
  require "$CHANGELOG_ENTRY" 'install location' || ok=1
  require "$CHANGELOG_ENTRY" 'additive' || ok=1
  return $ok
}

# =============================================================================
# Invariant (06-closingblock): agents/meta/* stay byte-for-byte unchanged.
# =============================================================================

test_meta_files_byte_unchanged() {
  ok=0
  for f in agents/meta/*.yaml; do
    head_copy=$(mktemp)
    if ! git -C "$SCRIPT_DIR" show "HEAD:$f" > "$head_copy" 2>/dev/null; then
      echo "  cannot read HEAD copy of $f (is the change already committed?)"; ok=1
    elif ! cmp -s "$head_copy" "$SCRIPT_DIR/$f"; then
      echo "  agents/meta/$f differs from git HEAD (must be byte-for-byte unchanged)"; ok=1
    fi
    rm -f "$head_copy"
  done
  return $ok
}

# ---- run everything -----------------------------------------------------------

run_test "closingblock-01: the specifier prompt's report section requires the three-line closing block, a mirror only, with the receipt as authority" test_closingblock_01_specifier_report_requires_block
run_test "closingblock-01: the coder prompt's report section requires the three-line closing block, a mirror only, with the receipt as authority" test_closingblock_01_coder_report_requires_block
run_test "closingblock-01: the verifier prompt's report section requires the three-line closing block, a mirror only, with the receipt as authority" test_closingblock_01_verifier_report_requires_block
run_test "closingblock-01: the orchestrator prompt's report section requires the three-line closing block, a mirror only, with the receipt as authority" test_closingblock_01_orchestrator_report_requires_block
run_test "closingblock-02 (specifier row): status=spec_complete, the declared ids of the sub-specs it wrote, results=none" test_closingblock_02_specifier_vocabulary
run_test "closingblock-02 (coder row): status done|blocked, its sub-spec's declared ids, id=<id> result=<green|skip|blocked> tokens mirroring its receipt in receipt order" test_closingblock_02_coder_vocabulary
run_test "closingblock-02 (verifier row): status approved|rejected (approved-with-warnings folds to approved, prose verdict authoritative), the change's ids, tokens from the receipts as found on disk at verification end" test_closingblock_02_verifier_vocabulary
run_test "closingblock-02 (orchestrator row): the six flow statuses, the probe's ids, <subspec-file>=<done|blocked|in_progress> from the probe's class fields" test_closingblock_02_orchestrator_vocabulary
run_test "closingblock-03: the coder's report names its receipt file and its results= tokens match the receipt's id lines exactly (receipt is the authority, deviation absorbed by the bounded REJECTED.md retry)" test_closingblock_03_coder_names_receipt_and_mirrors_exactly
run_test "closingblock-03: a coder session that refused before touching the sub-spec still closes honestly -- status=blocked with the BLOCKED: reason in the report prose" test_closingblock_03_refused_session_closes_honestly
run_test "closingblock-04: every role's report section states the block is never an input to any routing state or count" test_closingblock_04_never_a_routing_input_in_every_report_section
run_test "closingblock-04: AGENTS.md and CLAUDE.md carry the closing-block convention byte-identically" test_closingblock_04_docs_bullet_present_and_identical
run_test "closingblock-05: the specifier prompt's diff vs HEAD is purely additive and every added line carries the closing-block requirement" test_closingblock_05_specifier_diff_purely_additive_closing_block_only
run_test "closingblock-05: no existing specifier prompt line is reworded or removed (every pre-change line survives verbatim)" test_closingblock_05_specifier_no_existing_line_reworded_or_removed
run_test "closingblock-06: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_closingblock_06_version_agrees_with_newest_entry
run_test "closingblock-06: VERSION's only content is the version value with one trailing newline" test_closingblock_06_version_newline_terminated_only_content
run_test "closingblock-06: CHANGELOG.md carries the '## [4.3.0] - 2026-09-11' section above the [4.2.1] section" test_closingblock_06_430_section_above_421
run_test "closingblock-06: the [4.3.0] entry describes change 1 -- the orchestrator scripts extracted to scripts/orchestration/ with install.sh injecting them into the rendered antz-orchestrator body (no behavior change)" test_closingblock_06_entry_describes_change_1_script_extraction
run_test "closingblock-06: the [4.3.0] entry describes change 2 -- the session guards (dedup and the post-stop latch)" test_closingblock_06_entry_describes_change_2_session_guards
run_test "closingblock-06: the [4.3.0] entry describes change 3 -- the coder-written result receipts with the orchestrator's file-reading classification and the doubtful-receipt suite exception" test_closingblock_06_entry_describes_change_3_receipts
run_test "closingblock-06: the [4.3.0] entry describes the closing-block convention (a mirror only)" test_closingblock_06_entry_describes_closing_block
run_test "closingblock-06: every CHANGELOG entry other than this change's own (the [4.2.1]-down tail) is byte-untouched versus git HEAD" test_closingblock_06_earlier_entries_byte_untouched
run_test "closingblock-07: the [4.3.0] entry grades minor with the versioning-table justification -- not patch (not wording-only), not major (contract/marker format/access model/directory layout/install locations unchanged, the receipt file additive)" test_closingblock_07_entry_grades_minor_with_justification
run_test "invariant: agents/meta/* are byte-for-byte unchanged versus git HEAD" test_meta_files_byte_unchanged

# ---- e2e-only scenario: explicit SKIP stub -----------------------------------
# e2e-05 (spdd/changes/orchestrator-fast-path/07-e2e.feature) is the change's
# verifier-owned end-to-end QA suite: it reads VERSION/CHANGELOG.md at the
# user surface and drives ./install.sh --check/--all against pre-change
# (4.2.1) installed copies -- live install / drift-report semantics on the
# user's real machine, not this unit suite (whose bump assertions here are
# content-level, closingblock-06/07). Explicit stub so the scenario id is
# accounted for (suite convention: see tests/versioning-rule_test.sh).
skip_test "e2e-05: against pre-change 4.2.1 installed copies, --check reports the drift to 4.3.0 for both clients and prints the [4.3.0] entry, --all restamps every installed file, and a fresh --check reports already up to date (antz 4.3.0)" \
  "e2e-only: live install / drift-report semantics, run by the verifier (07-e2e.feature)"

rm -f "$SPECIFIER_REPORT" "$CODER_REPORT" "$VERIFIER_REPORT" "$ORCHESTRATOR_REPORT" \
  "$AGENTS_CLOSING" "$CLAUDE_CLOSING" "$CHANGELOG_ENTRY"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 07-e2e.feature)"
[ "$fail_count" -eq 0 ]
