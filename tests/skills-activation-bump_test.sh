#!/usr/bin/env bash
# Unit tests for the bump layer of change skills-activation
# (spdd/changes/skills-activation/05-bump.feature, scenarios bump-01..02):
# the tracked-path VERSION bump to 4.2.0 and the matching dated
# CHANGELOG.md entry layered above [4.1.0], keeping a Changelog format,
# describing exactly what this change shipped.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/docs-bump_test.sh. Run directly:
#   ./tests/skills-activation-bump_test.sh
#
# VERSION is NOT pinned as a byte-exact literal: the repo recorded lesson
# (tests/docs-bump_test.sh comments -- its "asserted VERSION == 4.0.0 and it
# broke on the next bump") is that a cross-change pin breaks on the next
# legitimate bump. Instead the tests assert the [4.2.0] - 2026-09-11 section
# exists and sits above [4.1.0], and that VERSION is a semver agreeing with
# the newest (topmost) CHANGELOG entry -- which today reads exactly 4.2.0,
# the value 03-render's marker and the --check machinery report.
#
# e2e-bump-01 (05-bump.feature) is observable only by driving live installs
# (./install.sh --check/--all against pre-change installed copies, marker
# version stamps) -- the verifier's Integration Verification, not this unit
# suite. It appears below as an explicit SKIP stub so no scenario id is
# silently unaccounted for.
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
  # An explicit, accounted-for stub for a scenario that is out of scope for
  # unit-level TDD (never a silent omission).
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

refuse() {
  # $1 = file, $2 = fixed string that must NOT appear in it
  if grep -qF -- "$2" "$1"; then
    echo "  found forbidden text: $2"
    return 1
  fi
  return 0
}

# This change's CHANGELOG entry: the [4.2.0] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry (4.1.0's edit-capability entry also says
# 'minor', 'major', ...) can never satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.2\.0\]/,/^## \[/{/^## \[4\.2\.0\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# The [4.2.0] heading line-number (for the above-[4.1.0] ordering test).
line_420() {
  grep -nF '## [4.2.0] - 2026-09-11' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_410() {
  grep -nF '## [4.1.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}

# =============================================================================
# bump-01: the bump is present -- VERSION is a semver agreeing with the
# newest (topmost) CHANGELOG entry (today exactly 4.2.0, trailing newline,
# the file's only content), the CHANGELOG.md carries a
# '## [4.2.0] - 2026-09-11' section above the [4.1.0] section, and that
# section lists the shipped skills-activation behavior: the coder and
# verifier prompts' new ## Skills sections, the orchestrator's pre-resolved
# '## Skills to load before work' delegation block, the Skill tool added to
# the readwrite Claude tools string in install.sh, and the docs gotcha.
# =============================================================================

test_bump_01_version_agrees_with_newest_entry() {
  ok=0
  version=$(cat "$VERSION_FILE")
  case "$version" in
    *[!0-9.]*) echo "  VERSION reads '$version', not a semver (X.Y.Z)"; ok=1 ;;
  esac
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

test_bump_01_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_bump_01_420_section_above_410() {
  ok=0
  l4="$(line_420)"
  l10="$(line_410)"
  [ -n "$l4" ] || { echo "  missing '## [4.2.0] - 2026-09-11' in CHANGELOG.md"; ok=1; }
  [ -n "$l10" ] || { echo "  missing '## [4.1.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l4" ] && [ -n "$l10" ] && [ "$l4" -ge "$l10" ]; then
    echo "  '## [4.2.0]' does not sit above '## [4.1.0]'"; ok=1
  fi
  return $ok
}

test_bump_01_entry_lists_prompts_skills() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '## Skills' || ok=1
  require "$CHANGELOG_ENTRY" 'coder' || ok=1
  require "$CHANGELOG_ENTRY" 'verifier' || ok=1
  return $ok
}

test_bump_01_entry_lists_orchestrator_delegation_block() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '## Skills to load before work' || ok=1
  require "$CHANGELOG_ENTRY" 'orchestrator' || ok=1
  return $ok
}

test_bump_01_entry_lists_claude_skill_grant() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'install.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'readwrite' || ok=1
  require "$CHANGELOG_ENTRY" 'Skill' || ok=1
  require "$CHANGELOG_ENTRY" 'Read, Grep, Glob, Bash, Edit, Write, Skill' || ok=1
  require "$CHANGELOG_ENTRY" 'allowlist' || ok=1
  return $ok
}

test_bump_01_entry_lists_docs_gotcha() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'gotcha' || ok=1
  require "$CHANGELOG_ENTRY" 'AGENTS.md' || ok=1
  require "$CHANGELOG_ENTRY" 'CLAUDE.md' || ok=1
  return $ok
}

# =============================================================================
# bump-02: the grade is minor, stated and justified against the versioning
# table -- behavior changes to the roles' prompts (## Skills sections) and to
# install.sh's rendered agent capability (the Skill grant), explicitly not
# patch (that grades only non-behavioral tweaks) and not major (the workflow
# contract, marker format, access taxonomy, rendered command contract, and
# install locations are all unchanged).
# =============================================================================

test_bump_02_entry_grades_minor_with_justification() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.2.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'minor' || ok=1
  require "$CHANGELOG_ENTRY" 'not major' || ok=1
  require "$CHANGELOG_ENTRY" 'not patch' || ok=1
  require "$CHANGELOG_ENTRY" 'behavior change' || ok=1
  require "$CHANGELOG_ENTRY" '## Skills' || ok=1
  require "$CHANGELOG_ENTRY" 'Skill' || ok=1
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'marker format' || ok=1
  require "$CHANGELOG_ENTRY" 'access taxonomy' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered command contract' || ok=1
  require "$CHANGELOG_ENTRY" 'install location' || ok=1
  return $ok
}

test_bump_02_version_is_the_bumping_value() {
  # The marker machinery (03-render) and ./install.sh --check report the
  # bumped value identically: VERSION is the value that makes the newest
  # CHANGELOG entry the drift --check prints and the marker stamps. Not a
  # byte-pinned literal -- the cross-change lesson (tests/docs-bump_test.sh:
  # its "asserted VERSION == 4.0.0" pin broke on the next bump) is that a
  # literal breaks on the next legitimate bump, so assert agreement with the
  # newest (topmost) entry instead (today exactly 4.2.1, the skills-desc-match
  # bump layered above this change's 4.2.0).
  version=$(cat "$VERSION_FILE")
  newest=$(sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$CHANGELOG_MD" | head -n 1)
  if [ -z "$newest" ] || [ "$version" != "$newest" ]; then
    echo "  VERSION reads '$version' but the newest CHANGELOG entry is '$newest' (must agree)"
    return 1
  fi
  return 0
}

# =============================================================================
# Invariant: agents/meta/* are byte-for-byte unchanged -- only non-meta edits
# are involved in this change (05-bump.feature Invariants).
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

# ---- run everything ---------------------------------------------------------

run_test "bump-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_bump_01_version_agrees_with_newest_entry
run_test "bump-01: VERSION's only content is the version value with one trailing newline" test_bump_01_newline_terminated_only_content
run_test "bump-01: CHANGELOG.md carries the '## [4.2.0] - 2026-09-11' section above the [4.1.0] section" test_bump_01_420_section_above_410
run_test "bump-01: the [4.2.0] entry lists the coder and verifier prompts' new ## Skills sections" test_bump_01_entry_lists_prompts_skills
run_test "bump-01: the [4.2.0] entry lists the orchestrator's pre-resolved '## Skills to load before work' delegation block" test_bump_01_entry_lists_orchestrator_delegation_block
run_test "bump-01: the [4.2.0] entry lists the Skill tool added to the readwrite Claude tools string in install.sh" test_bump_01_entry_lists_claude_skill_grant
run_test "bump-01: the [4.2.0] entry lists the docs skills-activation gotcha (AGENTS.md and CLAUDE.md)" test_bump_01_entry_lists_docs_gotcha
run_test "bump-02: the [4.2.0] entry grades minor with the versioning-table justification -- not patch (non-behavioral only), not major (contract/marker/taxonomy/command-contract/locations unchanged)" test_bump_02_entry_grades_minor_with_justification
run_test "bump-02: VERSION reads the bumping value -- agreeing with the newest (topmost) CHANGELOG entry, the drift --check and the render marker report (never a pinned literal)" test_bump_02_version_is_the_bumping_value
run_test "invariant: agents/meta/* are byte-for-byte unchanged versus git HEAD" test_meta_files_byte_unchanged

# ---- e2e-only scenario: explicit SKIP stub ------------------------------------
# e2e-bump-01 (spdd/changes/skills-activation/05-bump.feature) drives live
# installs (./install.sh --check against pre-change installed copies, then
# --all re-rendering with version=4.2.0 markers into a real HOME) -- the
# verifier's Integration Verification, not this unit suite. Explicit stub so
# the scenario id is accounted for (suite convention).

skip_test "e2e-bump-01: ./install.sh --check against pre-change installed copies reports the drift to 4.2.0 and prints the [4.2.0] entry; --all re-renders every installed file with antz:generated version=4.2.0 markers" \
  "e2e-only: live install / drift-report semantics, run by the verifier (05-bump.feature)"

rm -f "$CHANGELOG_ENTRY"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 05-bump.feature)"
[ "$fail_count" -eq 0 ]
