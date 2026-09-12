#!/usr/bin/env bash
# Unit tests for the bump layer of change flow-script-guards
# (spdd/changes/flow-script-guards/03-bump450.feature, scenarios
# bump450-01..02): the mandated minor VERSION bump to 4.5.0 and the matching
# dated CHANGELOG.md entry layered above [4.4.0], describing the flow script's
# mechanical slug validation, the new-flow tree guard, the advisory dirty=yes
# resume line, the orchestrator prompt wiring, and the flow-suite test moves.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/bump440_test.sh (the recorded precedent, merged from change
# fix-orchestrator-flow into spdd/specs/versioning.md). Run:
#   ./tests/bump450_test.sh
#
# VERSION is NOT pinned as a byte-exact literal (the recorded lesson from
# tests/docs-bump_test.sh: a cross-change pin breaks on the next legitimate
# bump). The tests assert the '## [4.5.0] - <date>' section exists above
# [4.4.0] in the file's entry style, and that VERSION is a semver agreeing
# with the newest (topmost) CHANGELOG entry -- which together pin "VERSION
# reads exactly 4.5.0" today -- with one trailing newline as the file's only
# content. The [4.4.0]-down tail is pinned byte-identical to git HEAD, so
# stacking [4.5.0] on top keeps every older suite's own-section assertions
# stable.
#
# The install.sh-untouched and no-v4.5.0-tag checks are gated on the bump
# being uncommitted (the flow's state): once the human makes the bump commit
# (and may tag v4.5.0 against it -- tagging is the human's commit-time
# follow-up, never a role's), they retire vacuously with a loud note, same
# convention as the additive-vs-HEAD prose-diff guards
# (tests/orchestrator-sessionguards_test.sh's sessionguards-04 gate). The
# "tags not pushed automatically" half is repo policy pinned by the docs'
# Versioning sections (tests/versioning-rule_test.sh), not re-pinned here.
#
# The e2e-version-01 scenario (spdd/changes/flow-script-guards/e2e-qa.feature)
# is the change's verifier-owned end-to-end QA suite (live ./install.sh
# --check/--all drift reporting at the user surface) -- not this unit suite;
# it is not stubbed here (the 03 sub-spec declares only bump450-01/02; the
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

# This change's CHANGELOG entry: the [4.5.0] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry (4.4.0's entry also says 'workflow contract',
# 'install locations', 'release machine lines', ...) can never satisfy this
# change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.5\.0\]/,/^## \[/{/^## \[4\.5\.0\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# The [4.4.0] section (the previous newest entry), for the "still describes
# its changes" half of the immutability assertion.
ENTRY_440=$(mktemp)
sed -n '/^## \[4\.4\.0\]/,/^## \[/{/^## \[4\.4\.0\]/d;p}' "$CHANGELOG_MD" > "$ENTRY_440"

line_450() {
  grep -nE '^## \[4\.5\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_440() {
  grep -nF '## [4.4.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
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
  # The conjunction is the lesson bump440 learned at this very change: a
  # later legitimate bump (say 4.6.0) would also make the tree differ from
  # HEAD, and must not resurrect these guards against the human's own
  # v4.5.0 tag -- so the diff counts as THIS change's only while HEAD does
  # not yet carry the [4.5.0] entry.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- CHANGELOG.md VERSION 2>/dev/null \
    && ! git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null | grep -q '^## \[4\.5\.0\]'
}

# =============================================================================
# bump450-01: the bump is present -- VERSION reads 4.5.0 (value plus one
# trailing newline, its only content, phrased as agreement with the newest
# topmost entry per the repo's recorded lesson), CHANGELOG.md gains a
# '## [4.5.0] - <date>' section above [4.4.0] in the file's entry style
# describing the change's substance, and every earlier entry is byte-for-byte
# untouched.
# =============================================================================

test_bump450_01_version_agrees_with_newest_entry() {
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

test_bump450_01_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_bump450_01_450_section_above_440() {
  ok=0
  l50="$(line_450)"
  l40="$(line_440)"
  l30="$(line_430)"
  [ -n "$l50" ] || { echo "  CHANGELOG.md has no dated '## [4.5.0] - YYYY-MM-DD' heading"; ok=1; }
  [ -n "$l40" ] || { echo "  missing '## [4.4.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l50" ] && [ -n "$l40" ] && [ "$l50" -ge "$l40" ]; then
    echo "  '## [4.5.0]' does not sit above '## [4.4.0]'"; ok=1
  fi
  # The Keep-a-Changelog statement and the file's preamble survive intact too.
  require "$CHANGELOG_MD" '[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)' || ok=1
  return $ok
}

test_bump450_01_entry_uses_existing_style() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  # The file's entry style: '### Added'/'### Changed' category headings with
  # bold lead-in bullets.
  require "$CHANGELOG_ENTRY" '### Added' || ok=1
  require "$CHANGELOG_ENTRY" '### Changed' || ok=1
  require "$CHANGELOG_ENTRY" '- **' || ok=1
  return $ok
}

test_bump450_01_entry_describes_slug_validation() {
  # The flow script's mechanical slug validation: state=bad_slug, rejection
  # before any branch or positioning work, non-destructive.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'state=bad_slug' || ok=1
  require "$CHANGELOG_ENTRY" 'mechanically' || ok=1
  require "$CHANGELOG_ENTRY" 'non-destructive' || ok=1
  require "$CHANGELOG_ENTRY" 'branch or positioning work' || ok=1
  return $ok
}

test_bump450_01_entry_describes_tree_guard() {
  # The new-flow tree guard: state=tree_dirty only on the conjunction
  # (change dir absent AND marker branch newly created), skipped on resume.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'state=tree_dirty' || ok=1
  require "$CHANGELOG_ENTRY" 'change dir `spdd/changes/<slug>/` is absent' || ok=1
  require "$CHANGELOG_ENTRY" 'marker branch would be newly created' || ok=1
  require "$CHANGELOG_ENTRY" 'skipped on a resume' || ok=1
  require "$CHANGELOG_ENTRY" 'git status --porcelain' || ok=1
  return $ok
}

test_bump450_01_entry_describes_dirty_advisory() {
  # The advisory dirty=yes resume line: after any state=reused on a
  # non-empty porcelain, no routing change, clean reuse prints exactly
  # state=reused.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'dirty=yes' || ok=1
  require "$CHANGELOG_ENTRY" 'state=reused' || ok=1
  require "$CHANGELOG_ENTRY" 'advisory' || ok=1
  require "$CHANGELOG_ENTRY" 'not a stop' || ok=1
  require "$CHANGELOG_ENTRY" 'A clean reuse still prints exactly `state=reused`' || ok=1
  return $ok
}

test_bump450_01_entry_describes_orchestrator_wiring() {
  # The orchestrator prompt wiring: step 1's ensure instructions, the latch,
  # and the Report Format now name the new states; dirty=yes documented as
  # advisory.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'step 1' || ok=1
  require "$CHANGELOG_ENTRY" 'latch' || ok=1
  require "$CHANGELOG_ENTRY" 'Report Format' || ok=1
  require "$CHANGELOG_ENTRY" 'status=stopped' || ok=1
  return $ok
}

test_bump450_01_entry_describes_flow_suite_test_moves() {
  # The rewritten/added flow-suite tests, including the scripts
  # byte-unchanged guard re-scoped off antz-flow.sh.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'ensure-02' || ok=1
  require "$CHANGELOG_ENTRY" 'ensure-05' || ok=1
  require "$CHANGELOG_ENTRY" 'rewritten' || ok=1
  require "$CHANGELOG_ENTRY" 're-scoped off `antz-flow.sh`' || ok=1
  require "$CHANGELOG_ENTRY" 'flow-09' || ok=1
  return $ok
}

test_bump450_01_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [4.4.0] - 2026-09-12' || ok=1
  l40="$(line_440)"
  l30="$(line_430)"
  l21="$(line_421)"
  [ -n "$l40" ] || { echo "  missing '## [4.4.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l30" ] || { echo "  missing '## [4.3.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l21" ] || { echo "  missing '## [4.2.1]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l40" ] && [ -n "$l30" ] && [ "$l40" -ge "$l30" ]; then
    echo "  '## [4.4.0]' no longer sits above '## [4.3.0]'"; ok=1
  fi
  if [ -n "$l30" ] && [ -n "$l21" ] && [ "$l30" -ge "$l21" ]; then
    echo "  '## [4.3.0]' no longer sits above '## [4.2.1]'"; ok=1
  fi
  # [4.4.0] still describes its own changes (its distinguishing bullets).
  [ -s "$ENTRY_440" ] || { echo "  CHANGELOG.md has no [4.4.0] section"; ok=1; }
  require "$ENTRY_440" 'never specified' || ok=1
  require "$ENTRY_440" 'two exceptions, both step 4' || ok=1
  require "$ENTRY_440" '`test_command=none`' || ok=1
  # The immutable-history tail: everything from [4.4.0] down equals HEAD's.
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[4\.4\.0\]/,$p' > "$ENTRY_440.head"
    sed -n '/^## \[4\.4\.0\]/,$p' "$CHANGELOG_MD" > "$ENTRY_440.work"
    cmp -s "$ENTRY_440.head" "$ENTRY_440.work" \
      || { echo "  CHANGELOG.md's entries from [4.4.0] down differ from git HEAD's (earlier entries are immutable history)"; ok=1; }
    rm -f "$ENTRY_440.head" "$ENTRY_440.work"
  fi
  return $ok
}

# =============================================================================
# bump450-02: the grade is minor, stated and justified against the versioning
# gradation -- the flow script's behavior and the orchestrator's routing
# change (not the wording-only patch), while the workflow contract, the
# antz:generated marker format, the access model, the directory layout, and
# the install locations all survive and the four subcommands, probe output
# vocabulary, release machine lines, and receipt grammar keep working (not
# major); install.sh itself is untouched (the bump reaches installed copies
# only through the re-render), and no role creates the v4.5.0 tag -- it is the
# human's commit-time follow-up.
# =============================================================================

test_bump450_02_entry_grades_minor_with_justification() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'grades as **minor**' || ok=1
  require "$CHANGELOG_ENTRY" 'not patch and not major' || ok=1
  require "$CHANGELOG_ENTRY" 'flow script' || ok=1
  require "$CHANGELOG_ENTRY" 'orchestrator' || ok=1
  require "$CHANGELOG_ENTRY" 'routing' || ok=1
  require "$CHANGELOG_ENTRY" 'wording-only' || ok=1
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'marker format' || ok=1
  require "$CHANGELOG_ENTRY" 'access model' || ok=1
  require "$CHANGELOG_ENTRY" 'directory layout' || ok=1
  require "$CHANGELOG_ENTRY" 'install locations' || ok=1
  require "$CHANGELOG_ENTRY" 'four subcommands' || ok=1
  require "$CHANGELOG_ENTRY" 'output vocabulary' || ok=1
  require "$CHANGELOG_ENTRY" 'release machine lines' || ok=1
  require "$CHANGELOG_ENTRY" 'receipt grammar' || ok=1
  return $ok
}

test_bump450_02_entry_states_install_sh_untouched_re_render_carries_bump() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'itself is untouched' || ok=1
  require "$CHANGELOG_ENTRY" 'through the normal `./install.sh --all` re-render' || ok=1
  return $ok
}

test_bump450_02_entry_states_no_role_creates_v450_tag() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'no role creates the `v4.5.0` tag' || ok=1
  require "$CHANGELOG_ENTRY" "human's commit-time follow-up" || ok=1
  return $ok
}

test_bump450_02_install_sh_byte_untouched_vs_head() {
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

test_bump450_02_no_v450_tag_created_while_uncommitted() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the no-tag guard is vacuously retired (v4.5.0 becomes the human's own commit-time follow-up, created against the human's bump commit and never pushed automatically)"
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" tag -l 'v4.5.0')" ]; then
    echo "  tag v4.5.0 already exists: no role may create it -- the local tag is the human's commit-time follow-up"
    return 1
  fi
  return 0
}

# ---- run everything -----------------------------------------------------------

run_test "bump450-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_bump450_01_version_agrees_with_newest_entry
run_test "bump450-01: VERSION's only content is the version value with one trailing newline" test_bump450_01_version_newline_terminated_only_content
run_test "bump450-01: CHANGELOG.md carries a dated '## [4.5.0] - YYYY-MM-DD' section above the [4.4.0] section, Keep-a-Changelog statement intact" test_bump450_01_450_section_above_440
run_test "bump450-01: the [4.5.0] section uses the file's existing entry style -- Added/Changed category headings with bold lead-in bullets" test_bump450_01_entry_uses_existing_style
run_test "bump450-01: the [4.5.0] entry describes the mechanical slug validation with the non-destructive state=bad_slug rejection" test_bump450_01_entry_describes_slug_validation
run_test "bump450-01: the [4.5.0] entry describes the new-flow tree guard -- state=tree_dirty only when the change dir is absent and the branch would be newly created, skipped on resume" test_bump450_01_entry_describes_tree_guard
run_test "bump450-01: the [4.5.0] entry describes the advisory dirty=yes line after a reused-on-dirty-tree, with the clean reuse unchanged" test_bump450_01_entry_describes_dirty_advisory
run_test "bump450-01: the [4.5.0] entry describes the orchestrator prompt wiring -- step 1, the latch, and the Report Format naming the new states" test_bump450_01_entry_describes_orchestrator_wiring
run_test "bump450-01: the [4.5.0] entry describes the rewritten/added flow-suite tests, including the scripts byte-unchanged guard re-scoped off antz-flow.sh" test_bump450_01_entry_describes_flow_suite_test_moves
run_test "bump450-01: every earlier entry is byte-untouched -- [4.4.0] still sits above [4.3.0] above [4.2.1] still describing its changes, and the [4.4.0]-down tail matches git HEAD" test_bump450_01_earlier_entries_byte_untouched

run_test "bump450-02: the [4.5.0] entry grades minor with the versioning-table justification -- not patch (flow script behavior and orchestrator routing change), not major (contract/marker format/access model/directory layout/install locations unchanged; four subcommands, probe output vocabulary, release machine lines, receipt grammar survive)" test_bump450_02_entry_grades_minor_with_justification
run_test "bump450-02: the [4.5.0] entry states install.sh itself is untouched and the bump reaches installed copies only through the normal ./install.sh --all re-render" test_bump450_02_entry_states_install_sh_untouched_re_render_carries_bump
run_test "bump450-02: the [4.5.0] entry states no role creates the v4.5.0 tag -- it is the human's commit-time follow-up" test_bump450_02_entry_states_no_role_creates_v450_tag
run_test "bump450-02: install.sh is byte-identical to git HEAD while the bump is uncommitted (retires after the human's commit)" test_bump450_02_install_sh_byte_untouched_vs_head
run_test "bump450-02: no v4.5.0 tag exists while the bump is uncommitted -- no role tags; it is the human's commit-time follow-up (retires after the human's commit)" test_bump450_02_no_v450_tag_created_while_uncommitted

rm -f "$CHANGELOG_ENTRY" "$ENTRY_440"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (see 03-bump450.feature)"
[ "$fail_count" -eq 0 ]
