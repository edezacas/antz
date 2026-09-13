#!/usr/bin/env bash
# Unit tests for the bump layer of change precision-gaps
# (spdd/changes/precision-gaps/05-bump460.feature, scenarios
# bump460-01..02): the mandated minor VERSION bump to 4.6.0 and the matching
# dated CHANGELOG.md entry layered above [4.5.0], describing the precision-gap
# fixes: the specifier's conventions (two-digit index, one e2e-qa.feature per
# change dir, README per-sub-spec sections with relevant files and the
# declared destination domain), the coder's mechanical checks (literal-grep id
# search, fixed plan threshold N=8), the verifier's mechanical "code present"
# criterion and per-domain spec-file rule with create-when-new, the
# orchestrator's bounded slug derivation, and the probe's convention-aligned
# id extraction with its test and spec updates.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/bump450_test.sh and tests/bump440_test.sh (the recorded precedent,
# merged from change fix-orchestrator-flow into spdd/specs/versioning.md).
# Run:
#   ./tests/bump460_test.sh
#
# VERSION is NOT pinned as a byte-exact literal (the recorded lesson from
# tests/docs-bump_test.sh: a cross-change pin breaks on the next legitimate
# bump). The tests assert the '## [4.6.0] - <date>' section exists, is the
# topmost entry, and sits above [4.5.0] in the file's entry style, and that
# VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry --
# which together pin "VERSION reads exactly 4.6.0" today -- with one trailing
# newline as the file's only content. The [4.5.0]-down tail is pinned
# byte-identical to git HEAD, so stacking [4.6.0] on top keeps every older
# suite's own-section assertions stable (the earlier bump suites'
# agreement-based checks survive the newer entry).
#
# Evolved by change hardening-installsh (sub-spec 06, bump470): the
# unconditional "no '## [' heading sits above [4.6.0]" topmost half is
# retired with this loud note -- stacking a newer dated entry above [4.6.0]
# is the CHANGELOG's whole point, so that pin could not survive the arrival
# of the legitimate [4.7.0] entry it specced (this suite's own header above
# already states its checks are the agreement-based kind that survive newer
# entries; bump440/450 never carried the topmost half). The relative
# ordering ([4.6.0] above [4.5.0] above [4.4.0]), the exactly-one dated
# heading, and every other assertion here stay enforced either way.
#
# The install.sh-untouched and no-v4.6.0-tag checks are gated on the bump
# being uncommitted (the flow's state): once the human makes the bump commit
# (and may tag v4.6.0 against it -- tagging is the human's commit-time
# follow-up, never a role's), they retire vacuously with a loud note, same
# convention as the additive-vs-HEAD prose-diff guards
# (tests/orchestrator-sessionguards_test.sh's sessionguards-04 gate). The
# gate counts the working-tree diff as THIS change's only while HEAD does not
# yet carry the [4.6.0] entry (bump440's stacking lesson: a later legitimate
# bump must not resurrect these guards). The "tags not pushed automatically"
# half is repo policy pinned by the docs' Versioning sections
# (tests/versioning-rule_test.sh), not re-pinned here.
#
# The e2e-version ids (spdd/changes/precision-gaps/e2e-qa.feature) are the
# change's verifier-owned end-to-end QA suite (live ./install.sh --check/--all
# drift reporting at the user surface) -- not this unit suite; they are not
# stubbed here (the 05 sub-spec declares only bump460-01/02; the e2e layer
# owns its ids).
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

# This change's CHANGELOG entry: the [4.6.0] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry (4.5.0's entry also says 'state=bad_slug',
# 'workflow contract', 'install locations', 'four subcommands', ...) can never
# satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.6\.0\]/,/^## \[/{/^## \[4\.6\.0\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# The [4.5.0] section (the previous newest entry), for the "still describes
# its changes" half of the immutability assertion.
ENTRY_450=$(mktemp)
sed -n '/^## \[4\.5\.0\]/,/^## \[/{/^## \[4\.5\.0\]/d;p}' "$CHANGELOG_MD" > "$ENTRY_450"

line_460() {
  grep -nE '^## \[4\.6\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_450() {
  grep -nF '## [4.5.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_440() {
  grep -nF '## [4.4.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}

change_pending() {
  # True while this change's bump artifacts are uncommitted in the working
  # tree (the flow's state -- no role ever commits). Once the human's bump
  # commit lands, the HEAD-comparison guards retire vacuously with a note.
  # The conjunction is the stacking lesson bump440 recorded: a later
  # legitimate bump would also make the tree differ from HEAD, and must not
  # resurrect these guards against the human's own v4.6.0 tag -- so the diff
  # counts as THIS change's only while HEAD does not yet carry the [4.6.0]
  # entry.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- CHANGELOG.md VERSION 2>/dev/null \
    && ! git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null | grep -q '^## \[4\.6\.0\]'
}

# =============================================================================
# bump460-01: the bump is present -- VERSION reads 4.6.0 (value plus one
# trailing newline, its only content, phrased as agreement with the newest
# topmost entry per the repo's recorded lesson), CHANGELOG.md carries a dated
# '## [4.6.0] - <date>' topmost section above [4.5.0] in the file's entry
# style describing the precision-gap fixes, and the [4.5.0] section plus
# every entry below it are byte-for-byte unchanged.
# =============================================================================

test_bump460_01_version_agrees_with_newest_entry() {
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

test_bump460_01_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_bump460_01_460_section_above_450() {
  ok=0
  l60="$(line_460)"
  l50="$(line_450)"
  l40="$(line_440)"
  [ -n "$l60" ] || { echo "  CHANGELOG.md has no dated '## [4.6.0] - YYYY-MM-DD' heading"; ok=1; }
  [ -n "$l50" ] || { echo "  missing '## [4.5.0]' in CHANGELOG.md"; ok=1; }
  # Exactly one [4.6.0] heading.
  n=$(grep -cF '## [4.6.0]' "$CHANGELOG_MD")
  [ "$n" -eq 1 ] || { echo "  '## [4.6.0]' appears $n times, expected exactly 1"; ok=1; }
  # Topmost half retired by change hardening-installsh (sub-spec 06,
  # bump470) per the header's loud note: a newer dated entry stacking above
  # [4.6.0] is legitimate CHANGELOG growth, and the agreement test above
  # keeps pinning "VERSION reads exactly 4.6.0" for as long as [4.6.0] is
  # the newest entry. The relative ordering stays enforced forever.
  if [ -n "$l60" ] && [ -n "$l50" ] && [ "$l60" -ge "$l50" ]; then
    echo "  '## [4.6.0]' does not sit above '## [4.5.0]'"; ok=1
  fi
  if [ -n "$l50" ] && [ -n "$l40" ] && [ "$l50" -ge "$l40" ]; then
    echo "  '## [4.5.0]' no longer sits above '## [4.4.0]'"; ok=1
  fi
  # The Keep-a-Changelog statement and the file's preamble survive intact too.
  require "$CHANGELOG_MD" '[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)' || ok=1
  return $ok
}

test_bump460_01_entry_uses_existing_style() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  # The file's entry style: '### Added'/'### Changed' category headings with
  # bold lead-in bullets.
  require "$CHANGELOG_ENTRY" '### Added' || ok=1
  require "$CHANGELOG_ENTRY" '### Changed' || ok=1
  require "$CHANGELOG_ENTRY" '- **' || ok=1
  return $ok
}

test_bump460_01_entry_describes_specifier_conventions() {
  # The specifier's conventions: the two-digit index, one e2e-qa.feature per
  # change dir, README per-sub-spec sections with relevant files and the
  # declared destination domain (plus the verifier's per-domain file rule
  # with create-when-new, stated in the same Added bullet).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'two zero-padded digits' || ok=1
  require "$CHANGELOG_ENTRY" 'sequential from 01' || ok=1
  require "$CHANGELOG_ENTRY" 'one per change, not one per feature' || ok=1
  require "$CHANGELOG_ENTRY" '`e2e-qa.feature`' || ok=1
  require "$CHANGELOG_ENTRY" 'one section per sub-spec' || ok=1
  require "$CHANGELOG_ENTRY" 'destination domain' || ok=1
  require "$CHANGELOG_ENTRY" 'kebab-case' || ok=1
  require "$CHANGELOG_ENTRY" 'one spec file per domain' || ok=1
  require "$CHANGELOG_ENTRY" 'creates the file' || ok=1
  return $ok
}

test_bump460_01_entry_describes_coder_mechanical_checks() {
  # The coder's mechanical checks: the literal-grep id search and the fixed
  # plan threshold N=8 (more than 8 implementation steps, or more than 1
  # shared contract needing change).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'literal grep' || ok=1
  require "$CHANGELOG_ENTRY" "project's test files (the files carrying the unit-test suite)" || ok=1
  require "$CHANGELOG_ENTRY" 'more than 8 implementation steps' || ok=1
  require "$CHANGELOG_ENTRY" 'more than 1 shared contract' || ok=1
  return $ok
}

test_bump460_01_entry_describes_verifier_code_present() {
  # The verifier's mechanical "code present" criterion: the same literal
  # grep finds the declared ids, or the result receipt exists -- existence
  # only, never its contents.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'code present' || ok=1
  require "$CHANGELOG_ENTRY" 'result receipt' || ok=1
  require "$CHANGELOG_ENTRY" 'existence only, never its contents' || ok=1
  return $ok
}

test_bump460_01_entry_describes_orchestrator_bounded_slug() {
  # The orchestrator's bounded slug derivation: at most 40 characters, the
  # flow script's mechanical state=bad_slug gate, collision rules pinned.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'at most 40 characters' || ok=1
  require "$CHANGELOG_ENTRY" 'state=bad_slug' || ok=1
  require "$CHANGELOG_ENTRY" 'suffix' || ok=1
  require "$CHANGELOG_ENTRY" 'ask the user' || ok=1
  return $ok
}

test_bump460_01_entry_describes_probe_alignment_with_test_and_spec_updates() {
  # The probe's convention-aligned id extraction -- no hyphen admitted in
  # the feature portion, violations surface as foreign-id mismatch -- with
  # its test rewrite (same suite, re-tagged fixtures, new probealign-*
  # assertions) and the spdd/specs/receipts.md spec update.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'admits no hyphen' || ok=1
  require "$CHANGELOG_ENTRY" 'foreign-id mismatch' || ok=1
  require "$CHANGELOG_ENTRY" 'tests/orchestrator-status-probe_test.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'spdd/specs/receipts.md' || ok=1
  return $ok
}

test_bump460_01_entry_describes_surrounding_pin_moves() {
  # The surrounding test pins the rewordings tripped: prompts-05's specifier
  # guard and closingblock-05's specifier diff-window assertions retired by
  # gating (loudly), roles-03 re-scoped, and the change's new self-contained
  # suites named.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'prompts-05' || ok=1
  require "$CHANGELOG_ENTRY" 'closingblock-05' || ok=1
  require "$CHANGELOG_ENTRY" 'roles-03' || ok=1
  require "$CHANGELOG_ENTRY" 'tests/conventions_test.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'tests/rolechecks_test.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'tests/sluglimit_test.sh' || ok=1
  return $ok
}

test_bump460_01_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [4.5.0] - 2026-09-12' || ok=1
  l50="$(line_450)"
  l40="$(line_440)"
  [ -n "$l50" ] || { echo "  missing '## [4.5.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l40" ] || { echo "  missing '## [4.4.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l50" ] && [ -n "$l40" ] && [ "$l50" -ge "$l40" ]; then
    echo "  '## [4.5.0]' no longer sits above '## [4.4.0]'"; ok=1
  fi
  # [4.5.0] still describes its own changes (its distinguishing bullets).
  [ -s "$ENTRY_450" ] || { echo "  CHANGELOG.md has no [4.5.0] section"; ok=1; }
  require "$ENTRY_450" 'state=tree_dirty' || ok=1
  require "$ENTRY_450" 'dirty=yes' || ok=1
  require "$ENTRY_450" 'advisory' || ok=1
  # The immutable-history tail: everything from [4.5.0] down equals HEAD's.
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[4\.5\.0\]/,$p' > "$ENTRY_450.head"
    sed -n '/^## \[4\.5\.0\]/,$p' "$CHANGELOG_MD" > "$ENTRY_450.work"
    cmp -s "$ENTRY_450.head" "$ENTRY_450.work" \
      || { echo "  CHANGELOG.md's entries from [4.5.0] down differ from git HEAD's (earlier entries are immutable history)"; ok=1; }
    rm -f "$ENTRY_450.head" "$ENTRY_450.work"
  fi
  return $ok
}

# =============================================================================
# bump460-02: the grade is minor, stated and justified against the versioning
# gradation -- the role-prompt behavior changes (the specifier's conventions,
# the coder's threshold and search, the verifier's code-present and
# domain-file rules, the orchestrator's slug bullet) are changes to rendered
# agent bodies and the probe's extraction behavior changes (not the
# wording-only patch), while the workflow contract, the antz:generated marker
# format, the access model, the directory layout, and the install locations
# all survive (not major); install.sh itself is untouched (the bump reaches
# installed copies only through the normal ./install.sh --all re-render), and
# no role creates the v4.6.0 tag -- it is the human's commit-time follow-up,
# created against the bump commit and not pushed automatically.
# =============================================================================

test_bump460_02_entry_grades_minor_with_justification() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  # States the grade, not patch and not major.
  require "$CHANGELOG_ENTRY" 'grades as **minor**' || ok=1
  require "$CHANGELOG_ENTRY" 'not patch and not major' || ok=1
  # Names the justification: role-prompt behavior changes are changes to
  # rendered agent bodies (specifier, coder, verifier, orchestrator), and the
  # probe's extraction behavior changes -- not the wording-only patch.
  require "$CHANGELOG_ENTRY" 'role behavior' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered agent body' || ok=1
  require "$CHANGELOG_ENTRY" 'specifier' || ok=1
  require "$CHANGELOG_ENTRY" 'coder' || ok=1
  require "$CHANGELOG_ENTRY" 'verifier' || ok=1
  require "$CHANGELOG_ENTRY" 'orchestrator' || ok=1
  require "$CHANGELOG_ENTRY" 'extraction behavior changes' || ok=1
  require "$CHANGELOG_ENTRY" 'wording-only' || ok=1
  # Names what survives unchanged (not major).
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'marker format' || ok=1
  require "$CHANGELOG_ENTRY" 'access model' || ok=1
  require "$CHANGELOG_ENTRY" 'directory layout' || ok=1
  require "$CHANGELOG_ENTRY" 'install locations' || ok=1
  require "$CHANGELOG_ENTRY" 'no consumer breaks' || ok=1
  return $ok
}

test_bump460_02_entry_states_install_sh_untouched_re_render_carries_bump() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'itself is untouched' || ok=1
  require "$CHANGELOG_ENTRY" 'through the normal `./install.sh --all` re-render' || ok=1
  return $ok
}

test_bump460_02_entry_states_no_role_creates_v460_tag() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'no role creates the `v4.6.0` tag' || ok=1
  require "$CHANGELOG_ENTRY" "human's commit-time follow-up" || ok=1
  require "$CHANGELOG_ENTRY" "created against the human's bump commit" || ok=1
  require "$CHANGELOG_ENTRY" 'not pushed automatically' || ok=1
  return $ok
}

test_bump460_02_install_sh_byte_untouched_vs_head() {
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

test_bump460_02_no_v460_tag_created_while_uncommitted() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the no-tag guard is vacuously retired (v4.6.0 becomes the human's own commit-time follow-up, created against the human's bump commit and never pushed automatically)"
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" tag -l 'v4.6.0')" ]; then
    echo "  tag v4.6.0 already exists: no role may create it -- the local tag is the human's commit-time follow-up"
    return 1
  fi
  return 0
}

# ---- run everything -----------------------------------------------------------

run_test "bump460-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_bump460_01_version_agrees_with_newest_entry
run_test "bump460-01: VERSION's only content is the version value with one trailing newline" test_bump460_01_version_newline_terminated_only_content
run_test "bump460-01: CHANGELOG.md carries exactly one dated '## [4.6.0] - YYYY-MM-DD' section sitting above the [4.5.0] section which stays above [4.4.0] (topmost half retired per header loud note), Keep-a-Changelog statement intact" test_bump460_01_460_section_above_450
run_test "bump460-01: the [4.6.0] section uses the file's existing entry style -- Added/Changed category headings with bold lead-in bullets" test_bump460_01_entry_uses_existing_style
run_test "bump460-01: the [4.6.0] entry describes the specifier's conventions -- two-digit sequential index, one e2e-qa.feature per change dir, README per-sub-spec sections with relevant files and the declared kebab-case destination domain, and the verifier's per-domain file rule with create-when-new" test_bump460_01_entry_describes_specifier_conventions
run_test "bump460-01: the [4.6.0] entry describes the coder's mechanical checks -- the literal-grep id search in the project's test files and the fixed plan threshold (more than 8 implementation steps or more than 1 shared contract)" test_bump460_01_entry_describes_coder_mechanical_checks
run_test "bump460-01: the [4.6.0] entry describes the verifier's mechanical code-present criterion -- the same literal grep finds the declared ids, or the result receipt exists (existence only, never its contents)" test_bump460_01_entry_describes_verifier_code_present
run_test "bump460-01: the [4.6.0] entry describes the orchestrator's bounded slug derivation -- at most 40 characters matching the state=bad_slug gate, collision rules pinned" test_bump460_01_entry_describes_orchestrator_bounded_slug
run_test "bump460-01: the [4.6.0] entry describes the probe's convention-aligned id extraction with its test rewrite and the spdd/specs/receipts.md spec update" test_bump460_01_entry_describes_probe_alignment_with_test_and_spec_updates
run_test "bump460-01: the [4.6.0] entry describes the surrounding pin moves -- prompts-05 and closingblock-05 gated retirements, roles-03 re-scoped, and the new self-contained suites" test_bump460_01_entry_describes_surrounding_pin_moves
run_test "bump460-01: the [4.5.0] section and every entry below it are byte-for-byte unchanged -- still above [4.4.0] still describing its changes, and the [4.5.0]-down tail matches git HEAD" test_bump460_01_earlier_entries_byte_untouched

run_test "bump460-02: the [4.6.0] entry grades minor with the versioning-table justification -- not patch (the specifier's conventions, the coder's threshold and search, the verifier's code-present and domain-file rules, and the orchestrator's slug bullet change rendered agent bodies, and the probe's extraction behavior changes; not wording-only), not major (workflow contract, marker format, access model, directory layout, install locations unchanged, no consumer breaks)" test_bump460_02_entry_grades_minor_with_justification
run_test "bump460-02: the [4.6.0] entry states install.sh itself is untouched and the bump reaches installed copies only through the normal ./install.sh --all re-render" test_bump460_02_entry_states_install_sh_untouched_re_render_carries_bump
run_test "bump460-02: the [4.6.0] entry states no role creates the v4.6.0 tag -- it is the human's commit-time follow-up, created against the bump commit and not pushed automatically" test_bump460_02_entry_states_no_role_creates_v460_tag
run_test "bump460-02: install.sh is byte-identical to git HEAD while the bump is uncommitted (retires after the human's commit)" test_bump460_02_install_sh_byte_untouched_vs_head
run_test "bump460-02: no v4.6.0 tag exists while the bump is uncommitted -- no role tags; it is the human's commit-time follow-up (retires after the human's commit)" test_bump460_02_no_v460_tag_created_while_uncommitted

rm -f "$CHANGELOG_ENTRY" "$ENTRY_450"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (see 05-bump460.feature)"
[ "$fail_count" -eq 0 ]
