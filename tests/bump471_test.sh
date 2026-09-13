#!/usr/bin/env bash
# Unit tests for the bump layer of change style-rewrite
# (spdd/changes/style-rewrite/07-bump471.feature, scenarios
# bump471-01..02): the mandated patch VERSION bump to 4.7.1 and the matching
# dated CHANGELOG.md entry layered above [4.7.0], describing the style
# rewrite with semantics intact: the mirror clause stated exactly once in
# each of the four prompts, the four long sentences broken into short lists
# (the coder's closing-block bullet folded into "## Receipt", the
# orchestrator's rejected_count=1 row, the dedup guard, the verifier's
# REJECTED.md entry), the specifier's triple negation replaced by the
# two-line table rule, the terminology unified (`<slug>`, one form per
# concept), the Working-Root triplication documented as an editing rule, and
# the test suites following the rewritten prose loudly with every new
# working-vs-HEAD window born gated on the change_pending pattern.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/bump470_test.sh and its predecessors bump460/bump450/bump440 (the
# recorded precedent, merged from change precision-gaps into
# spdd/specs/versioning.md).
# Run:
#   ./tests/bump471_test.sh
#
# VERSION is NOT pinned as a byte-exact literal (the recorded lesson from
# tests/docs-bump_test.sh: a cross-change pin breaks on the next legitimate
# bump). The tests assert the '## [4.7.1] - <date>' section exists and sits
# above the [4.7.0]-lineage in the file's entry style, and that VERSION is a
# semver agreeing with the newest (topmost) CHANGELOG entry -- which together
# pin "VERSION reads exactly 4.7.1" today -- with one trailing newline as the
# file's only content. The [4.7.0]-down tail is pinned byte-identical to git
# HEAD, so stacking [4.7.1] on top keeps every older suite's own-section
# assertions stable.
#
# Stacking lesson applied to THIS suite (bump470's own header precedent):
# only the RELATIVE order ([4.7.1] above [4.7.0] above [4.6.0]) is pinned,
# plus the agreement check -- so the next legitimate bump can stack above
# [4.7.1] without breaking these tests, and no unconditional topmost pin is
# born here that a future entry would have to retire.
#
# The install.sh-untouched, agents/meta-untouched and no-v4.7.1-tag guards
# are gated on the bump being uncommitted (the flow's state): once the human
# makes the bump commit (and may tag v4.7.1 against it -- tagging is the
# human's commit-time follow-up, never a role's), they retire vacuously with
# a loud note, same convention as tests/bump440/450/460_test.sh as applied
# in commit 864d2a8 (the diff counts as THIS change's only while HEAD does
# not yet carry the [4.7.1] entry, so a later legitimate bump never
# resurrects them). The gate's lifecycle is exercised against a throwaway
# scratch repo so the pending and committed states are both observed without
# this suite ever touching the real working tree.
#
# The e2e-style ids (spdd/changes/style-rewrite/e2e-qa.feature) are the
# change's verifier-owned end-to-end QA suite -- not this unit suite; they
# are not stubbed here (the 07 sub-spec declares only bump471-01/02; the
# e2e layer owns its ids).
#
# Skills activated for this session: tdd (red -> green per scenario slice;
# expected strings derive from the sub-spec's text, never re-derived from
# the entry under test). No skill covers VERSION/CHANGELOG.md bookkeeping or
# this repo's bash test harness style.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"
INSTALL_SH="$SCRIPT_DIR/install.sh"
SUITE_SRC="$SCRIPT_DIR/tests/bump471_test.sh"

pass_count=0
fail_count=0

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

# This change's CHANGELOG entry: the [4.7.1] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry can never satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.7\.1\]/,/^## \[/{/^## \[4\.7\.1\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# The [4.7.0] section (the previous newest entry), for the "still describes
# its changes" half of the immutability assertion.
ENTRY_470=$(mktemp)
sed -n '/^## \[4\.7\.0\]/,/^## \[/{/^## \[4\.7\.0\]/d;p}' "$CHANGELOG_MD" > "$ENTRY_470"

line_471() {
  grep -nE '^## \[4\.7\.1\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_470() {
  grep -nF '## [4.7.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_460() {
  grep -nF '## [4.6.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}

change_pending() {
  # True while this change's bump artifacts are uncommitted in the working
  # tree (the flow's state -- no role ever commits): the tree differs from
  # HEAD on CHANGELOG.md/VERSION AND HEAD does not yet carry the [4.7.1]
  # entry. The conjunction is the recorded stacking lesson (bump440/450/
  # bump460 as applied in commit 864d2a8): a later legitimate bump would
  # also make the tree differ from HEAD, and must not resurrect these
  # guards against the human's own v4.7.1 tag -- so the diff counts as
  # THIS change's only while HEAD lacks the entry. Once the human's bump
  # commit lands, the gated guards retire vacuously with a loud note. The
  # lifecycle test below exercises this exact function against a throwaway
  # scratch repo, so the pending and committed states are both observed
  # without this suite ever touching the real working tree.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- CHANGELOG.md VERSION 2>/dev/null \
    && ! git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null | grep -q '^## \[4\.7\.1\]'
}

# =============================================================================
# bump471-01: the bump is present -- VERSION reads 4.7.1 (value plus one
# trailing newline, its only content, phrased as agreement with the newest
# topmost entry per the repo's recorded lesson), CHANGELOG.md carries exactly
# one dated '## [4.7.1] - <date>' section above [4.7.0] in the file's entry
# style describing the style rewrite (mirror clause once per prompt, the four
# long sentences broken into short lists, the two-line table rule, the
# unified terminology, the documented triplication rule, the suites
# following), the entry states the patch grade and its justification, and
# every entry from [4.7.0] down is byte-for-byte unchanged.
# =============================================================================

test_bump471_01_version_agrees_with_newest_entry() {
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

test_bump471_01_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_bump471_01_471_section_dated_above_470() {
  ok=0
  l71="$(line_471)"
  l70="$(line_470)"
  l60="$(line_460)"
  [ -n "$l71" ] || { echo "  CHANGELOG.md has no dated '## [4.7.1] - YYYY-MM-DD' heading"; ok=1; }
  [ -n "$l70" ] || { echo "  missing '## [4.7.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l60" ] || { echo "  missing '## [4.6.0]' in CHANGELOG.md"; ok=1; }
  # Exactly one [4.7.1] heading.
  n=$(grep -cF '## [4.7.1]' "$CHANGELOG_MD")
  [ "$n" -eq 1 ] || { echo "  '## [4.7.1]' appears $n times, expected exactly 1"; ok=1; }
  # Relative ordering only -- deliberately no unconditional "nothing sits
  # above [4.7.1]" topmost pin (the stacking lesson; this suite's header
  # records why). The agreement test above keeps "VERSION reads exactly
  # 4.7.1" pinned today.
  if [ -n "$l71" ] && [ -n "$l70" ] && [ "$l71" -ge "$l70" ]; then
    echo "  '## [4.7.1]' does not sit above '## [4.7.0]'"; ok=1
  fi
  if [ -n "$l70" ] && [ -n "$l60" ] && [ "$l70" -ge "$l60" ]; then
    echo "  '## [4.7.0]' no longer sits above '## [4.6.0]'"; ok=1
  fi
  # The Keep-a-Changelog statement and the file's preamble survive intact too.
  require "$CHANGELOG_MD" '[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)' || ok=1
  return $ok
}

test_bump471_01_entry_uses_existing_style() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  # The file's entry style: category headings with bold lead-in bullets.
  require "$CHANGELOG_ENTRY" '### Changed' || ok=1
  require "$CHANGELOG_ENTRY" '- **' || ok=1
  return $ok
}

test_bump471_01_entry_describes_mirror_clause_once_per_prompt() {
  # The mirror clause stated once per prompt (sub-spec 07's entry list,
  # item 1; the quoted clause strings are the change's shared contract).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'mirror clause' || ok=1
  require "$CHANGELOG_ENTRY" 'stated exactly once in each of the four prompts' || ok=1
  require "$CHANGELOG_ENTRY" 'The block is a mirror only' || ok=1
  require "$CHANGELOG_ENTRY" 'the receipt is the authority' || ok=1
  return $ok
}

test_bump471_01_entry_describes_the_four_short_lists() {
  # The four long sentences broken into short lists (sub-spec 07's entry
  # list, item 2), naming all four sites.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'became short lists' || ok=1
  require "$CHANGELOG_ENTRY" 'closing-block bullet' || ok=1
  require "$CHANGELOG_ENTRY" '## Receipt' || ok=1
  require "$CHANGELOG_ENTRY" 'rejected_count=1' || ok=1
  require "$CHANGELOG_ENTRY" 'dedup guard' || ok=1
  require "$CHANGELOG_ENTRY" 'REJECTED.md entry' || ok=1
  return $ok
}

test_bump471_01_entry_describes_the_two_line_table_rule() {
  # The specifier's triple negation replaced by the two-line table rule
  # (sub-spec 07's entry list, item 3).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'triple negation' || ok=1
  require "$CHANGELOG_ENTRY" 'two-line table rule' || ok=1
  return $ok
}

test_bump471_01_entry_describes_terminology_unified() {
  # The terminology unified: `<change-slug>` -> `<slug>`, one form per
  # concept (sub-spec 07's entry list, item 4).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '<change-slug>' || ok=1
  require "$CHANGELOG_ENTRY" '<slug>' || ok=1
  require "$CHANGELOG_ENTRY" 'one form per concept' || ok=1
  return $ok
}

test_bump471_01_entry_describes_triplication_rule() {
  # The Working-Root triplication documented as an editing rule, in both
  # docs, pinned by a test (sub-spec 07's entry list, item 5).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'Working-Root triplication' || ok=1
  require "$CHANGELOG_ENTRY" '## Working Root' || ok=1
  require "$CHANGELOG_ENTRY" 'all three sites' || ok=1
  require "$CHANGELOG_ENTRY" 'AGENTS.md and CLAUDE.md' || ok=1
  require "$CHANGELOG_ENTRY" 'pinned by a test' || ok=1
  return $ok
}

test_bump471_01_entry_describes_the_suites_following_loudly() {
  # The test suites follow the rewritten prose, every new diff-window
  # assertion born gated on the change_pending pattern (sub-spec 07's
  # invariant "no new diff-window assertion is born ungated", stated in the
  # entry per the change's README goal bullet).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'test suites followed' || ok=1
  require "$CHANGELOG_ENTRY" 'born gated' || ok=1
  require "$CHANGELOG_ENTRY" 'change_pending' || ok=1
  return $ok
}

test_bump471_01_entry_grades_patch_with_justification() {
  # The entry states the grade and its justification (sub-spec 07,
  # bump471-01's grade clause): patch -- wording only, no behavior change;
  # not minor; not major.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'grades as **patch**' || ok=1
  require "$CHANGELOG_ENTRY" 'wording only, no behavior change' || ok=1
  require "$CHANGELOG_ENTRY" 'not minor' || ok=1
  require "$CHANGELOG_ENTRY" 'no capability change' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered-surface change' || ok=1
  require "$CHANGELOG_ENTRY" 'detection change' || ok=1
  require "$CHANGELOG_ENTRY" 'not major' || ok=1
  return $ok
}

test_bump471_01_entry_names_the_surviving_surface() {
  # The not-major half states the survivors concretely (sub-spec 07,
  # bump471-01's grade clause): the workflow contract, the machine-line
  # formats, the closing-block vocabularies, the latch/dedup contracts.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'machine-line format' || ok=1
  require "$CHANGELOG_ENTRY" 'closing-block vocabularies' || ok=1
  require "$CHANGELOG_ENTRY" 'latch/dedup contract' || ok=1
  require "$CHANGELOG_ENTRY" 'text only' || ok=1
  return $ok
}

test_bump471_01_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [4.7.0] - 2026-09-13' || ok=1
  l70="$(line_470)"
  l60="$(line_460)"
  [ -n "$l70" ] || { echo "  missing '## [4.7.0]' in CHANGELOG.md"; ok=1; }
  [ -n "$l60" ] || { echo "  missing '## [4.6.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l70" ] && [ -n "$l60" ] && [ "$l70" -ge "$l60" ]; then
    echo "  '## [4.7.0]' no longer sits above '## [4.6.0]'"; ok=1
  fi
  # [4.7.0] still describes its own changes (its distinguishing bullets).
  [ -s "$ENTRY_470" ] || { echo "  CHANGELOG.md has no [4.7.0] section"; ok=1; }
  require "$ENTRY_470" 'line-start header comment' || ok=1
  require "$ENTRY_470" 'ANTZ_REF' || ok=1
  # The immutable-history tail: everything from [4.7.0] down equals HEAD's.
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[4\.7\.0\]/,$p' > "$ENTRY_470.head"
    sed -n '/^## \[4\.7\.0\]/,$p' "$CHANGELOG_MD" > "$ENTRY_470.work"
    cmp -s "$ENTRY_470.head" "$ENTRY_470.work" \
      || { echo "  CHANGELOG.md's entries from [4.7.0] down differ from git HEAD's (older entries are immutable history)"; ok=1; }
    rm -f "$ENTRY_470.head" "$ENTRY_470.work"
  fi
  return $ok
}

# =============================================================================
# bump471-02: the working-vs-HEAD guards are born gated on change_pending
# (enforced while the bump is pending, retired vacuously with a loud note
# once the human's bump commit lands, never resurrecting against a later
# legitimate bump), and the no-commit law holds: the suite never commits,
# never tags, and never mutates the working tree, so it exits 0 in both the
# pending and the committed state.
# =============================================================================

test_bump471_02_entry_states_untouched_survivors_and_no_role_tags() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'agents/meta/*' || ok=1
  require "$CHANGELOG_ENTRY" 'install.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'byte-unchanged' || ok=1
  require "$CHANGELOG_ENTRY" 'byte-identical to git HEAD' || ok=1
  require "$CHANGELOG_ENTRY" './install.sh --all' || ok=1
  require "$CHANGELOG_ENTRY" 'no role creates the `v4.7.1` tag' || ok=1
  require "$CHANGELOG_ENTRY" "human's commit-time follow-up" || ok=1
  require "$CHANGELOG_ENTRY" "created against the human's bump commit" || ok=1
  require "$CHANGELOG_ENTRY" 'not pushed automatically' || ok=1
  return $ok
}

test_bump471_02_install_sh_and_agents_meta_byte_untouched_vs_head() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the install.sh/agents-meta-untouched guard is vacuously retired (a future change touching them must bump under the versioning rule anyway)"
    return 0
  fi
  ok=0
  head_copy=$(mktemp)
  if ! git -C "$SCRIPT_DIR" show HEAD:install.sh > "$head_copy" 2>/dev/null; then
    echo "  cannot read HEAD:install.sh"; rm -f "$head_copy"; return 1
  fi
  cmp -s "$head_copy" "$INSTALL_SH" \
    || { echo "  install.sh differs from git HEAD (the entire style change must leave it untouched; the bump reaches installed copies only through the user's later ./install.sh --all)"; ok=1; }
  rm -f "$head_copy"
  if ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- agents/meta 2>/dev/null; then
    echo "  agents/meta/ differs from git HEAD (the entire style change must leave it byte-unchanged)"; ok=1
  fi
  return $ok
}

test_bump471_02_no_v471_tag_created_while_uncommitted() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the no-tag guard is vacuously retired (v4.7.1 becomes the human's own commit-time follow-up, created against the human's bump commit and never pushed automatically)"
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" tag -l 'v4.7.1')" ]; then
    echo "  tag v4.7.1 already exists: no role may create it -- the local tag is the human's commit-time follow-up"
    return 1
  fi
  return 0
}

test_bump471_02_change_pending_gate_enforced_while_pending_and_retires_when_committed() {
  # The gate's full lifecycle, observed against a throwaway scratch repo --
  # the only place this suite writes with git, and it is not the working
  # tree. Four states: clean (off), bump pending (on), bump committed
  # (retired), and a LATER legitimate bump pending on top of a HEAD that
  # already carries [4.7.1] (off again -- the guards never resurrect).
  ok=0
  SCRATCH_REPO=$(mktemp -d) || return 1
  saved_SCRIPT_DIR=$SCRIPT_DIR
  printf '4.7.0\n' > "$SCRATCH_REPO/VERSION"
  printf '# Changelog\n\n## [4.7.0] - 2026-09-13\n\n### Changed\n- prior entry.\n' > "$SCRATCH_REPO/CHANGELOG.md"
  git -C "$SCRATCH_REPO" init -q
  git -C "$SCRATCH_REPO" add -A
  git -C "$SCRATCH_REPO" -c user.name=bump471-fixture -c user.email=bump471-fixture@invalid -c commit.gpgsign=false commit -q -m 'base: [4.7.0] committed, [4.7.1] nowhere'
  SCRIPT_DIR=$SCRATCH_REPO
  # State A: clean tree, HEAD without [4.7.1] -- nothing to guard, off.
  if change_pending; then
    echo "  state A (clean tree, no [4.7.1] in HEAD): the gate should be off"; ok=1
  fi
  # State B: this change's bump pending (the flow's state) -- on, enforced.
  printf '4.7.1\n' > "$SCRATCH_REPO/VERSION"
  printf '# Changelog\n\n## [4.7.1] - 2026-09-13\n\n### Changed\n- this change.\n\n## [4.7.0] - 2026-09-13\n\n### Changed\n- prior entry.\n' > "$SCRATCH_REPO/CHANGELOG.md"
  if ! change_pending; then
    echo "  state B (bump pending, HEAD without [4.7.1]): the gate should be on"; ok=1
  fi
  # State C: the human's bump commit lands -- retired vacuously, off.
  git -C "$SCRATCH_REPO" add -A
  git -C "$SCRATCH_REPO" -c user.name=bump471-fixture -c user.email=bump471-fixture@invalid -c commit.gpgsign=false commit -q -m 'the human bump commit lands (and may tag v4.7.1)'
  if change_pending; then
    echo "  state C (bump committed): the gate should have retired"; ok=1
  fi
  # State D: a LATER legitimate bump pending on top -- must NOT resurrect.
  printf '4.8.0\n' > "$SCRATCH_REPO/VERSION"
  printf '# Changelog\n\n## [4.8.0] - 2026-09-14\n\n### Changed\n- a later change.\n\n## [4.7.1] - 2026-09-13\n\n### Changed\n- this change.\n\n## [4.7.0] - 2026-09-13\n\n### Changed\n- prior entry.\n' > "$SCRATCH_REPO/CHANGELOG.md"
  if change_pending; then
    echo "  state D (a later bump pending on top of a HEAD that carries [4.7.1]): the gate must never resurrect"; ok=1
  fi
  SCRIPT_DIR=$saved_SCRIPT_DIR
  rm -rf "$SCRATCH_REPO"
  return $ok
}

test_bump471_02_suite_never_commits_tags_or_mutates_the_working_tree() {
  # The no-commit law, pinned on this suite's own source: every git
  # invocation against the real repo is a read-only inspection
  # (diff/show/tag -l), and every git invocation carries an explicit -C
  # target so nothing can ever inherit the cwd and touch the working tree
  # by accident. Writes appear only against the scratch repo in the
  # lifecycle test above -- a throwaway directory, not the working tree.
  ok=0
  [ -f "$SUITE_SRC" ] || { echo "  cannot locate this suite's source at $SUITE_SRC"; return 1; }
  while IFS= read -r line; do
    cmd=$(printf '%s\n' "$line" | sed 's/.*git -C "[$]SCRIPT_DIR" //' | awk '{print $1}')
    case "$cmd" in
      diff|show) ;;
      tag) printf '%s\n' "$line" | grep -qF 'tag -l' \
             || { echo "  tag creation (no -l) against the real repo: $line"; ok=1; } ;;
      *) echo "  non-read-only git subcommand '$cmd' against the real repo: $line"; ok=1 ;;
    esac
  done <<GITLINES
$(grep -F 'git -C "$SCRIPT_DIR"' "$SUITE_SRC" | grep -vF "'git -C")
GITLINES
  # Prose strings like "matches git HEAD" are not invocations; only lines
  # where git is followed by an actual subcommand name are held to the
  # explicit-target rule.
  offenders=$(grep -v '^[[:space:]]*#' "$SUITE_SRC" \
    | grep -E '(^|[^-[:alnum:]])git (commit|init|add|branch|checkout|switch|reset|stash|merge|rebase|apply|tag|show|diff|status|remote|config|mv|rm|clean|worktree|update-index)([[:space:]]|$)' \
    | grep -v -- '-C ' || true)
  if [ -n "$offenders" ]; then
    echo "  git invocations without an explicit -C target (they could mutate the real working tree):"
    printf '%s\n' "$offenders"
    ok=1
  fi
  return $ok
}

# ---- run everything -----------------------------------------------------------

run_test "bump471-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_bump471_01_version_agrees_with_newest_entry
run_test "bump471-01: VERSION's only content is the version value with one trailing newline" test_bump471_01_version_newline_terminated_only_content
run_test "bump471-01: CHANGELOG.md carries exactly one dated '## [4.7.1] - YYYY-MM-DD' section sitting above the [4.7.0] section which stays above [4.6.0] (relative ordering only -- the stacking lesson), Keep-a-Changelog statement intact" test_bump471_01_471_section_dated_above_470
run_test "bump471-01: the [4.7.1] section uses the file's existing entry style -- category headings with bold lead-in bullets" test_bump471_01_entry_uses_existing_style
run_test "bump471-01: the [4.7.1] entry describes the mirror clause stated exactly once in each of the four prompts, quoting the clause itself" test_bump471_01_entry_describes_mirror_clause_once_per_prompt
run_test "bump471-01: the [4.7.1] entry describes the four long sentences that became short lists -- the coder's closing-block bullet folded into ## Receipt, the orchestrator's rejected_count=1 row, the dedup guard, the verifier's REJECTED.md entry" test_bump471_01_entry_describes_the_four_short_lists
run_test "bump471-01: the [4.7.1] entry describes the specifier's triple negation replaced by the two-line table rule" test_bump471_01_entry_describes_the_two_line_table_rule
run_test "bump471-01: the [4.7.1] entry describes the terminology unified -- <change-slug> to <slug>, one form per concept" test_bump471_01_entry_describes_terminology_unified
run_test "bump471-01: the [4.7.1] entry describes the Working-Root triplication documented as an editing rule in AGENTS.md and CLAUDE.md and pinned by a test" test_bump471_01_entry_describes_triplication_rule
run_test "bump471-01: the [4.7.1] entry describes the test suites following the prose, every new working-vs-HEAD window born gated on change_pending" test_bump471_01_entry_describes_the_suites_following_loudly
run_test "bump471-01: the [4.7.1] entry grades patch with the versioning-table justification -- wording only, no behavior change; not minor (no capability, rendered-surface, or detection change); not major" test_bump471_01_entry_grades_patch_with_justification
run_test "bump471-01: the [4.7.1] entry names the surviving surface concretely -- the workflow contract, the machine-line formats, the closing-block vocabularies, and the latch/dedup contracts all survive" test_bump471_01_entry_names_the_surviving_surface
run_test "bump471-01: the [4.7.0] section and every entry below it are byte-for-byte unchanged -- still above [4.6.0] still describing its changes, and the [4.7.0]-down tail matches git HEAD" test_bump471_01_earlier_entries_byte_untouched

run_test "bump471-02: the [4.7.1] entry states agents/meta/* and install.sh are byte-unchanged (the bump reaches installed copies only through the user's later ./install.sh --all) and no role creates the v4.7.1 tag -- it is the human's commit-time follow-up, created against the bump commit and not pushed automatically" test_bump471_02_entry_states_untouched_survivors_and_no_role_tags
run_test "bump471-02: install.sh and agents/meta are byte-identical to git HEAD while the bump is uncommitted -- the guard is gated on change_pending and retires with a loud note after the human's commit" test_bump471_02_install_sh_and_agents_meta_byte_untouched_vs_head
run_test "bump471-02: no v4.7.1 tag exists while the bump is uncommitted -- no role tags; it is the human's commit-time follow-up, gated on change_pending (retires after the human's commit)" test_bump471_02_no_v471_tag_created_while_uncommitted
run_test "bump471-02: the change_pending gate is exercised on a throwaway scratch repo through its whole lifecycle -- off when clean, enforced while the bump is pending, retired vacuously once the human's bump commit lands, and never resurrected by a later legitimate bump (the suite exits 0 in both the pending and the committed state)" test_bump471_02_change_pending_gate_enforced_while_pending_and_retires_when_committed
run_test "bump471-02: the suite itself never commits, never tags, and never mutates the working tree -- every git invocation against the real repo is diff/show/tag-l, and every git invocation carries an explicit -C target" test_bump471_02_suite_never_commits_tags_or_mutates_the_working_tree

rm -f "$CHANGELOG_ENTRY" "$ENTRY_470"

echo ""
echo "$pass_count passed, $fail_count failed (see 07-bump471.feature)"
[ "$fail_count" -eq 0 ]
