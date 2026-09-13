#!/usr/bin/env bash
# Unit tests for the bump layer of change hardening-installsh
# (spdd/changes/hardening-installsh/06-bump470.feature, scenarios
# bump470-01..02): the mandated minor VERSION bump to 4.7.0 and the matching
# dated CHANGELOG.md entry layered above [4.6.0], describing the install.sh
# hardening: the header-anchored antz:generated marker detection at its three
# sites (install_file, installed_version_of, the /antz-set-model embedded
# script) closing the overwrite-without-backup hole, the quoted description
# scalars at the three render sites (render_claude, render_opencode,
# render_set_model_command), the ANTZ_REF ref derivation replacing the
# hardcoded master, the embedded script's mktemp cleanup trap, the stated
# .bak.<timestamp> policy and the completed install.sh header, and the
# AGENTS.md/CLAUDE.md "not present yet" correction.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/bump460_test.sh, tests/bump450_test.sh and tests/bump440_test.sh (the
# recorded precedent, merged from change precision-gaps into
# spdd/specs/versioning.md).
# Run:
#   ./tests/bump470_test.sh
#
# VERSION is NOT pinned as a byte-exact literal (the recorded lesson from
# tests/docs-bump_test.sh: a cross-change pin breaks on the next legitimate
# bump). The tests assert the '## [4.7.0] - <date>' section exists and sits
# above [4.5.0]-lineage in the file's entry style, and that VERSION is a
# semver agreeing with the newest (topmost) CHANGELOG entry -- which together
# pin "VERSION reads exactly 4.7.0" today -- with one trailing newline as the
# file's only content. The [4.6.0]-down tail is pinned byte-identical to git
# HEAD, so stacking [4.7.0] on top keeps every older suite's own-section
# assertions stable.
#
# Stacking lesson applied to THIS suite: unlike bump460's original topmost
# half (an unconditional "no '## [' heading sits above [4.6.0]" pin that the
# arrival of this very [4.7.0] entry forced to retire, loudly, in
# tests/bump460_test.sh), this suite pins only the RELATIVE order ([4.7.0]
# above [4.6.0] above [4.5.0]) plus the agreement check -- so the next
# legitimate bump can stack above [4.7.0] without breaking these tests, and
# "VERSION reads exactly 4.7.0" stays pinned today without a cross-change
# literal.
#
# The no-v4.7.0-tag and agents/-untouched guards are gated on the bump being
# uncommitted (the flow's state): once the human makes the bump commit (and
# may tag v4.7.0 against it -- tagging is the human's commit-time follow-up,
# never a role's), they retire vacuously with a loud note, same convention as
# tests/bump460_test.sh's install.sh-untouched gate (whose own comment records
# the bump440 stacking lesson: the diff counts as THIS change's only while
# HEAD does not yet carry the entry).
#
# The e2e-qa ids (spdd/changes/hardening-installsh/e2e-qa.feature) are the
# change's verifier-owned end-to-end QA suite -- not this unit suite; they are
# not stubbed here (the 06 sub-spec declares only bump470-01/02; the e2e layer
# owns its ids).
#
# Skills activated for this session: none matched (no available skill covers
# VERSION/CHANGELOG.md bookkeeping or this repo's bash test harness style).

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

# ---- fixture helpers ----------------------------------------------------------

require() {
  # $1 = file, $2 = fixed string that must appear in it
  if grep -qF -- "$2" "$1"; then return 0; fi
  echo "  missing required text: $2"
  return 1
}

# This change's CHANGELOG entry: the [4.7.0] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry can never satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.7\.0\]/,/^## \[/{/^## \[4\.7\.0\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# The [4.6.0] section (the previous newest entry), for the "still describes
# its changes" half of the immutability assertion.
ENTRY_460=$(mktemp)
sed -n '/^## \[4\.6\.0\]/,/^## \[/{/^## \[4\.6\.0\]/d;p}' "$CHANGELOG_MD" > "$ENTRY_460"

line_470() {
  grep -nE '^## \[4\.7\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_460() {
  grep -nF '## [4.6.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_450() {
  grep -nF '## [4.5.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}

change_pending() {
  # True while this change's bump artifacts are uncommitted in the working
  # tree (the flow's state -- no role ever commits). Once the human's bump
  # commit lands, the gated guards retire vacuously with a note. The
  # conjunction is the recorded stacking lesson: a later legitimate bump
  # would also make the tree differ from HEAD, and must not resurrect these
  # guards against the human's own v4.7.0 tag -- so the diff counts as THIS
  # change's only while HEAD does not yet carry the [4.7.0] entry.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- CHANGELOG.md VERSION 2>/dev/null \
    && ! git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null | grep -q '^## \[4\.7\.0\]'
}

# =============================================================================
# bump470-01: the bump is present -- VERSION reads 4.7.0 (value plus one
# trailing newline, its only content, phrased as agreement with the newest
# topmost entry per the repo's recorded lesson), CHANGELOG.md carries a dated
# '## [4.7.0] - <date>' section above [4.6.0] in the file's entry style
# describing the install.sh hardening, and the [4.6.0] section plus every
# entry below it are byte-for-byte unchanged.
# =============================================================================

test_bump470_01_version_agrees_with_newest_entry() {
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

test_bump470_01_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_bump470_01_470_section_dated_above_460() {
  ok=0
  l70="$(line_470)"
  l60="$(line_460)"
  l50="$(line_450)"
  [ -n "$l70" ] || { echo "  CHANGELOG.md has no dated '## [4.7.0] - YYYY-MM-DD' heading"; ok=1; }
  [ -n "$l60" ] || { echo "  missing '## [4.6.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l50" ] || { echo "  missing '## [4.5.0]' in CHANGELOG.md"; ok=1; }
  # Exactly one [4.7.0] heading.
  n=$(grep -cF '## [4.7.0]' "$CHANGELOG_MD")
  [ "$n" -eq 1 ] || { echo "  '## [4.7.0]' appears $n times, expected exactly 1"; ok=1; }
  # Relative ordering only -- deliberately no unconditional "nothing sits
  # above [4.7.0]" topmost pin (the stacking lesson; this suite's header
  # records why). The agreement test above keeps "VERSION reads exactly 4.7.0"
  # pinned today.
  if [ -n "$l70" ] && [ -n "$l60" ] && [ "$l70" -ge "$l60" ]; then
    echo "  '## [4.7.0]' does not sit above '## [4.6.0]'"; ok=1
  fi
  if [ -n "$l60" ] && [ -n "$l50" ] && [ "$l60" -ge "$l50" ]; then
    echo "  '## [4.6.0]' no longer sits above '## [4.5.0]'"; ok=1
  fi
  # The Keep-a-Changelog statement and the file's preamble survive intact too.
  require "$CHANGELOG_MD" '[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)' || ok=1
  return $ok
}

test_bump470_01_entry_uses_existing_style() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  # The file's entry style: category headings with bold lead-in bullets.
  require "$CHANGELOG_ENTRY" '### Changed' || ok=1
  require "$CHANGELOG_ENTRY" '- **' || ok=1
  return $ok
}

test_bump470_01_entry_describes_header_marker_detection() {
  # The header-anchored marker detection at its three sites and the
  # overwrite-without-backup hole it closes.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'line-start header comment' || ok=1
  require "$CHANGELOG_ENTRY" 'install_file' || ok=1
  require "$CHANGELOG_ENTRY" 'installed_version_of' || ok=1
  require "$CHANGELOG_ENTRY" 'embedded script' || ok=1
  require "$CHANGELOG_ENTRY" 'overwrite-without-backup' || ok=1
  require "$CHANGELOG_ENTRY" 'mid-body' || ok=1
  require "$CHANGELOG_ENTRY" 'backed up' || ok=1
  require "$CHANGELOG_ENTRY" 'fresh install' || ok=1
  return $ok
}

test_bump470_01_entry_describes_quoted_descriptions() {
  # The quoted description scalars at the three render sites, value-preserving.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'double-quoted' || ok=1
  require "$CHANGELOG_ENTRY" 'render_claude' || ok=1
  require "$CHANGELOG_ENTRY" 'render_opencode' || ok=1
  require "$CHANGELOG_ENTRY" 'render_set_model_command' || ok=1
  require "$CHANGELOG_ENTRY" 'backslashes' || ok=1
  require "$CHANGELOG_ENTRY" 'byte-for-byte' || ok=1
  return $ok
}

test_bump470_01_entry_describes_antz_ref_derivation() {
  # The ANTZ_REF ref derivation replacing the hardcoded master -- a tagged
  # install no longer reads master content.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'ANTZ_REF' || ok=1
  require "$CHANGELOG_ENTRY" 'RAW_BASE' || ok=1
  require "$CHANGELOG_ENTRY" 'hardcoded' || ok=1
  require "$CHANGELOG_ENTRY" 'verbatim' || ok=1
  require "$CHANGELOG_ENTRY" 'no longer reads master content' || ok=1
  require "$CHANGELOG_ENTRY" 'fetch_file' || ok=1
  require "$CHANGELOG_ENTRY" 'local-checkout' || ok=1
  return $ok
}

test_bump470_01_entry_describes_cleanup_trap() {
  # The embedded script's mktemp cleanup trap.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'mktemp' || ok=1
  require "$CHANGELOG_ENTRY" 'cleanup trap' || ok=1
  require "$CHANGELOG_ENTRY" 'every exit path' || ok=1
  require "$CHANGELOG_ENTRY" 'never the target' || ok=1
  return $ok
}

test_bump470_01_entry_describes_policy_and_header_completion() {
  # The stated .bak.<timestamp> policy and the completed install.sh header
  # (orchestrator and commands named).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '.bak.<timestamp>' || ok=1
  require "$CHANGELOG_ENTRY" 'backup policy' || ok=1
  require "$CHANGELOG_ENTRY" 'never reads, renames, or deletes' || ok=1
  require "$CHANGELOG_ENTRY" "cleanup is the user's" || ok=1
  require "$CHANGELOG_ENTRY" 'antz-orchestrator' || ok=1
  require "$CHANGELOG_ENTRY" 'both installed commands' || ok=1
  return $ok
}

test_bump470_01_entry_describes_repodocs_correction() {
  # The AGENTS.md/CLAUDE.md "not present yet" correction.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'AGENTS.md and CLAUDE.md' || ok=1
  require "$CHANGELOG_ENTRY" 'not present yet' || ok=1
  require "$CHANGELOG_ENTRY" 'exist in the checkout' || ok=1
  require "$CHANGELOG_ENTRY" 'byte-identical between the two files' || ok=1
  return $ok
}

test_bump470_01_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [4.6.0] - 2026-09-13' || ok=1
  l60="$(line_460)"
  l50="$(line_450)"
  [ -n "$l60" ] || { echo "  missing '## [4.6.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l50" ] || { echo "  missing '## [4.5.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l60" ] && [ -n "$l50" ] && [ "$l60" -ge "$l50" ]; then
    echo "  '## [4.6.0]' no longer sits above '## [4.5.0]'"; ok=1
  fi
  # [4.6.0] still describes its own changes (its distinguishing bullets).
  [ -s "$ENTRY_460" ] || { echo "  CHANGELOG.md has no [4.6.0] section"; ok=1; }
  require "$ENTRY_460" 'two zero-padded digits' || ok=1
  require "$ENTRY_460" 'state=bad_slug' || ok=1
  require "$ENTRY_460" 'code present' || ok=1
  # The immutable-history tail: everything from [4.6.0] down equals HEAD's.
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[4\.6\.0\]/,$p' > "$ENTRY_460.head"
    sed -n '/^## \[4\.6\.0\]/,$p' "$CHANGELOG_MD" > "$ENTRY_460.work"
    cmp -s "$ENTRY_460.head" "$ENTRY_460.work" \
      || { echo "  CHANGELOG.md's entries from [4.6.0] down differ from git HEAD's (earlier entries are immutable history)"; ok=1; }
    rm -f "$ENTRY_460.head" "$ENTRY_460.work"
  fi
  return $ok
}

# =============================================================================
# bump470-02: the grade is minor, stated and justified against the versioning
# gradation -- install.sh's detection logic and rendered output both change
# (anchored marker detection, quoted descriptions, ANTZ_REF-driven fetch
# URLs), which is not the wording-only patch, while the workflow contract, the
# marker format, the access model, the directory layout, and the install
# locations all survive (not major, no consumer breaks); agents/prompts/ and
# agents/meta/ are untouched; and no role creates the v4.7.0 tag -- it is the
# human's commit-time follow-up, created against the bump commit and not
# pushed automatically.
# =============================================================================

test_bump470_02_entry_grades_minor_with_justification() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  # States the grade, not patch and not major.
  require "$CHANGELOG_ENTRY" 'grades as **minor**' || ok=1
  require "$CHANGELOG_ENTRY" 'not patch and not major' || ok=1
  # Names the justification: detection logic and rendered output both change
  # (not the wording-only patch).
  require "$CHANGELOG_ENTRY" 'detection logic and rendered output both change' || ok=1
  require "$CHANGELOG_ENTRY" 'wording-only' || ok=1
  require "$CHANGELOG_ENTRY" 'ANTZ_REF' || ok=1
  # Names what survives unchanged (not major).
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'marker format' || ok=1
  require "$CHANGELOG_ENTRY" 'access model' || ok=1
  require "$CHANGELOG_ENTRY" 'directory layout' || ok=1
  require "$CHANGELOG_ENTRY" 'install locations' || ok=1
  require "$CHANGELOG_ENTRY" 'no consumer breaks' || ok=1
  return $ok
}

test_bump470_02_entry_names_the_surviving_surface() {
  # The not-major half states the survivors concretely: the marker line's
  # shape, the flags, the rendered frontmatter field set, the install paths.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" "marker line's shape" || ok=1
  require "$CHANGELOG_ENTRY" 'flags' || ok=1
  require "$CHANGELOG_ENTRY" 'frontmatter field set' || ok=1
  require "$CHANGELOG_ENTRY" 'install paths' || ok=1
  return $ok
}

test_bump470_02_entry_states_prompts_untouched_and_no_role_tags() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'agents/prompts/' || ok=1
  require "$CHANGELOG_ENTRY" 'agents/meta/' || ok=1
  require "$CHANGELOG_ENTRY" 'untouched' || ok=1
  require "$CHANGELOG_ENTRY" 'no role creates the `v4.7.0` tag' || ok=1
  require "$CHANGELOG_ENTRY" "human's commit-time follow-up" || ok=1
  require "$CHANGELOG_ENTRY" "created against the human's bump commit" || ok=1
  require "$CHANGELOG_ENTRY" 'not pushed automatically' || ok=1
  return $ok
}

test_bump470_02_agents_prompts_and_meta_byte_untouched_vs_head() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the agents/-untouched guard is vacuously retired (a future change touching agents/ must bump under the versioning rule anyway)"
    return 0
  fi
  if ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- agents/prompts agents/meta 2>/dev/null; then
    echo "  agents/prompts/ or agents/meta/ differs from git HEAD (the entire change must leave them untouched)"
    return 1
  fi
  return 0
}

test_bump470_02_no_v470_tag_created_while_uncommitted() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the no-tag guard is vacuously retired (v4.7.0 becomes the human's own commit-time follow-up, created against the human's bump commit and never pushed automatically)"
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" tag -l 'v4.7.0')" ]; then
    echo "  tag v4.7.0 already exists: no role may create it -- the local tag is the human's commit-time follow-up"
    return 1
  fi
  return 0
}

test_bump470_02_versioning_policy_docs_unchanged() {
  # The versioning policy itself is unchanged by this bump: the
  # "## Versioning" sections of AGENTS.md and CLAUDE.md are byte-identical to
  # git HEAD (the bump follows the existing gradation, not a new rubric;
  # sub-spec 06's out-of-scope clause).
  ok=0
  for doc in AGENTS.md CLAUDE.md; do
    if ! git -C "$SCRIPT_DIR" show "HEAD:$doc" 2>/dev/null > "$CHANGELOG_ENTRY.headdoc"; then
      echo "  cannot read HEAD:$doc"; ok=1; continue
    fi
    awk '/^## Versioning/{f=1} f' "$CHANGELOG_ENTRY.headdoc" \
      | awk 'NR==1{print;next} /^## /{exit} {print}' > "$CHANGELOG_ENTRY.headsec"
    awk '/^## Versioning/{f=1} f' "$SCRIPT_DIR/$doc" \
      | awk 'NR==1{print;next} /^## /{exit} {print}' > "$CHANGELOG_ENTRY.worksec"
    cmp -s "$CHANGELOG_ENTRY.headsec" "$CHANGELOG_ENTRY.worksec" \
      || { echo "  $doc's '## Versioning' section differs from git HEAD (the policy docs are out of this change's scope)"; ok=1; }
    [ -s "$CHANGELOG_ENTRY.headsec" ] \
      || { echo "  HEAD:$doc has no '## Versioning' section to compare against"; ok=1; }
    rm -f "$CHANGELOG_ENTRY.headdoc" "$CHANGELOG_ENTRY.headsec" "$CHANGELOG_ENTRY.worksec"
  done
  return $ok
}

# ---- run everything -----------------------------------------------------------

run_test "bump470-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_bump470_01_version_agrees_with_newest_entry
run_test "bump470-01: VERSION's only content is the version value with one trailing newline" test_bump470_01_version_newline_terminated_only_content
run_test "bump470-01: CHANGELOG.md carries exactly one dated '## [4.7.0] - YYYY-MM-DD' section sitting above the [4.6.0] section which stays above [4.5.0] (relative ordering only -- the stacking lesson), Keep-a-Changelog statement intact" test_bump470_01_470_section_dated_above_460
run_test "bump470-01: the [4.7.0] section uses the file's existing entry style -- category headings with bold lead-in bullets" test_bump470_01_entry_uses_existing_style
run_test "bump470-01: the [4.7.0] entry describes the header-anchored marker detection at its three sites (install_file, installed_version_of, the /antz-set-model embedded script) and the overwrite-without-backup hole it closes" test_bump470_01_entry_describes_header_marker_detection
run_test "bump470-01: the [4.7.0] entry describes the quoted description scalars at the three render sites (render_claude, render_opencode, render_set_model_command), value-preserving" test_bump470_01_entry_describes_quoted_descriptions
run_test "bump470-01: the [4.7.0] entry describes the ANTZ_REF ref derivation replacing the hardcoded master -- a tagged install no longer reads master content, local-checkout installs unaffected" test_bump470_01_entry_describes_antz_ref_derivation
run_test "bump470-01: the [4.7.0] entry describes the embedded script's mktemp cleanup trap on every exit path" test_bump470_01_entry_describes_cleanup_trap
run_test "bump470-01: the [4.7.0] entry describes the stated .bak.<timestamp> backup policy and the completed install.sh header (orchestrator and commands named)" test_bump470_01_entry_describes_policy_and_header_completion
run_test "bump470-01: the [4.7.0] entry describes the AGENTS.md/CLAUDE.md 'not present yet' correction of the spdd/ Structure bullet" test_bump470_01_entry_describes_repodocs_correction
run_test "bump470-01: the [4.6.0] section and every entry below it are byte-for-byte unchanged -- still above [4.5.0] still describing its changes, and the [4.6.0]-down tail matches git HEAD" test_bump470_01_earlier_entries_byte_untouched

run_test "bump470-02: the [4.7.0] entry grades minor with the versioning-table justification -- not patch (install.sh's detection logic and rendered output both change: anchored marker detection, quoted descriptions, ANTZ_REF-driven fetch URLs; not wording-only), not major (workflow contract, marker format, access model, directory layout, install locations unchanged, no consumer breaks)" test_bump470_02_entry_grades_minor_with_justification
run_test "bump470-02: the [4.7.0] entry names the surviving surface concretely -- the marker line's shape, the flags, the rendered frontmatter field set, and the install paths all survive" test_bump470_02_entry_names_the_surviving_surface
run_test "bump470-02: the [4.7.0] entry states agents/prompts/ and agents/meta/ are untouched and no role creates the v4.7.0 tag -- it is the human's commit-time follow-up, created against the bump commit and not pushed automatically" test_bump470_02_entry_states_prompts_untouched_and_no_role_tags
run_test "bump470-02: agents/prompts/ and agents/meta/ are byte-identical to git HEAD while the bump is uncommitted (retires after the human's commit)" test_bump470_02_agents_prompts_and_meta_byte_untouched_vs_head
run_test "bump470-02: no v4.7.0 tag exists while the bump is uncommitted -- no role tags; it is the human's commit-time follow-up (retires after the human's commit)" test_bump470_02_no_v470_tag_created_while_uncommitted
run_test "bump470-02: the '## Versioning' sections of AGENTS.md and CLAUDE.md are byte-identical to git HEAD -- the bump follows the existing gradation, the policy docs are untouched" test_bump470_02_versioning_policy_docs_unchanged

rm -f "$CHANGELOG_ENTRY" "$ENTRY_460"

echo ""
echo "$pass_count passed, $fail_count failed (see 06-bump470.feature)"
[ "$fail_count" -eq 0 ]
