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
#                         or removed (retired by gating, loudly, once the
#                         working copy differs from HEAD -- precision-gaps
#                         conventions-04; the degenerate no-diff state check
#                         stays);
#   closingblock-06    -- the bump is present: VERSION agrees with the
#                         newest (topmost) CHANGELOG entry, the
#                         '## [4.3.0] - 2026-09-11' section sits above
#                         [4.2.1] and describes all three improvements plus
#                         the closing-block convention, earlier entries are
#                         byte-for-byte untouched;
#   closingblock-07    -- the entry grades minor, stated and justified
#                         against the versioning table.
#
# Amended by change style-rewrite (sub-spec 02-coder): the coder's report
# duty (the receipt-naming bullet + the closing-block bullet) folds out of
# the "## Output" orphan list into "## Receipt"; the closing-block bullet
# becomes a short list; the mirror clause is stated exactly once in the
# prompt, in the folded list. The coder's report-section extract anchor
# moves from "Output" to "Receipt" (the closingblock-01..04 coder checks keep
# the same required strings). New scenarios coder-01..04
# (spdd/changes/style-rewrite/02-coder.feature) are tested below, each
# reported test name embedding its scenario id.
#
# Amended again by style-rewrite sub-spec 06-terminology (terminology-01):
# the specifier's Output heading re-keys `<change-slug>` -> `<slug>`, so the
# specifier report-section extract anchor re-keys on the new heading text
# (the closingblock-01/02/04 specifier checks keep the same required strings).
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
# a report-section assertion). The coder's report-closing duty lives in its
# "## Receipt" section since the style-rewrite 02 orphan fold (it used to be
# keyed on "Output").

SPECIFIER_REPORT=$(mktemp)
CODER_REPORT=$(mktemp)
VERIFIER_REPORT=$(mktemp)
ORCHESTRATOR_REPORT=$(mktemp)
extract_section "$SPECIFIER_PROMPT" 'Output, written to `spdd/changes/<slug>/`' "$SPECIFIER_REPORT"
extract_section "$CODER_PROMPT" "Receipt" "$CODER_REPORT"
extract_section "$VERIFIER_PROMPT" "Report Format" "$VERIFIER_REPORT"
extract_section "$ORCHESTRATOR_PROMPT" "Report Format" "$ORCHESTRATOR_REPORT"

# style-rewrite sub-spec 02 extracts (the coder's report duty moved under
# "## Receipt"): the Receipt section as it stands, and inside it the folded
# closing-block list -- from its intro bullet to (excluding) the section's
# final bullet. Keyed on the Receipt section, not the prompt at large, so the
# pre-fold orphan bullet can never satisfy these checks.
CODER_RECEIPT_SEC=$(mktemp)
CODER_CLOSING_REGION=$(mktemp)
extract_section "$CODER_PROMPT" "Receipt" "$CODER_RECEIPT_SEC"
awk '/^- End your report with a closing block/ {flag=1; print; next}
     flag && /^- / {flag=0}
     flag {print}' "$CODER_RECEIPT_SEC" > "$CODER_CLOSING_REGION"

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
# closingblock-05: the specifier prompt's diff-vs-HEAD assertions -- originally
# lifted from byte-for-byte to "purely additive, closing-block only" for the
# closing-block edit, and now retired by gating, loudly (precision-gaps
# 01-conventions.feature, conventions-04): the conventions-01..03 specifier
# rewordings legitimately remove and re-add lines, so once the working copy
# differs from HEAD each assertion prints a loud retirement note and skips its
# diff-window checks (both stay registered); the degenerate no-diff state
# check (the closing-block bullet must be present when the copy equals HEAD)
# stays enforced.
# =============================================================================

test_closingblock_05_specifier_diff_purely_additive_closing_block_only() {
  ok=0
  DIFF_FILE=$(mktemp)
  git -C "$SCRIPT_DIR" diff HEAD -- agents/prompts/specifier.prompt > "$DIFF_FILE"
  if [ ! -s "$DIFF_FILE" ]; then
    # Time-robustness (the 94938da lesson), kept: with no diff window this
    # assertion degrades to a state check -- the closing-block bullet must be
    # present in the current prompt.
    if ! grep -q 'closing block' "$SCRIPT_DIR/agents/prompts/specifier.prompt"; then
      echo "  specifier.prompt has no diff vs HEAD and carries no closing-block bullet"
      ok=1
    fi
  else
    # conventions-04 gating: the working copy differs from HEAD (the
    # precision-gaps rewordings remove and re-add lines -- a legitimate edit
    # this pin cannot distinguish), so the additive-shape diff-window checks
    # retire with this loud note.
    echo "  note: specifier.prompt differs from HEAD (the precision-gaps conventions-01..03 rewordings remove and re-add lines legitimately); the purely-additive/closing-block-only diff-window checks are retired by gating"
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
  if ! cmp -s "$HEAD_SPECIFIER" "$SPECIFIER_PROMPT"; then
    # conventions-04 gating: same retirement as the diff-window sibling.
    echo "  note: specifier.prompt differs from HEAD (the precision-gaps conventions-01..03 rewordings remove and re-add lines legitimately); the verbatim-survival diff-window check is retired by gating"
    rm -f "$HEAD_SPECIFIER"
    return 0
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

# =============================================================================
# style-rewrite sub-spec 02 (spdd/changes/style-rewrite/02-coder.feature):
# coder-01 the orphan fold + short list; coder-02 the reworded final
# statement; coder-03 the mirror clause exactly once, in the folded list;
# coder-04 the suites follow the fold (anchor moved, receipts suite intact).
# =============================================================================

check_short_list_region() {
  # $1 = file: no line has parentheses nested deeper than one level, and no
  # line carries unbalanced parens (each parenthetical lives on one line).
  awk '
    {
      d = 0; m = 0; n = split($0, ch, "")
      for (i = 1; i <= n; i++) {
        if (ch[i] == "(") { d++; if (d > m) m = d }
        else if (ch[i] == ")") { d--; if (d < 0) m = 99 }
      }
      if (m > 1 || d != 0) { print "  parens deeper than one level (or unbalanced): " $0; bad = 1 }
    }
    END { exit bad ? 1 : 0 }
  ' "$1"
}

test_coder_01_orphan_bullets_fold_into_receipt_as_short_list() {
  ok=0
  # "## Output" keeps exactly the two surviving bullets: the files-changed
  # bullet and the skills bullet -- the blank-line orphan gap is gone (no
  # further non-blank content in the section).
  OUT_SEC=$(mktemp)
  extract_section "$CODER_PROMPT" "Output" "$OUT_SEC"
  bullets=$(grep -c '^- ' "$OUT_SEC")
  nonblank=$(grep -c '[^[:space:]]' "$OUT_SEC")
  if [ "$bullets" -ne 2 ] || [ "$nonblank" -ne 2 ]; then
    echo "  ## Output holds $bullets bullets / $nonblank non-blank lines, expected exactly 2/2 (the orphan fold left residue or took a survivor)"
    ok=1
  fi
  require "$OUT_SEC" 'Files changed' || ok=1
  require "$OUT_SEC" 'skills were activated' || ok=1
  rm -f "$OUT_SEC"
  # The receipt-naming bullet moved under "## Receipt", content kept (it
  # names the receipt the report must cite, because the receipt is the
  # classification authority on disk).
  require "$CODER_RECEIPT_SEC" 'Name the receipt file you wrote or updated' || ok=1
  require "$CODER_RECEIPT_SEC" 'receipt file you wrote or updated (see `## Receipt`) in this report body' || ok=1
  require "$CODER_RECEIPT_SEC" 'the receipt must be named explicitly so the reader can find the classification authority on disk' || ok=1
  # The closing-block bullet is now a short list under "## Receipt": an intro
  # plus at least one item per closing-block line and the match rule. The
  # intro bullet itself stays short (the 100-130-word sentence is gone).
  if [ ! -s "$CODER_CLOSING_REGION" ]; then
    echo "  the closing-block list does not live under \"## Receipt\""
    ok=1
  else
    items=$(grep -c '^  - ' "$CODER_CLOSING_REGION")
    if [ "$items" -lt 4 ]; then
      echo "  the closing-block region holds $items list items, expected at least 4 (one per line + the match rule)"
      ok=1
    fi
    intro_words=$(head -n 1 "$CODER_CLOSING_REGION" | wc -w)
    if [ "$intro_words" -ge 40 ]; then
      echo "  the closing-block intro is still a $intro_words-word sentence, expected a short lead line"
      ok=1
    fi
    # Every pinned string survives, each on a single line of the region.
    require "$CODER_CLOSING_REGION" 'closing block' || ok=1
    require "$CODER_CLOSING_REGION" 'three consecutive lines' || ok=1
    require "$CODER_CLOSING_REGION" '`status=<value>`' || ok=1
    require "$CODER_CLOSING_REGION" '`ids=<id,id,...>`' || ok=1
    require "$CODER_CLOSING_REGION" '`results=<value>`' || ok=1
    require "$CODER_CLOSING_REGION" 'grep-able' || ok=1
    require "$CODER_CLOSING_REGION" '`done`' || ok=1
    require "$CODER_CLOSING_REGION" '`blocked`' || ok=1
    require "$CODER_CLOSING_REGION" "your sub-spec's declared ids" || ok=1
    require "$CODER_CLOSING_REGION" 'id=<id> result=<green|skip|blocked>' || ok=1
    require "$CODER_CLOSING_REGION" 'mirroring your receipt' || ok=1
    require "$CODER_CLOSING_REGION" 'in receipt order' || ok=1
    require "$CODER_CLOSING_REGION" 'match' || ok=1
    require "$CODER_CLOSING_REGION" 'exactly' || ok=1
    require "$CODER_CLOSING_REGION" 'the disk receipt is the authority' || ok=1
    require "$CODER_CLOSING_REGION" 'REJECTED.md' || ok=1
    require "$CODER_CLOSING_REGION" 'status=blocked' || ok=1
    require "$CODER_CLOSING_REGION" 'BLOCKED:' || ok=1
    require "$CODER_CLOSING_REGION" 'closes honestly' || ok=1
    # The full duty still reads out of the list: exact match of the results=
    # tokens against the receipt's id lines, the deviation-is-a-bug rule with
    # the bounded REJECTED.md retry, and the honest refused-session close.
    require "$CODER_CLOSING_REGION" 'deviation between the block and the receipt is a bug' || ok=1
    require "$CODER_CLOSING_REGION" 'bounded' || ok=1
    require "$CODER_CLOSING_REGION" 'refused before touching the sub-spec still closes honestly' || ok=1
    require "$CODER_CLOSING_REGION" 'reason in the report prose' || ok=1
    # No item carries parentheses nested deeper than one level.
    check_short_list_region "$CODER_CLOSING_REGION" || ok=1
  fi
  return $ok
}

test_coder_03_mirror_clause_stated_exactly_once_in_the_folded_list() {
  ok=0
  for s in 'The block is a mirror only' \
           'no routing, count, or decision ever derives from it' \
           'the receipt is the authority'; do
    n=$(grep -oF -- "$s" "$CODER_PROMPT" | wc -l)
    if [ "$n" -ne 1 ]; then
      echo "  '$s' occurs $n times in coder.prompt, expected exactly 1"
      ok=1
    fi
    require "$CODER_CLOSING_REGION" "$s" || ok=1
  done
  return $ok
}

test_coder_02_receipt_closing_statement_keeps_authority_drops_restatement() {
  ok=0
  # The "## Receipt" section's final bullet still states the
  # classification-authority duty...
  LAST_BULLET=$(mktemp)
  lastln=$(grep -n '^- ' "$CODER_RECEIPT_SEC" | tail -n 1 | cut -d: -f1)
  [ -n "$lastln" ] && sed -n "${lastln},\$p" "$CODER_RECEIPT_SEC" > "$LAST_BULLET"
  require "$LAST_BULLET" 'The disk receipt is the classification authority' || ok=1
  require "$LAST_BULLET" 'classifies sub-specs by reading receipts instead of running the unit' || ok=1
  # ...and the mirror clause's variant restatements are gone from the whole
  # prompt (the folded list states the clause once; this bullet no longer
  # restates it in other words).
  refuse "$CODER_PROMPT" 'mirrors the receipt only' || ok=1
  refuse "$CODER_PROMPT" 'the receipt is what routes' || ok=1
  rm -f "$LAST_BULLET"
  return $ok
}

test_coder_04_closingblock_anchor_follows_fold_receipts_suite_untouched() {
  ok=0
  SUITE="$SCRIPT_DIR/tests/closingblock_test.sh"
  # The coder's report-section extract is keyed on the "Receipt" heading now,
  # so the closingblock-01..04 coder checks read the folded list.
  grep -qF "extract_section \"\$CODER_PROMPT\" \"Receipt\" \"\$CODER_REPORT\"" "$SUITE" \
    || { echo "  closingblock_test.sh still keys the coder's report extract on \"Output\""; ok=1; }
  HEAD_SUITE=$(mktemp)
  if ! git -C "$SCRIPT_DIR" show HEAD:tests/closingblock_test.sh > "$HEAD_SUITE" 2>/dev/null; then
    echo "  cannot read HEAD:tests/closingblock_test.sh"; rm -f "$HEAD_SUITE"; return 1
  fi
  # The verifier and orchestrator extract lines are unchanged, and the coder
  # checks keep the same required strings as before (new scope, same pins) --
  # both verified against HEAD's copy of the suite. The SPECIFIER extract
  # line is the exception style-rewrite terminology-01 re-keys (its heading
  # text moves `<change-slug>` -> `<slug>`): a window born gated on the
  # change_pending pattern -- enforced while this suite differs from HEAD AND
  # HEAD's SPECIFIER extract line still reads `<change-slug>`, requiring the
  # working line to equal HEAD's with exactly the placeholder rewrite
  # applied; retired with a loud note once HEAD carries the rewrite (the
  # closingblock-01/02/04 specifier content checks, reading the re-keyed
  # section, stay enforced in every state).
  for role in VERIFIER ORCHESTRATOR; do
    a=$(grep -F "extract_section \"\$${role}_PROMPT\"" "$HEAD_SUITE")
    b=$(grep -F "extract_section \"\$${role}_PROMPT\"" "$SUITE")
    [ "$a" = "$b" ] || { echo "  the $role extract line changed (must stay unchanged)"; ok=1; }
  done
  sa=$(grep '^extract_section "\$SPECIFIER_PROMPT"' "$HEAD_SUITE")
  sb=$(grep '^extract_section "\$SPECIFIER_PROMPT"' "$SUITE")
  if ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- tests/closingblock_test.sh 2>/dev/null \
       && printf '%s\n' "$sa" | grep -qF 'change-slug'; then
    if [ "$sb" != "$(printf '%s\n' "$sa" | sed -e 's|<change-slug>|<slug>|g')" ]; then
      echo "  the SPECIFIER extract line changed beyond the <change-slug> -> <slug> re-key"
      ok=1
    fi
  else
    echo "  note: the specifier-heading re-key is committed vs HEAD (or HEAD's extract line no longer reads \`<change-slug>\`); the SPECIFIER extract-line window is vacuously retired, the content checks stay enforced"
  fi
  pat="require \"\$CODER_REPORT\""
  ca=$(grep -F "$pat" "$HEAD_SUITE")
  cb=$(grep -F "$pat" "$SUITE")
  [ "$ca" = "$cb" ] \
    || { echo "  the coder checks' required strings differ from HEAD's (same strings, moved scope only)"; ok=1; }
  rm -f "$HEAD_SUITE"
  # tests/receipts_test.sh passes unmodified: byte-identical to HEAD's copy...
  git -C "$SCRIPT_DIR" diff --quiet HEAD -- tests/receipts_test.sh \
    || { echo "  tests/receipts_test.sh was modified (this sub-spec verified it no-break)"; ok=1; }
  # ...and exits 0 against the folded prompt (both suites exit 0: this very
  # run is the closingblock half, the nested run the receipts half).
  sh "$SCRIPT_DIR/tests/receipts_test.sh" > /dev/null 2>&1 \
    || { echo "  tests/receipts_test.sh exits non-zero against the folded prompt"; ok=1; }
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
run_test "coder-01: the two orphan bullets fold into ## Receipt -- ## Output keeps exactly the two surviving bullets, the receipt-naming bullet keeps its content, and the closing-block bullet becomes a short list carrying every pinned string" test_coder_01_orphan_bullets_fold_into_receipt_as_short_list
run_test "coder-02: the ## Receipt final bullet still states the classification-authority duty, and the mirror clause's variant restatements are gone from the whole prompt" test_coder_02_receipt_closing_statement_keeps_authority_drops_restatement
run_test "coder-03: the mirror clause strings each occur exactly once in coder.prompt and the single occurrence lives in the folded closing-block list under ## Receipt" test_coder_03_mirror_clause_stated_exactly_once_in_the_folded_list
run_test "coder-04: closingblock_test.sh keys the coder's report extract on Receipt with the same required strings and the other three extracts unchanged, and tests/receipts_test.sh passes unmodified (both suites exit 0)" test_coder_04_closingblock_anchor_follows_fold_receipts_suite_untouched
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
  "$AGENTS_CLOSING" "$CLAUDE_CLOSING" "$CHANGELOG_ENTRY" \
  "$CODER_RECEIPT_SEC" "$CODER_CLOSING_REGION"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 07-e2e.feature)"
[ "$fail_count" -eq 0 ]
