#!/usr/bin/env bash
# Unit tests for the bump layer of change skills-desc-match
# (spdd/changes/skills-desc-match/02-bump421.feature, scenarios
# bump421-01..02): the tracked-path VERSION bump to 4.2.1 and the matching
# dated CHANGELOG.md entry layered above [4.2.0] -- a patch-grade Fixed
# entry describing exactly the description-only match narrowing.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/skills-activation-bump_test.sh. Run directly:
#   ./tests/skills-desc-match-bump_test.sh
#
# VERSION is NOT pinned as a byte-exact literal: the repo recorded lesson
# (tests/docs-bump_test.sh comments) is that a cross-change pin breaks on the
# next legitimate bump. The tests assert the [4.2.1] - 2026-09-11 section
# exists and sits above [4.2.0], and that VERSION is a semver agreeing with
# the newest (topmost) CHANGELOG entry -- which today reads exactly 4.2.1.
#
# e2e-01/e2e-02 (spdd/changes/skills-desc-match/03-e2e.feature) are the
# verifier's end-to-end QA suite (live /antz delegations, live install.sh
# --check/--all against pre-change installed copies) -- not this unit suite;
# they are not stubbed here (no sub-spec of this change asks for their
# stubs; the e2e layer owns them).
#
# Skills activated for this session: none matched (available skills --
# angular-conventions, customize-opencode, diagnose-crash, find-skills,
# init-project, omarchy -- none matches VERSION/CHANGELOG.md bookkeeping).

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner ---------------------------------------------------------

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
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
}

# ---- fixture helpers ---------------------------------------------------------

require() {
  # $1 = file, $2 = fixed string that must appear in it
  if grep -qF -- "$2" "$1"; then return 0; fi
  echo "  missing required text: $2"
  return 1
}

# This change's CHANGELOG entry: the [4.2.1] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry (4.2.0's entry also says 'minor', 'cap of
# five', ...) can never satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.2\.1\]/,/^## \[/{/^## \[4\.2\.1\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

line_421() {
  grep -nF '## [4.2.1] - 2026-09-11' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_420() {
  grep -nF '## [4.2.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}

# =============================================================================
# bump421-01: the bump is present -- VERSION is a semver agreeing with the
# newest (topmost) CHANGELOG entry (today exactly 4.2.1), CHANGELOG.md gains
# a '## [4.2.1] - 2026-09-11' section above the [4.2.0] section, and that
# section's ### Fixed entry states exactly the descmatch narrowing:
# description-field-only matching, the name/license/metadata no-matches, the
# whole-frontmatter defect with the apache false positive, the '>' / '>-'
# block-scalar continuation-line support with its termination rule, the real
# skills kept matchable, and that nothing else changed.
# =============================================================================

test_bump421_01_version_agrees_with_newest_entry() {
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

test_bump421_01_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_bump421_01_421_section_above_420() {
  ok=0
  l21="$(line_421)"
  l20="$(line_420)"
  [ -n "$l21" ] || { echo "  missing '## [4.2.1] - 2026-09-11' in CHANGELOG.md"; ok=1; }
  [ -n "$l20" ] || { echo "  missing '## [4.2.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l21" ] && [ -n "$l20" ] && [ "$l21" -ge "$l20" ]; then
    echo "  '## [4.2.1]' does not sit above '## [4.2.0]'"; ok=1
  fi
  return $ok
}

test_bump421_01_entry_is_a_fixed_entry() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '### Fixed' || ok=1
  return $ok
}

test_bump421_01_entry_states_description_only_matching() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'antz-skills.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'description:' || ok=1
  require "$CHANGELOG_ENTRY" 'field only' || ok=1
  require "$CHANGELOG_ENTRY" 'name:' || ok=1
  require "$CHANGELOG_ENTRY" 'license:' || ok=1
  require "$CHANGELOG_ENTRY" 'metadata:' || ok=1
  require "$CHANGELOG_ENTRY" 'no longer lists the skill' || ok=1
  return $ok
}

test_bump421_01_entry_states_the_previous_defect() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'ENTIRE YAML frontmatter block' || ok=1
  require "$CHANGELOG_ENTRY" 'apache' || ok=1
  require "$CHANGELOG_ENTRY" 'license: Apache-2.0' || ok=1
  return $ok
}

test_bump421_01_entry_states_block_scalar_support() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'description: >' || ok=1
  require "$CHANGELOG_ENTRY" '>-' || ok=1
  require "$CHANGELOG_ENTRY" 'indented continuation lines' || ok=1
  require "$CHANGELOG_ENTRY" 'until the next top-level key or the end of the frontmatter' || ok=1
  require "$CHANGELOG_ENTRY" 'omarchy' || ok=1
  require "$CHANGELOG_ENTRY" 'diagnose-crash' || ok=1
  return $ok
}

test_bump421_01_entry_states_nothing_else_changed() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'Skills: none matched' || ok=1
  require "$CHANGELOG_ENTRY" 'cap of five' || ok=1
  require "$CHANGELOG_ENTRY" 'tie-break' || ok=1
  require "$CHANGELOG_ENTRY" 'install.sh' || ok=1
  return $ok
}

# =============================================================================
# bump421-02: the grade is patch, stated and justified against the versioning
# table -- the snippet is aligned to already-specced behavior with no
# contract change (not minor: no new role behavior, render mechanic, or
# install mechanic; not major: nothing in the workflow or rendered command
# contract changes), and the entry records that this closes the
# "Implementation caution" recorded in spdd/specs/skills-activation.md.
# =============================================================================

test_bump421_02_entry_grades_patch_with_justification() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '**patch**' || ok=1
  require "$CHANGELOG_ENTRY" 'not minor' || ok=1
  require "$CHANGELOG_ENTRY" 'not major' || ok=1
  require "$CHANGELOG_ENTRY" 'already-specced' || ok=1
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'antz:generated' || ok=1
  require "$CHANGELOG_ENTRY" 'access model' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered command contract' || ok=1
  return $ok
}

test_bump421_02_entry_records_the_closed_caution() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'Implementation caution' || ok=1
  require "$CHANGELOG_ENTRY" 'spdd/specs/skills-activation.md' || ok=1
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "bump421-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_bump421_01_version_agrees_with_newest_entry
run_test "bump421-01: VERSION's only content is the version value with one trailing newline" test_bump421_01_version_newline_terminated_only_content
run_test "bump421-01: CHANGELOG.md carries the '## [4.2.1] - 2026-09-11' section above the [4.2.0] section" test_bump421_01_421_section_above_420
run_test "bump421-01: the [4.2.1] section carries a '### Fixed' heading" test_bump421_01_entry_is_a_fixed_entry
run_test "bump421-01: the [4.2.1] entry states the matching is keyed to each skill's description: field only -- name:/license:/metadata:-only keywords no longer list the skill" test_bump421_01_entry_states_description_only_matching
run_test "bump421-01: the [4.2.1] entry states the previous whole-frontmatter defect with the apache-via-license false positive" test_bump421_01_entry_states_the_previous_defect
run_test "bump421-01: the [4.2.1] entry states the '>' / '>-' block-scalar continuation-line support with its termination rule, keeping omarchy and diagnose-crash matchable" test_bump421_01_entry_states_block_scalar_support
run_test "bump421-01: the [4.2.1] entry states nothing else changed -- output shapes, cap of five, tie-break, prose, docs, install.sh untouched" test_bump421_01_entry_states_nothing_else_changed
run_test "bump421-02: the [4.2.1] entry grades patch with the versioning-table justification -- already-specced behavior, not minor (no new behavior/mechanic), not major (no contract change)" test_bump421_02_entry_grades_patch_with_justification
run_test "bump421-02: the [4.2.1] entry records that this closes the Implementation caution recorded in spdd/specs/skills-activation.md" test_bump421_02_entry_records_the_closed_caution

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (see 02-bump421.feature)"
[ "$fail_count" -eq 0 ]
