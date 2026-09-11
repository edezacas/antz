#!/usr/bin/env bash
# Unit tests for the docs layer of change flow-branch-checkout
# (spdd/archive/flow-branch-checkout/03-docs.feature, scenarios docs-01..03):
# the AGENTS.md/CLAUDE.md gotcha bullets rewritten for the create-and-
# checkout flow contract, the VERSION bump, and the matching dated
# CHANGELOG.md entry.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/versioning-rule_test.sh. Run directly:
#   ./tests/docs-bump_test.sh
#
# The two gotcha bullets are shared verbatim between AGENTS.md and CLAUDE.md
# (the files' shared-bullet convention), so every content test runs against
# both files' extracted bullet and a parity test compares them byte-for-byte.
# The CHANGELOG content tests are scoped to this change's own entry -- the one
# immediately above the immutable [3.0.0] baseline (Keep a Changelog order is
# newest-first, so later changes only stack further up; this change's entry is
# therefore stable for the file's lifetime) -- so a stray phrase in an older
# entry can never satisfy them, and the "earlier entries untouched" test
# compares everything from the [3.0.0] heading down against git HEAD's copy.
# No test pins the current VERSION value: a cross-change pin would break on
# the next bump, which is exactly the bug docs-03 shipped with (it asserted
# VERSION == 4.0.0 and broke when change specifier-write-access bumped the
# VERSION to 4.1.0). The only versioning-policy assertions live in
# tests/versioning-rule_test.sh.
#
# e2e-docs-01 (spdd/changes/flow-branch-checkout/e2e-qa.feature) is
# observable only by driving live installs (./install.sh --check/--all) and
# re-rendering into a real HOME -- the verifier's Integration Verification,
# not this unit suite. It appears below as an explicit SKIP stub so no
# scenario id is silently unaccounted for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/versioning-rule_test.sh) ---------------

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

refuse_word() {
  # $1 = file, $2 = word that must NOT appear as a whole word in it
  if grep -qw -- "$2" "$1"; then
    echo "  found forbidden word: $2"
    return 1
  fi
  return 0
}

extract_bullet() {
  # $1 = md file, $2 = fixed bullet prefix; prints the first matching line
  grep -F -- "$2" "$1" | head -n 1
}

# Extract each file's two gotcha bullets once (single lines), so the content
# tests grep the bullet alone -- a required or forbidden phrase elsewhere in
# the file must never satisfy or trip a bullet-scoped assertion.
AGENTS_BRANCH=$(mktemp)
CLAUDE_BRANCH=$(mktemp)
AGENTS_RELEASE=$(mktemp)
CLAUDE_RELEASE=$(mktemp)
printf '%s\n' "$(extract_bullet "$AGENTS_MD" '- **Branch-marked flow')" > "$AGENTS_BRANCH"
printf '%s\n' "$(extract_bullet "$CLAUDE_MD" '- **Branch-marked flow')" > "$CLAUDE_BRANCH"
printf '%s\n' "$(extract_bullet "$AGENTS_MD" '- Release gating, never speculative')" > "$AGENTS_RELEASE"
printf '%s\n' "$(extract_bullet "$CLAUDE_MD" '- Release gating, never speculative')" > "$CLAUDE_RELEASE"

# This change's CHANGELOG entry is the one immediately above the [3.0.0]
# baseline: from the first '## [' heading above the [3.0.0] heading to
# (excluding) the next '## [' heading. Content tests grep this extract so
# older entries' text can never satisfy them. (If no entry sits above
# [3.0.0], the extract is empty and the tests fail loudly.)
CHANGELOG_ENTRY=$(mktemp)
awk '/^## \[3\.0\.0\]/{exit} /^## \[/{f=1} f' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"
# The version of that entry, parsed out of the extract (first '## [<semver>]'
# heading). Tests that need the version read this variable, never a literal.
CHANGELOG_ENTRY_VERSION=$(sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$CHANGELOG_ENTRY" | head -n 1)

both_bullets() {
  # $1 = name of a check function taking one bullet file; runs it on both
  # files' branch-marker bullet (and, for release tests, pass the release
  # bullets instead via the *_RELEASE temp files).
  "$1" "$AGENTS_BRANCH" && "$1" "$CLAUDE_BRANCH"
}

both_release_bullets() {
  "$1" "$AGENTS_RELEASE" && "$1" "$CLAUDE_RELEASE"
}

# =============================================================================
# docs-01: the branch-marker gotcha bullet reflects the create-and-checkout
# contract, the refused stop, and the revised law -- identically in both
# files.
# =============================================================================

check_branch_create_and_position() {
  ok=0
  require "$1" 'created **and checked out** by the orchestrator'"'"'s `antz-flow.sh`' || ok=1
  require "$1" 'the flow'"'"'s session sits on `antz/<slug>`' || ok=1
  require "$1" 're-positions the session onto the existing branch' || ok=1
  return $ok
}

test_docs_01_create_and_position() {
  ok=0
  [ -s "$AGENTS_BRANCH" ] || { echo "  AGENTS.md has no branch-marker gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_BRANCH" ] || { echo "  CLAUDE.md has no branch-marker gotcha bullet"; ok=1; }
  both_bullets check_branch_create_and_position || ok=1
  return $ok
}

check_branch_refused_positioning() {
  ok=0
  require "$1" 'A refused positioning' || ok=1
  require "$1" 'state=checkout_refused' || ok=1
  require "$1" 'never forces anything' || ok=1
  return $ok
}

test_docs_01_refused_positioning() {
  both_bullets check_branch_refused_positioning
}

check_branch_law() {
  ok=0
  require "$1" 'no `-B`, no `--force`, no merges, no resets, no branch deletes, and never a forced or overwriting checkout' || ok=1
  refuse "$1" 'no checkouts' || ok=1
  return $ok
}

test_docs_01_law_drops_no_checkouts() {
  both_bullets check_branch_law
}

check_branch_level_marker() {
  ok=0
  require "$1" '(`4.0` behavior)' || ok=1
  refuse "$1" '(`3.0` behavior)' || ok=1
  return $ok
}

test_docs_01_marks_level_4_0() {
  both_bullets check_branch_level_marker
}

test_docs_01_bullet_identical_in_both_files() {
  ok=0
  [ -s "$AGENTS_BRANCH" ] || { echo "  AGENTS.md has no branch-marker gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_BRANCH" ] || { echo "  CLAUDE.md has no branch-marker gotcha bullet"; ok=1; }
  cmp -s "$AGENTS_BRANCH" "$CLAUDE_BRANCH" \
    || { echo "  branch-marker bullet differs between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

# =============================================================================
# docs-02: the release-gating gotcha bullet states the user-controlled
# follow-ups, with no integration branch name inline.
# =============================================================================

check_release_followups() {
  ok=0
  require "$1" 'the user is already on `antz/<slug>`' || ok=1
  require "$1" 'reviews the pending files in `git status`' || ok=1
  require "$1" 'commits whenever and how they prefer' || ok=1
  require "$1" 'whether and where to merge (e.g. `git switch <integration> && git merge antz/<slug>`' || ok=1
  require "$1" 'may delete the branch' || ok=1
  return $ok
}

test_docs_02_user_controlled_followups() {
  ok=0
  [ -s "$AGENTS_RELEASE" ] || { echo "  AGENTS.md has no release-gating gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_RELEASE" ] || { echo "  CLAUDE.md has no release-gating gotcha bullet"; ok=1; }
  both_release_bullets check_release_followups || ok=1
  return $ok
}

check_release_never_merges_or_resets() {
  require "$1" 'never merges and never resets a branch'
}

test_docs_02_orchestrator_never_merges_or_resets() {
  both_release_bullets check_release_never_merges_or_resets
}

check_release_no_integration_branch_name() {
  ok=0
  refuse_word "$1" 'master' || ok=1
  refuse_word "$1" 'main' || ok=1
  return $ok
}

test_docs_02_no_concrete_integration_branch_named() {
  both_release_bullets check_release_no_integration_branch_name
}

test_docs_02_bullet_identical_in_both_files() {
  ok=0
  [ -s "$AGENTS_RELEASE" ] || { echo "  AGENTS.md has no release-gating gotcha bullet"; ok=1; }
  [ -s "$CLAUDE_RELEASE" ] || { echo "  CLAUDE.md has no release-gating gotcha bullet"; ok=1; }
  cmp -s "$AGENTS_RELEASE" "$CLAUDE_RELEASE" \
    || { echo "  release-gating bullet differs between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

# =============================================================================
# docs-03: the mandatory bump artifact -- a dated CHANGELOG entry describing
# exactly what changed, per the versioning policy (see AGENTS.md Versioning /
# tests/versioning-rule_test.sh) -- with no earlier entry rewritten. Nothing
# here pins the current VERSION value (the 4.0.0 literal this test originally
# shipped with broke on the next change's bump to 4.1.0): VERSION is only
# checked to exist, be a semver, and agree with the entry this change added.
# =============================================================================

# semver shapes: anchored (whole-string match) and unanchored (embedding in a
# larger pattern, e.g. the '## [<version>] - <date>' heading regex).
semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
semver_re_re='[0-9]+\.[0-9]+\.[0-9]+'

test_docs_03_version_is_semver_and_matches_entry() {
  version=$(cat "$VERSION_FILE")
  if ! printf '%s' "$version" | grep -Eq "$semver_re"; then
    echo "  VERSION reads '$version', not a semver (X.Y.Z)"
    return 1
  fi
  if [ "$version" != "$CHANGELOG_ENTRY_VERSION" ]; then
    echo "  VERSION reads '$version' but the dated CHANGELOG entry above [3.0.0] is '$CHANGELOG_ENTRY_VERSION'"
    return 1
  fi
  return 0
}

test_docs_03_entry_shape_dated_and_breaking() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no entry above [3.0.0]"; ok=1; }
  # First line of the extract: a dated '## [<semver>] - <date>' heading.
  head -n 1 "$CHANGELOG_ENTRY" | grep -Eq "^## \[$semver_re_re\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" \
    || { echo "  the entry above [3.0.0] is not a dated '## [X.Y.Z] - YYYY-MM-DD' heading: '$(head -n 1 "$CHANGELOG_ENTRY")'"; ok=1; }
  require "$CHANGELOG_ENTRY" '### Changed' || ok=1
  require "$CHANGELOG_ENTRY" '**Breaking (workflow contract):' || ok=1
  entry_line=$(grep -nF -- "## [$CHANGELOG_ENTRY_VERSION]" "$CHANGELOG_MD" | head -n 1 | cut -d: -f1)
  prev_line=$(grep -nF -- '## [3.0.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1)
  [ -n "$entry_line" ] && [ -n "$prev_line" ] && [ "$entry_line" -lt "$prev_line" ] \
    || { echo "  this change's entry (## [$CHANGELOG_ENTRY_VERSION]) must sit above the [3.0.0] entry"; ok=1; }
  return $ok
}

test_docs_03_entry_describes_the_contract_change() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no entry above [3.0.0]"; ok=1; }
  require "$CHANGELOG_ENTRY" 'checks the branch out' || ok=1
  require "$CHANGELOG_ENTRY" 're-positions' || ok=1
  require "$CHANGELOG_ENTRY" 'state=checkout_refused' || ok=1
  require "$CHANGELOG_ENTRY" 'no role ever commits anything' || ok=1
  require "$CHANGELOG_ENTRY" 'the user is already on `antz/<slug>`' || ok=1
  require "$CHANGELOG_ENTRY" 'git switch <integration> && git merge antz/<slug>' || ok=1
  require "$CHANGELOG_ENTRY" 'may delete the branch' || ok=1
  require "$CHANGELOG_ENTRY" 'never hardcodes an integration branch name' || ok=1
  return $ok
}

test_docs_03_entry_tests_note() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no entry above [3.0.0]"; ok=1; }
  require "$CHANGELOG_ENTRY" 'no-checkout assertion' || ok=1
  require "$CHANGELOG_ENTRY" 'inverted' || ok=1
  require "$CHANGELOG_ENTRY" 'checkout/positioning assertion' || ok=1
  require "$CHANGELOG_ENTRY" 'never-commits and no-destruction guarantees still tested' || ok=1
  return $ok
}

test_docs_03_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [3.0.0] - 2026-09-10' || ok=1
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[3\.0\.0\]/,$p' > "$CHANGELOG_ENTRY.head"
    sed -n '/^## \[3\.0\.0\]/,$p' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY.work"
    cmp -s "$CHANGELOG_ENTRY.head" "$CHANGELOG_ENTRY.work" \
      || { echo "  CHANGELOG.md's entries from [3.0.0] down differ from git HEAD's (earlier entries are immutable history)"; ok=1; }
    rm -f "$CHANGELOG_ENTRY.head" "$CHANGELOG_ENTRY.work"
  fi
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "docs-01: the branch-marker gotcha bullet states ensure creates AND checks out the branch, the session sits on antz/<slug> uncommitted, and resume re-positions (both files)" test_docs_01_create_and_position
run_test "docs-01: the branch-marker gotcha bullet states a refused positioning stops the flow with a machine-readable state and never forces anything (both files)" test_docs_01_refused_positioning
run_test "docs-01: the branch-marker gotcha bullet's law drops 'no checkouts', keeps no -B/--force, no merges, no resets, no deletes, and adds never a forced or overwriting checkout (both files)" test_docs_01_law_drops_no_checkouts
run_test "docs-01: the branch-marker gotcha bullet marks the behavior level 4.0, not 3.0 (both files)" test_docs_01_marks_level_4_0
run_test "docs-01: the branch-marker gotcha bullet is byte-identical between AGENTS.md and CLAUDE.md" test_docs_01_bullet_identical_in_both_files

run_test "docs-02: the release-gating gotcha bullet states the user-controlled follow-ups -- on antz/<slug>, review via git status, commit whenever/how, merge where they decide (e.g. git switch <integration> && git merge antz/<slug>), optional delete (both files)" test_docs_02_user_controlled_followups
run_test "docs-02: the release-gating gotcha bullet states the orchestrator never merges and never resets a branch (both files)" test_docs_02_orchestrator_never_merges_or_resets
run_test "docs-02: the release-gating gotcha bullet names no concrete integration branch (no master/main) (both files)" test_docs_02_no_concrete_integration_branch_named
run_test "docs-02: the release-gating gotcha bullet is byte-identical between AGENTS.md and CLAUDE.md" test_docs_02_bullet_identical_in_both_files

run_test "docs-03: VERSION is a semver agreeing with the version of the dated CHANGELOG entry this change added (above [3.0.0]) -- never a pinned value" test_docs_03_version_is_semver_and_matches_entry
run_test "docs-03: the CHANGELOG entry above [3.0.0] is a dated [X.Y.Z] - YYYY-MM-DD heading with a Changed section labelling the change breaking (workflow contract)" test_docs_03_entry_shape_dated_and_breaking
run_test "docs-03: the CHANGELOG entry this change added (the one above [3.0.0]) describes ensure's create-and-checkout (fresh) and re-positioning (resume), the state=checkout_refused stop, the intact never-commits law, and the user-controlled follow-ups" test_docs_03_entry_describes_the_contract_change
run_test "docs-03: the CHANGELOG entry this change added notes the no-checkout assertion inverted to a checkout/positioning assertion with the never-commits and no-destruction guarantees still tested" test_docs_03_entry_tests_note
run_test "docs-03: every CHANGELOG entry other than this change's own and those of later changes (the [3.0.0]-down tail) is byte-untouched versus git HEAD" test_docs_03_earlier_entries_byte_untouched

# ---- e2e-only scenario: explicit SKIP stub ------------------------------------
# e2e-docs-01 (spdd/changes/flow-branch-checkout/e2e-qa.feature) drives live
# installs (./install.sh --check then --all into a real HOME, re-rendered
# markers, a fresh --check) -- the verifier's Integration Verification, not
# this unit suite. Explicit stub so the scenario id is accounted for (suite
# convention: see tests/versioning-rule_test.sh and tests/antz-flow_test.sh).

skip_test "e2e-docs-01: install.sh --check reports antz 3.0.0 -> 4.0.0 with the new changelog entry and writes nothing; --all re-renders with version=4.0.0 markers; both docs carry the updated bullets identically" \
  "e2e-only: live install / re-render semantics, run by the verifier (e2e-qa.feature)"

rm -f "$AGENTS_BRANCH" "$CLAUDE_BRANCH" "$AGENTS_RELEASE" "$CLAUDE_RELEASE" "$CHANGELOG_ENTRY"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see e2e-qa.feature)"
[ "$fail_count" -eq 0 ]
