#!/usr/bin/env bash
# Unit tests for the bump layer of change fix-orchestrator-flow
# (spdd/changes/fix-orchestrator-flow/04-bump440.feature, scenarios
# bump440-01..02): the mandated minor VERSION bump to 4.4.0 and the matching
# dated CHANGELOG.md entry layered above [4.3.0], describing items 1.1-1.7 of
# docs/plan-revision-2026-09.md Cambio A in user-facing terms.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/skills-desc-match-bump_test.sh and tests/closingblock_test.sh. Run:
#   ./tests/bump440_test.sh
#
# VERSION is NOT pinned as a byte-exact literal (the recorded lesson from
# tests/docs-bump_test.sh: a cross-change pin breaks on the next legitimate
# bump). The tests assert the '## [4.4.0] - <date>' section exists above
# [4.3.0] in the file's entry style, and that VERSION is a semver agreeing
# with the newest (topmost) CHANGELOG entry -- which today reads exactly
# 4.4.0 -- with one trailing newline as the file's only content. Earlier
# entries are pinned immutable (the [4.3.0]-down tail byte-untouched vs git
# HEAD), so stacking [4.4.0] on top keeps the whole suite stable.
#
# The install.sh-untouched and no-v4.4.0-tag checks are gated on the bump
# being uncommitted (the flow's state): once the human makes the bump commit
# (and may tag v4.4.0 against it -- tagging is the human's commit-time
# follow-up, never a role's), they retire vacuously with a loud note, same
# convention as the additive-vs-HEAD prose-diff guards
# (tests/orchestrator-sessionguards_test.sh's sessionguards-04 gate). The
# "tags not pushed automatically" half is repo policy pinned by the docs'
# Versioning sections (tests/versioning-rule_test.sh), not re-pinned here.
#
# The e2e-version-01 scenario (spdd/changes/fix-orchestrator-flow/e2e-qa.feature)
# is the change's verifier-owned end-to-end QA suite (live ./install.sh
# --check/--all drift reporting at the user surface) -- not this unit suite;
# it is not stubbed here (the 04 sub-spec declares only bump440-01/02; the
# e2e layer owns its ids).
#
# Skills activated for this session: none matched (no available skill covers
# VERSION/CHANGELOG.md bookkeeping or this repo's bash test harness style).

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"
INSTALL_SH="$SCRIPT_DIR/install.sh"

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

# ---- fixture helpers ----------------------------------------------------------

require() {
  # $1 = file, $2 = fixed string that must appear in it
  if grep -qF -- "$2" "$1"; then return 0; fi
  echo "  missing required text: $2"
  return 1
}

# This change's CHANGELOG entry: the [4.4.0] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry (4.3.0's entry also says 'dedup',
# 'test_command=', 'latch', ...) can never satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.4\.0\]/,/^## \[/{/^## \[4\.4\.0\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# The [4.3.0] section (the previous newest entry), for the "still describes
# its changes" half of the immutability assertion.
ENTRY_430=$(mktemp)
sed -n '/^## \[4\.3\.0\]/,/^## \[/{/^## \[4\.3\.0\]/d;p}' "$CHANGELOG_MD" > "$ENTRY_430"

line_440() {
  grep -nE '^## \[4\.4\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_430() {
  grep -nF '## [4.3.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_421() {
  grep -nF '## [4.2.1]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}

change_pending() {
  # True while this change's bump artifacts are uncommitted in the working
  # tree (the flow's state -- no role ever commits). Once the human's bump
  # commit lands, the HEAD-comparison guards retire vacuously with a note.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- CHANGELOG.md VERSION 2>/dev/null
}

# =============================================================================
# bump440-01: the bump is present -- VERSION reads 4.4.0 (value plus one
# trailing newline, its only content, phrased as agreement with the newest
# topmost entry per the repo's recorded lesson), CHANGELOG.md gains a
# '## [4.4.0] - <date>' section above [4.3.0] in the file's entry style
# describing the change's substance (items 1.1-1.7), and every earlier entry
# is byte-for-byte untouched.
# =============================================================================

test_bump440_01_version_agrees_with_newest_entry() {
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

test_bump440_01_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_bump440_01_440_section_above_430() {
  ok=0
  l40="$(line_440)"
  l30="$(line_430)"
  l21="$(line_421)"
  [ -n "$l40" ] || { echo "  CHANGELOG.md has no dated '## [4.4.0] - YYYY-MM-DD' heading"; ok=1; }
  [ -n "$l30" ] || { echo "  missing '## [4.3.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l40" ] && [ -n "$l30" ] && [ "$l40" -ge "$l30" ]; then
    echo "  '## [4.4.0]' does not sit above '## [4.3.0]'"; ok=1
  fi
  # The Keep-a-Changelog statement and the file's preamble survive intact too.
  require "$CHANGELOG_MD" '[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)' || ok=1
  return $ok
}

test_bump440_01_entry_uses_existing_style() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  # The file's entry style: '### Added'/'### Changed' category headings with
  # bold lead-in bullets.
  require "$CHANGELOG_ENTRY" '### Added' || ok=1
  require "$CHANGELOG_ENTRY" '### Changed' || ok=1
  require "$CHANGELOG_ENTRY" '- **' || ok=1
  return $ok
}

test_bump440_01_entry_describes_specifier_delegation() {
  # 1.1: the never-specified delegation with mid-session deletion and
  # post-verifier routing.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'never specified' || ok=1
  require "$CHANGELOG_ENTRY" 'delegates the whole change to the `specifier`' || ok=1
  require "$CHANGELOG_ENTRY" 'branch-only' || ok=1
  require "$CHANGELOG_ENTRY" 're-probes' || ok=1
  require "$CHANGELOG_ENTRY" 'at most once per invocation' || ok=1
  require "$CHANGELOG_ENTRY" 'deletion mid-session' || ok=1
  require "$CHANGELOG_ENTRY" 'status=stopped' || ok=1
  require "$CHANGELOG_ENTRY" 'disk-based detection routes it' || ok=1
  return $ok
}

test_bump440_01_entry_describes_dedup_two_exceptions() {
  # 1.2: the dedup guard's two enumerated exceptions, both step 4's.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'dedup guard' || ok=1
  require "$CHANGELOG_ENTRY" 'exactly two exceptions, both step 4' || ok=1
  require "$CHANGELOG_ENTRY" 'attributable blocker' || ok=1
  require "$CHANGELOG_ENTRY" 'whole-change `verifier` retry' || ok=1
  require "$CHANGELOG_ENTRY" 'specifier is never re-delegated' || ok=1
  return $ok
}

test_bump440_01_entry_describes_step5_disk_detection() {
  # 1.3: step 5's disk-based verifier-outcome detection with the release-gate
  # disambiguation.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'outcome from disk, not conversation' || ok=1
  require "$CHANGELOG_ENTRY" 'governing rule, applied' || ok=1
  require "$CHANGELOG_ENTRY" 'approved-with-warnings included' || ok=1
  require "$CHANGELOG_ENTRY" 'new `REJECTED.md` entry' || ok=1
  require "$CHANGELOG_ENTRY" 'routes to step 6' || ok=1
  require "$CHANGELOG_ENTRY" 'stops fail-closed' || ok=1
  require "$CHANGELOG_ENTRY" 'archive-missing' || ok=1
  return $ok
}

test_bump440_01_entry_defines_waiting_user() {
  # 1.5: the defined waiting-user stop variant versus stopped.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'waiting-user` is defined, not removed' || ok=1
  require "$CHANGELOG_ENTRY" 'hands a decision to the user' || ok=1
  require "$CHANGELOG_ENTRY" 'open questions, slug ambiguity, receipt doubt' || ok=1
  require "$CHANGELOG_ENTRY" 'latch applies identically to both' || ok=1
  return $ok
}

test_bump440_01_entry_describes_coder_write_surface() {
  # 1.4: the coder's ownership restated by write surface.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'by write surface, not read surface' || ok=1
  require "$CHANGELOG_ENTRY" 'read-only context' || ok=1
  require "$CHANGELOG_ENTRY" 'wherever they belong in the project' || ok=1
  require "$CHANGELOG_ENTRY" 'never touches `spdd/archive/`' || ok=1
  return $ok
}

test_bump440_01_entry_describes_verifier_plain_mv() {
  # 1.6: the verifier's archive move, plain mv as the only instruction, with
  # its reason.
  # NB: the reason's leading git-mv clause is pinned by its tail only --
  # tests/roles_test.sh's roles-05 tripwire forbids any suite outside
  # roles_test.sh from carrying the literal removed wording; the tail still
  # pins that the entry states the always-fails reason and is satisfied only
  # by the full git-mv-on-untracked-files-always-fails shape (an entry
  # offering mv as one option among several cannot match).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'plain `mv` as the only instruction' || ok=1
  require "$CHANGELOG_ENTRY" 'mv` on untracked files always fails' || ok=1
  require "$CHANGELOG_ENTRY" 'nothing here is ever committed' || ok=1
  return $ok
}

test_bump440_01_entry_describes_none_sentinel() {
  # 1.7: the literal test_command=none sentinel, the probe's acceptance, and
  # the never-execute rule.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '`test_command=none`' || ok=1
  require "$CHANGELOG_ENTRY" 'never an empty value' || ok=1
  require "$CHANGELOG_ENTRY" 'probe accepts it as a well-formed non-empty value' || ok=1
  require "$CHANGELOG_ENTRY" 'complete=yes' || ok=1
  require "$CHANGELOG_ENTRY" 'never executes the sentinel' || ok=1
  require "$CHANGELOG_ENTRY" 'asks the user once' || ok=1
  return $ok
}

test_bump440_01_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [4.3.0] - 2026-09-11' || ok=1
  l30="$(line_430)"
  l21="$(line_421)"
  [ -n "$l30" ] || { echo "  missing '## [4.3.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l21" ] || { echo "  missing '## [4.2.1]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l30" ] && [ -n "$l21" ] && [ "$l30" -ge "$l21" ]; then
    echo "  '## [4.3.0]' no longer sits above '## [4.2.1]'"; ok=1
  fi
  # [4.3.0] still describes its own changes (its distinguishing bullets).
  [ -s "$ENTRY_430" ] || { echo "  CHANGELOG.md has no [4.3.0] section"; ok=1; }
  require "$ENTRY_430" 'Result receipts' || ok=1
  require "$ENTRY_430" 'Closing block' || ok=1
  require "$ENTRY_430" 'session guards' || ok=1
  # The immutable-history tail: everything from [4.3.0] down equals HEAD's.
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[4\.3\.0\]/,$p' > "$ENTRY_430.head"
    sed -n '/^## \[4\.3\.0\]/,$p' "$CHANGELOG_MD" > "$ENTRY_430.work"
    cmp -s "$ENTRY_430.head" "$ENTRY_430.work" \
      || { echo "  CHANGELOG.md's entries from [4.3.0] down differ from git HEAD's (earlier entries are immutable history)"; ok=1; }
    rm -f "$ENTRY_430.head" "$ENTRY_430.work"
  fi
  return $ok
}

# =============================================================================
# bump440-02: the grade is minor, stated and justified against the versioning
# gradation -- role behavior and rendered agent bodies change (not the
# wording-only patch), while the workflow contract, the antz:generated marker
# format, the access model, the directory layout, and the install locations
# all survive (not major); install.sh itself is untouched (the bump reaches
# installed copies only through the re-render), and no role creates the
# v4.4.0 tag -- it is the human's commit-time follow-up.
# =============================================================================

test_bump440_02_entry_grades_minor_with_justification() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'grades as **minor**' || ok=1
  require "$CHANGELOG_ENTRY" 'not patch and not major' || ok=1
  require "$CHANGELOG_ENTRY" 'role behavior' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered agent bodies' || ok=1
  require "$CHANGELOG_ENTRY" 'wording-only' || ok=1
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'marker format' || ok=1
  require "$CHANGELOG_ENTRY" 'access model' || ok=1
  require "$CHANGELOG_ENTRY" 'directory layout' || ok=1
  require "$CHANGELOG_ENTRY" 'install locations' || ok=1
  require "$CHANGELOG_ENTRY" 'output vocabulary' || ok=1
  require "$CHANGELOG_ENTRY" 'release machine lines' || ok=1
  require "$CHANGELOG_ENTRY" 'receipt grammar' || ok=1
  require "$CHANGELOG_ENTRY" 'four subcommands' || ok=1
  return $ok
}

test_bump440_02_entry_states_install_sh_untouched_re_render_carries_bump() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'itself is untouched' || ok=1
  require "$CHANGELOG_ENTRY" 'through the normal `./install.sh --all` re-render' || ok=1
  return $ok
}

test_bump440_02_install_sh_byte_untouched_vs_head() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the install.sh-untouched guard is vacuously retired (a future change touching install.sh must bump under the versioning rule anyway)"
    return 0
  fi
  head_copy=$(mktemp)
  if ! git -C "$SCRIPT_DIR" show HEAD:install.sh > "$head_copy" 2>/dev/null; then
    echo "  cannot read HEAD:install.sh"; rm -f "$head_copy"; return 1
  fi
  if ! cmp -s "$head_copy" "$INSTALL_SH"; then
    echo "  install.sh differs from git HEAD (this change must leave it untouched; the bump reaches installed copies only through the re-render)"
    rm -f "$head_copy"; return 1
  fi
  rm -f "$head_copy"
  return 0
}

test_bump440_02_no_v440_tag_created_while_uncommitted() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the no-tag guard is vacuously retired (v4.4.0 becomes the human's own commit-time follow-up, created against the human's bump commit and never pushed automatically)"
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" tag -l 'v4.4.0')" ]; then
    echo "  tag v4.4.0 already exists: no role may create it -- the local tag is the human's commit-time follow-up"
    return 1
  fi
  return 0
}

# ---- run everything -----------------------------------------------------------

run_test "bump440-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_bump440_01_version_agrees_with_newest_entry
run_test "bump440-01: VERSION's only content is the version value with one trailing newline" test_bump440_01_version_newline_terminated_only_content
run_test "bump440-01: CHANGELOG.md carries a dated '## [4.4.0] - YYYY-MM-DD' section above the [4.3.0] section, Keep-a-Changelog statement intact" test_bump440_01_440_section_above_430
run_test "bump440-01: the [4.4.0] section uses the file's existing entry style -- Added/Changed category headings with bold lead-in bullets" test_bump440_01_entry_uses_existing_style
run_test "bump440-01: the [4.4.0] entry describes the never-specified specifier delegation with the mid-session-deletion and post-verifier routing (1.1)" test_bump440_01_entry_describes_specifier_delegation
run_test "bump440-01: the [4.4.0] entry describes the dedup guard's two enumerated exceptions, both step 4's (1.2)" test_bump440_01_entry_describes_dedup_two_exceptions
run_test "bump440-01: the [4.4.0] entry describes step 5's disk-based verifier-outcome detection with the release-gate disambiguation (1.3)" test_bump440_01_entry_describes_step5_disk_detection
run_test "bump440-01: the [4.4.0] entry describes the defined waiting-user stop variant versus stopped (1.5)" test_bump440_01_entry_defines_waiting_user
run_test "bump440-01: the [4.4.0] entry describes the coder's ownership bullet restated by write surface (1.4)" test_bump440_01_entry_describes_coder_write_surface
run_test "bump440-01: the [4.4.0] entry describes the verifier's plain-mv archive step with its git-mv-always-fails reason (1.6)" test_bump440_01_entry_describes_verifier_plain_mv
run_test "bump440-01: the [4.4.0] entry describes the literal test_command=none sentinel with the probe's acceptance and the never-execute rule (1.7)" test_bump440_01_entry_describes_none_sentinel
run_test "bump440-01: every earlier entry is byte-untouched -- [4.3.0] still sits above [4.2.1] still describing its changes, and the [4.3.0]-down tail matches git HEAD" test_bump440_01_earlier_entries_byte_untouched

run_test "bump440-02: the [4.4.0] entry grades minor with the versioning-table justification -- not patch (role behavior and rendered agent bodies change), not major (contract/marker format/access model/directory layout/install locations unchanged; probe vocabulary, release lines, receipt grammar, four subcommands survive)" test_bump440_02_entry_grades_minor_with_justification
run_test "bump440-02: the [4.4.0] entry states install.sh itself is untouched and the bump reaches installed copies only through the normal ./install.sh --all re-render" test_bump440_02_entry_states_install_sh_untouched_re_render_carries_bump
run_test "bump440-02: install.sh is byte-identical to git HEAD while the bump is uncommitted (retires after the human's commit)" test_bump440_02_install_sh_byte_untouched_vs_head
run_test "bump440-02: no v4.4.0 tag exists while the bump is uncommitted -- no role tags; it is the human's commit-time follow-up (retires after the human's commit)" test_bump440_02_no_v440_tag_created_while_uncommitted

rm -f "$CHANGELOG_ENTRY" "$ENTRY_430"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (see 04-bump440.feature)"
[ "$fail_count" -eq 0 ]
