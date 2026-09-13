#!/usr/bin/env bash
# Unit tests for the bump layer of change deembed-orchestration-scripts
# (spdd/changes/deembed-orchestration-scripts/06-versionbump.feature,
# scenarios versionbump-01..03): the mandated minor VERSION bump to 4.8.0 and
# the matching dated CHANGELOG.md entry layered above [4.7.1], describing the
# de-embedding with semantics intact: the four scripts installed as files
# under the resolved ${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/ libdir
# (marker, backup, --check), the orchestrator prompt and both /antz-set-model
# command bodies invoking the installed scripts by their resolved paths with
# zero re-materialization, inject_includes() and the "# antz-include:" markers
# retired with the antz-skills.sh fence-indent carve-out, the set-model
# script's required client first argument and internal agents-dir resolution,
# --check extended to the installed scripts, the AGENTS.md/CLAUDE.md law and
# docs/orchestrator.md updated, the expected cache effect (~483 rendered lines
# -> ~150, per-session re-materialization -> zero), the grade stated as minor
# with the "install locations" clause addressed head-on, and the single-bump
# coverage of the whole change including its docs-only and tests-only parts.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style of
# tests/bump471_test.sh and its predecessors bump470/460/450/440 (the recorded
# precedent, merged from change style-rewrite into spdd/specs/versioning.md).
# Run:
#   ./tests/bump480_test.sh
#
# VERSION is NOT pinned as a byte-exact literal (the recorded lesson from
# tests/docs-bump_test.sh: a cross-change pin breaks on the next legitimate
# bump). The tests assert the '## [4.8.0] - <date>' section exists and sits
# above the [4.7.1]-lineage in the file's entry style, and that VERSION is a
# semver agreeing with the newest (topmost) CHANGELOG entry -- which together
# pin "VERSION reads exactly 4.8.0" today -- with one trailing newline as the
# file's only content. The [4.7.1]-down tail is pinned byte-identical to git
# HEAD, so stacking [4.8.0] on top keeps every older suite's own-section
# assertions stable.
#
# Stacking lesson applied to THIS suite (bump470/471's own header precedent):
# only the RELATIVE order ([4.8.0] above [4.7.1] above [4.7.0]) is pinned,
# plus the agreement check -- so the next legitimate bump can stack above
# [4.8.0] without breaking these tests, and no unconditional topmost pin is
# born here that a future entry would have to retire.
#
# The no-v4.8.0-tag guard and the "exactly one new entry above [4.7.1]"
# counting guard are gated on the bump being uncommitted (the flow's state):
# once the human makes the bump commit (and may tag v4.8.0 against it --
# tagging is the human's commit-time follow-up, never a role's), they retire
# vacuously with a loud note, same convention as tests/bump440/450/460/470/
# 471_test.sh as applied in commit 864d2a8 (the diff counts as THIS change's
# only while HEAD does not yet carry the [4.8.0] entry, so a later legitimate
# bump never resurrects them). The gate's lifecycle is exercised against a
# throwaway scratch repo so the pending and committed states are both observed
# without this suite ever touching the real working tree.
#
# The e2e-style ids (spdd/changes/deembed-orchestration-scripts/e2e-qa.feature)
# are the change's verifier-owned end-to-end QA suite -- not this unit suite;
# they are not stubbed here (the 06 sub-spec declares only versionbump-01/02/
# 03; the e2e layer owns its ids).
#
# Skills activated for this session: none matched (the delegation carried an
# explicit "Skills: none matched" resolution; no available skill covers
# VERSION/CHANGELOG.md bookkeeping or this repo's bash test harness style).

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
CHANGELOG_MD="$SCRIPT_DIR/CHANGELOG.md"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
SUITE_SRC="$SCRIPT_DIR/tests/bump480_test.sh"

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

# This change's CHANGELOG entry: the [4.8.0] section alone (heading down to,
# excluding, the next '## [' heading). Content tests grep this extract, so a
# stray phrase in an older entry can never satisfy this change's assertions.
CHANGELOG_ENTRY=$(mktemp)
sed -n '/^## \[4\.8\.0\]/,/^## \[/{/^## \[4\.8\.0\]/d;p}' "$CHANGELOG_MD" > "$CHANGELOG_ENTRY"

# The [4.7.1] section (the previous newest entry), for the "still describes
# its changes" half of the immutability assertion.
ENTRY_471=$(mktemp)
sed -n '/^## \[4\.7\.1\]/,/^## \[/{/^## \[4\.7\.1\]/d;p}' "$CHANGELOG_MD" > "$ENTRY_471"

# Each doc's "## Versioning" section, for the policy clause versionbump-03
# leans on (the docs-only no-bump rule that covers this change's docs/tests
# parts).
AGENTS_VSECTION=$(mktemp)
CLAUDE_VSECTION=$(mktemp)
sed -n '/^## Versioning$/,$p' "$AGENTS_MD" > "$AGENTS_VSECTION"
sed -n '/^## Versioning$/,$p' "$CLAUDE_MD" > "$CLAUDE_VSECTION"

line_480() {
  grep -nE '^## \[4\.8\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_471() {
  grep -nF '## [4.7.1]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}
line_470() {
  grep -nF '## [4.7.0]' "$CHANGELOG_MD" | head -n 1 | cut -d: -f1
}

newest_entry_version() {
  sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$CHANGELOG_MD" | head -n 1
}

change_pending() {
  # True while this change's bump artifacts are uncommitted in the working
  # tree (the flow's state -- no role ever commits): the tree differs from
  # HEAD on CHANGELOG.md/VERSION AND HEAD does not yet carry the [4.8.0]
  # entry. The conjunction is the recorded stacking lesson (bump440/450/
  # bump460 as applied in commit 864d2a8): a later legitimate bump would
  # also make the tree differ from HEAD, and must not resurrect these
  # guards against the human's own v4.8.0 tag -- so the diff counts as
  # THIS change's only while HEAD lacks the entry. Once the human's bump
  # commit lands, the gated guards retire vacuously with a loud note. The
  # lifecycle test below exercises this exact function against a throwaway
  # scratch repo, so the pending and committed states are both observed
  # without this suite ever touching the real working tree.
  ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- CHANGELOG.md VERSION 2>/dev/null \
    && ! git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null | grep -q '^## \[4\.8\.0\]'
}

# =============================================================================
# versionbump-01: the bump is present -- VERSION reads 4.8.0 (value plus one
# trailing newline, its only content, phrased as agreement with the newest
# topmost entry per the repo's recorded lesson), CHANGELOG.md carries exactly
# one dated '## [4.8.0] - <date>' section above [4.7.1] in the file's entry
# style describing the change's substance (the four libdir scripts with
# marker/backup/--check, invocation by resolved path with zero
# re-materialization, inject_includes() and the include markers retired with
# the fence-indent carve-out, the set-model client argument and internal
# agents-dir resolution, --check extended, the docs law updated, and the
# expected cache effect), and every entry from [4.7.1] down is byte-for-byte
# unchanged.
# =============================================================================

test_versionbump_01_version_agrees_with_newest_entry() {
  ok=0
  version=$(cat "$VERSION_FILE")
  printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "  VERSION reads '$version', not a semver (X.Y.Z)"; ok=1; }
  newest=$(newest_entry_version)
  if [ -z "$newest" ]; then
    echo "  CHANGELOG.md has no '## [...]' entry headings"; ok=1
  elif [ "$version" != "$newest" ]; then
    echo "  VERSION reads '$version' but the newest CHANGELOG entry is '$newest'"
    ok=1
  fi
  return $ok
}

test_versionbump_01_version_newline_terminated_only_content() {
  # VERSION's only content is the version value with one trailing newline.
  printf '%s\n' "$(cat "$VERSION_FILE")" | cmp -s - "$VERSION_FILE" \
    || { echo "  VERSION is not exactly '<version>\\n'"; return 1; }
  return 0
}

test_versionbump_01_480_section_dated_above_471() {
  ok=0
  l80="$(line_480)"
  l71="$(line_471)"
  l70="$(line_470)"
  [ -n "$l80" ] || { echo "  CHANGELOG.md has no dated '## [4.8.0] - YYYY-MM-DD' heading"; ok=1; }
  [ -n "$l71" ] || { echo "  missing '## [4.7.1]' in CHANGELOG.md"; ok=1; }
  [ -n "$l70" ] || { echo "  missing '## [4.7.0]' in CHANGELOG.md"; ok=1; }
  # Exactly one [4.8.0] heading.
  n=$(grep -cF '## [4.8.0]' "$CHANGELOG_MD")
  [ "$n" -eq 1 ] || { echo "  '## [4.8.0]' appears $n times, expected exactly 1"; ok=1; }
  # Relative ordering only -- deliberately no unconditional "nothing sits
  # above [4.8.0]" topmost pin (the stacking lesson; this suite's header
  # records why). The agreement test above keeps "VERSION reads exactly
  # 4.8.0" pinned today.
  if [ -n "$l80" ] && [ -n "$l71" ] && [ "$l80" -ge "$l71" ]; then
    echo "  '## [4.8.0]' does not sit above '## [4.7.1]'"; ok=1
  fi
  if [ -n "$l71" ] && [ -n "$l70" ] && [ "$l71" -ge "$l70" ]; then
    echo "  '## [4.7.1]' no longer sits above '## [4.7.0]'"; ok=1
  fi
  # The Keep-a-Changelog statement and the file's preamble survive intact too.
  require "$CHANGELOG_MD" '[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)' || ok=1
  return $ok
}

test_versionbump_01_entry_uses_existing_style() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  # The file's entry style: category headings with bold lead-in bullets.
  require "$CHANGELOG_ENTRY" '### Added' || ok=1
  require "$CHANGELOG_ENTRY" '### Changed' || ok=1
  require "$CHANGELOG_ENTRY" '- **' || ok=1
  return $ok
}

test_versionbump_01_entry_describes_the_four_libdir_scripts() {
  # The four scripts installed as files under the resolved libdir, with
  # marker, backup, and --check reporting (sub-spec 06's entry list, item 1).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/' || ok=1
  require "$CHANGELOG_ENTRY" 'installed as files' || ok=1
  require "$CHANGELOG_ENTRY" 'antz-flow.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'antz-probe.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'antz-skills.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'antz-set-model.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'marker' || ok=1
  require "$CHANGELOG_ENTRY" 'backup' || ok=1
  return $ok
}

test_versionbump_01_entry_describes_invocation_by_resolved_path() {
  # The orchestrator prompt and both /antz-set-model command bodies invoke the
  # installed scripts by their resolved paths with zero script
  # re-materialization (sub-spec 06's entry list, item 2).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'orchestrator prompt' || ok=1
  require "$CHANGELOG_ENTRY" '/antz-set-model command bodies' || ok=1
  require "$CHANGELOG_ENTRY" 'invoking the installed scripts by their resolved paths' || ok=1
  require "$CHANGELOG_ENTRY" 'zero script re-materialization' || ok=1
  require "$CHANGELOG_ENTRY" '__ANTZ_SCRIPTS_DIR__' || ok=1
  return $ok
}

test_versionbump_01_entry_describes_the_embed_machinery_retired() {
  # inject_includes() and the "# antz-include:" markers retired along with the
  # antz-skills.sh fence-indent carve-out (sub-spec 06's entry list, item 3).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'inject_includes()' || ok=1
  require "$CHANGELOG_ENTRY" '# antz-include:' || ok=1
  require "$CHANGELOG_ENTRY" 'retired' || ok=1
  require "$CHANGELOG_ENTRY" 'fence-indent carve-out' || ok=1
  return $ok
}

test_versionbump_01_entry_describes_set_model_client_argument() {
  # The set-model script's required client first argument and internal
  # agents-dir resolution (sub-spec 06's entry list, item 4).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'required client first argument' || ok=1
  require "$CHANGELOG_ENTRY" 'internal agents-dir resolution' || ok=1
  return $ok
}

test_versionbump_01_entry_describes_check_extended() {
  # --check extended to the installed scripts (sub-spec 06's entry list,
  # item 5).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '--check' || ok=1
  require "$CHANGELOG_ENTRY" 'extended to the installed scripts' || ok=1
  return $ok
}

test_versionbump_01_entry_describes_docs_law_updated() {
  # The AGENTS.md/CLAUDE.md law and docs/orchestrator.md updated (sub-spec 06's
  # entry list, item 6).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'AGENTS.md and CLAUDE.md' || ok=1
  require "$CHANGELOG_ENTRY" 'docs/orchestrator.md' || ok=1
  return $ok
}

test_versionbump_01_entry_states_expected_cache_effect() {
  # The expected cache effect: the rendered orchestrator body from ~483 lines
  # to ~150, per-session script re-materialization to zero (sub-spec 06's
  # entry list, item 7 -- the change's whole point).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" '~483' || ok=1
  require "$CHANGELOG_ENTRY" '~150' || ok=1
  require "$CHANGELOG_ENTRY" 'per-session script re-materialization' || ok=1
  require "$CHANGELOG_ENTRY" 'zero' || ok=1
  return $ok
}

test_versionbump_01_earlier_entries_byte_untouched() {
  ok=0
  require "$CHANGELOG_MD" '## [4.7.1] - 2026-09-13' || ok=1
  l71="$(line_471)"
  l70="$(line_470)"
  [ -n "$l71" ] || { echo "  missing '## [4.7.1]' in CHANGELOG.md"; ok=1; }
  [ -n "$l70" ] || { echo "  missing '## [4.7.0]' in CHANGELOG.md"; ok=1; }
  if [ -n "$l71" ] && [ -n "$l70" ] && [ "$l71" -ge "$l70" ]; then
    echo "  '## [4.7.1]' no longer sits above '## [4.7.0]'"; ok=1
  fi
  # [4.7.1] still describes its own changes (its distinguishing bullets).
  [ -s "$ENTRY_471" ] || { echo "  CHANGELOG.md has no [4.7.1] section"; ok=1; }
  require "$ENTRY_471" 'stated exactly once in each of the four prompts' || ok=1
  require "$ENTRY_471" 'one form per concept' || ok=1
  # The immutable-history tail: everything from [4.7.1] down equals HEAD's.
  if head_changelog=$(git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null); then
    printf '%s\n' "$head_changelog" | sed -n '/^## \[4\.7\.1\]/,$p' > "$ENTRY_471.head"
    sed -n '/^## \[4\.7\.1\]/,$p' "$CHANGELOG_MD" > "$ENTRY_471.work"
    cmp -s "$ENTRY_471.head" "$ENTRY_471.work" \
      || { echo "  CHANGELOG.md's entries from [4.7.1] down differ from git HEAD's (older entries are immutable history)"; ok=1; }
    rm -f "$ENTRY_471.head" "$ENTRY_471.work"
  fi
  return $ok
}

# =============================================================================
# versionbump-02: the grade is minor, stated explicitly (rendered bodies and
# install mechanics change -- not the wording-only patch), with the "install
# locations" clause of the grading table addressed head-on (workflow contract,
# machine-line vocabulary, marker format, access model and the twelve
# client-file install paths unchanged; the libdir an additional shared
# location no consumer breaks on, per the 4.3.0 explicit-adjacency-note
# precedent), and with the v4.8.0 tag named the human's commit-time follow-up
# that no role creates. The working-vs-HEAD guards are born gated on
# change_pending and the suite never commits, tags, or mutates the tree.
# =============================================================================

test_versionbump_02_entry_grades_minor_explicitly() {
  # The grade stated, and justified as a behavior change rather than the
  # wording-only patch (sub-spec 06, versionbump-02's first clause).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'grades as **minor**' || ok=1
  require "$CHANGELOG_ENTRY" 'not patch and not major' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered' || ok=1
  require "$CHANGELOG_ENTRY" 'install mechanics change' || ok=1
  require "$CHANGELOG_ENTRY" 'behavior change' || ok=1
  require "$CHANGELOG_ENTRY" 'wording-only' || ok=1
  return $ok
}

test_versionbump_02_entry_addresses_install_locations_clause_head_on() {
  # The not-major half, addressing the grading table's "install locations"
  # clause by name (sub-spec 06, versionbump-02's second clause).
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'install locations' || ok=1
  require "$CHANGELOG_ENTRY" 'head-on' || ok=1
  require "$CHANGELOG_ENTRY" 'workflow contract' || ok=1
  require "$CHANGELOG_ENTRY" 'machine-line vocabulary' || ok=1
  require "$CHANGELOG_ENTRY" '`antz:generated` marker format' || ok=1
  require "$CHANGELOG_ENTRY" 'access model' || ok=1
  require "$CHANGELOG_ENTRY" 'twelve client-file install paths' || ok=1
  require "$CHANGELOG_ENTRY" 'additional install location shared by both clients' || ok=1
  require "$CHANGELOG_ENTRY" 'no existing consumer breaks' || ok=1
  return $ok
}

test_versionbump_02_entry_cites_the_430_adjacency_precedent() {
  # The precedent the note leans on: the same explicit-adjacency-note form the
  # 4.3.0 entry used for its own render-contract adjacency.
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'explicit-adjacency-note precedent as the 4.3.0 entry' || ok=1
  return $ok
}

test_versionbump_02_entry_states_the_tag_is_the_humans_follow_up() {
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'no role creates the `v4.8.0` tag' || ok=1
  require "$CHANGELOG_ENTRY" "human's commit-time follow-up" || ok=1
  require "$CHANGELOG_ENTRY" "created against the human's bump commit" || ok=1
  require "$CHANGELOG_ENTRY" 'not pushed automatically' || ok=1
  return $ok
}

test_versionbump_02_no_v480_tag_created_while_uncommitted() {
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the no-tag guard is vacuously retired (v4.8.0 becomes the human's own commit-time follow-up, created against the human's bump commit and never pushed automatically)"
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" tag -l 'v4.8.0')" ]; then
    echo "  tag v4.8.0 already exists: no role may create it -- the local tag is the human's commit-time follow-up"
    return 1
  fi
  return 0
}

test_versionbump_02_change_pending_gate_enforced_while_pending_and_retires_when_committed() {
  # The gate's full lifecycle, observed against a throwaway scratch repo --
  # the only place this suite writes with git, and it is not the working
  # tree. Four states: clean (off), bump pending (on), bump committed
  # (retired), and a LATER legitimate bump pending on top of a HEAD that
  # already carries [4.8.0] (off again -- the guards never resurrect).
  ok=0
  SCRATCH_REPO=$(mktemp -d) || return 1
  saved_SCRIPT_DIR=$SCRIPT_DIR
  printf '4.7.1\n' > "$SCRATCH_REPO/VERSION"
  printf '# Changelog\n\n## [4.7.1] - 2026-09-13\n\n### Changed\n- prior entry.\n' > "$SCRATCH_REPO/CHANGELOG.md"
  git -C "$SCRATCH_REPO" init -q
  git -C "$SCRATCH_REPO" add -A
  git -C "$SCRATCH_REPO" -c user.name=bump480-fixture -c user.email=bump480-fixture@invalid -c commit.gpgsign=false commit -q -m 'base: [4.7.1] committed, [4.8.0] nowhere'
  SCRIPT_DIR=$SCRATCH_REPO
  # State A: clean tree, HEAD without [4.8.0] -- nothing to guard, off.
  if change_pending; then
    echo "  state A (clean tree, no [4.8.0] in HEAD): the gate should be off"; ok=1
  fi
  # State B: this change's bump pending (the flow's state) -- on, enforced.
  printf '4.8.0\n' > "$SCRATCH_REPO/VERSION"
  printf '# Changelog\n\n## [4.8.0] - 2026-09-13\n\n### Changed\n- this change.\n\n## [4.7.1] - 2026-09-13\n\n### Changed\n- prior entry.\n' > "$SCRATCH_REPO/CHANGELOG.md"
  if ! change_pending; then
    echo "  state B (bump pending, HEAD without [4.8.0]): the gate should be on"; ok=1
  fi
  # State C: the human's bump commit lands -- retired vacuously, off.
  git -C "$SCRATCH_REPO" add -A
  git -C "$SCRATCH_REPO" -c user.name=bump480-fixture -c user.email=bump480-fixture@invalid -c commit.gpgsign=false commit -q -m 'the human bump commit lands (and may tag v4.8.0)'
  if change_pending; then
    echo "  state C (bump committed): the gate should have retired"; ok=1
  fi
  # State D: a LATER legitimate bump pending on top -- must NOT resurrect.
  printf '4.9.0\n' > "$SCRATCH_REPO/VERSION"
  printf '# Changelog\n\n## [4.9.0] - 2026-09-14\n\n### Changed\n- a later change.\n\n## [4.8.0] - 2026-09-13\n\n### Changed\n- this change.\n\n## [4.7.1] - 2026-09-13\n\n### Changed\n- prior entry.\n' > "$SCRATCH_REPO/CHANGELOG.md"
  if change_pending; then
    echo "  state D (a later bump pending on top of a HEAD that carries [4.8.0]): the gate must never resurrect"; ok=1
  fi
  SCRIPT_DIR=$saved_SCRIPT_DIR
  rm -rf "$SCRATCH_REPO"
  return $ok
}

test_versionbump_02_suite_never_commits_tags_or_mutates_the_working_tree() {
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

# =============================================================================
# versionbump-03: one bump covers the whole change -- the single [4.8.0] entry
# names the orchestrator prompt edit, install.sh's mechanics change, the
# command files' rendered shape, and the docs/tests edits together; exactly one
# CHANGELOG entry was added versus HEAD (no second bump for any part); and the
# docs-only/tests-only clause of the still-unchanged policy is what covers
# those parts, so they need no entry of their own.
# =============================================================================

test_versionbump_03_single_entry_covers_every_component() {
  # One graded entry for the whole change (sub-spec 06, versionbump-03's
  # first clause): the prompt edit, install.sh's mechanics, the rendered
  # command shape, and the docs/tests edits all land in [4.8.0].
  ok=0
  [ -s "$CHANGELOG_ENTRY" ] || { echo "  CHANGELOG.md has no [4.8.0] section"; ok=1; }
  require "$CHANGELOG_ENTRY" 'orchestrator prompt' || ok=1
  require "$CHANGELOG_ENTRY" 'install.sh' || ok=1
  require "$CHANGELOG_ENTRY" 'rendered' || ok=1
  require "$CHANGELOG_ENTRY" 'command' || ok=1
  require "$CHANGELOG_ENTRY" 'AGENTS.md and CLAUDE.md' || ok=1
  require "$CHANGELOG_ENTRY" 'test suites' || ok=1
  return $ok
}

test_versionbump_03_exactly_one_new_entry_above_471() {
  # No additional bump: versus git HEAD the change adds exactly one '## [...]'
  # entry, and it is the one VERSION agrees with (the newest topmost). Gated
  # on change_pending, so it retires once the human's commit lands.
  if ! change_pending; then
    echo "  note: this change's bump artifacts are committed vs HEAD; the one-entry counting guard is vacuously retired"
    return 0
  fi
  ok=0
  head_list=$(mktemp)
  work_list=$(mktemp)
  if ! git -C "$SCRIPT_DIR" show HEAD:CHANGELOG.md 2>/dev/null | sed -n 's/^## \[\([^]]*\)\].*/\1/p' | sort > "$head_list"; then
    echo "  cannot read HEAD:CHANGELOG.md"; rm -f "$head_list" "$work_list"; return 1
  fi
  sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$CHANGELOG_MD" | sort > "$work_list"
  added=$(comm -13 "$head_list" "$work_list")
  n=$(printf '%s\n' "$added" | grep -c .)
  if [ "$n" -ne 1 ]; then
    echo "  $n new CHANGELOG entries vs git HEAD (a single bump adds exactly one): $(printf '%s' "$added" | tr '\n' ' ')"
    ok=1
  fi
  if [ -n "$added" ] && [ "$added" != "$(newest_entry_version)" ]; then
    echo "  the single new entry '$added' is not the newest topmost one VERSION agrees with"
    ok=1
  fi
  # And no sibling 4.8.x section quietly stacked alongside it.
  n48=$(grep -cF '## [4.8.' "$CHANGELOG_MD")
  [ "$n48" -eq 1 ] || { echo "  '## [4.8.' appears $n48 times, expected exactly 1"; ok=1; }
  rm -f "$head_list" "$work_list"
  return $ok
}

test_versionbump_03_docs_and_tests_parts_need_no_bump_of_their_own() {
  # The docs-only clause of the policy applies to them (sub-spec 06,
  # versionbump-03's second clause): the versioning rule still exempts a
  # docs-only or tests-only edit, so this change's AGENTS.md/CLAUDE.md,
  # docs/, spdd/ and tests/ edits ride on the single bump mandated by its
  # tracked-path edits instead of needing further entries.
  ok=0
  for vsection in "$AGENTS_VSECTION" "$CLAUDE_VSECTION"; do
    [ -s "$vsection" ] || { echo "  no '## Versioning' section to read"; ok=1; continue; }
    require "$vsection" 'Changes to docs (`AGENTS.md`, `CLAUDE.md`, `docs/`, `spdd/`)' || ok=1
    require "$vsection" "don't require a bump" || ok=1
    require "$vsection" 'and to `tests/`' || ok=1
  done
  # The policy docs' Versioning sections stay byte-identical to each other
  # (the bump follows the existing gradation, not a new rubric).
  cmp -s "$AGENTS_VSECTION" "$CLAUDE_VSECTION" \
    || { echo "  AGENTS.md and CLAUDE.md '## Versioning' sections differ (the bump must not rewrite the policy)"; ok=1; }
  return $ok
}

# ---- run everything -----------------------------------------------------------

run_test "versionbump-01: VERSION is a semver agreeing with the newest (topmost) CHANGELOG entry -- never a pinned literal" test_versionbump_01_version_agrees_with_newest_entry
run_test "versionbump-01: VERSION's only content is the version value with one trailing newline" test_versionbump_01_version_newline_terminated_only_content
run_test "versionbump-01: CHANGELOG.md carries exactly one dated '## [4.8.0] - YYYY-MM-DD' section sitting above the [4.7.1] section which stays above [4.7.0] (relative ordering only -- the stacking lesson), Keep-a-Changelog statement intact" test_versionbump_01_480_section_dated_above_471
run_test "versionbump-01: the [4.8.0] section uses the file's existing entry style -- category headings with bold lead-in bullets" test_versionbump_01_entry_uses_existing_style
run_test "versionbump-01: the [4.8.0] entry describes the four scripts installed as files under the resolved \${XDG_CONFIG_HOME:-\$HOME/.config}/antz/scripts/ libdir with marker, backup, and --check reporting" test_versionbump_01_entry_describes_the_four_libdir_scripts
run_test "versionbump-01: the [4.8.0] entry describes the orchestrator prompt and both /antz-set-model command bodies invoking the installed scripts by their resolved paths with zero script re-materialization" test_versionbump_01_entry_describes_invocation_by_resolved_path
run_test "versionbump-01: the [4.8.0] entry describes inject_includes() and the '# antz-include:' markers retired along with the antz-skills.sh fence-indent carve-out" test_versionbump_01_entry_describes_the_embed_machinery_retired
run_test "versionbump-01: the [4.8.0] entry describes the set-model script's required client first argument and its internal agents-dir resolution" test_versionbump_01_entry_describes_set_model_client_argument
run_test "versionbump-01: the [4.8.0] entry describes --check extended to the installed scripts" test_versionbump_01_entry_describes_check_extended
run_test "versionbump-01: the [4.8.0] entry describes the AGENTS.md and CLAUDE.md law and docs/orchestrator.md updated" test_versionbump_01_entry_describes_docs_law_updated
run_test "versionbump-01: the [4.8.0] entry states the expected cache effect -- the rendered orchestrator body from ~483 lines to ~150, per-session script re-materialization to zero" test_versionbump_01_entry_states_expected_cache_effect
run_test "versionbump-01: the [4.7.1] section and every entry below it are byte-for-byte unchanged -- still above [4.7.0] still describing its changes, and the [4.7.1]-down tail matches git HEAD" test_versionbump_01_earlier_entries_byte_untouched

run_test "versionbump-02: the [4.8.0] entry states the grade as minor, not patch and not major -- rendered bodies and install mechanics change, not the wording-only kind that grades as patch" test_versionbump_02_entry_grades_minor_explicitly
run_test "versionbump-02: the [4.8.0] entry addresses the 'install locations' clause head-on -- workflow contract, machine-line vocabulary, antz:generated marker format, access model and the twelve client-file install paths unchanged; the libdir an additional install location shared by both clients that no existing consumer breaks on" test_versionbump_02_entry_addresses_install_locations_clause_head_on
run_test "versionbump-02: the [4.8.0] entry cites the 4.3.0 entry's explicit-adjacency-note precedent for that grading-table clause" test_versionbump_02_entry_cites_the_430_adjacency_precedent
run_test "versionbump-02: the [4.8.0] entry states that no role creates the v4.8.0 tag -- it is the human's commit-time follow-up, created against the bump commit and not pushed automatically" test_versionbump_02_entry_states_the_tag_is_the_humans_follow_up
run_test "versionbump-02: no v4.8.0 tag exists while the bump is uncommitted -- no role tags; gated on change_pending (retires with a loud note after the human's commit)" test_versionbump_02_no_v480_tag_created_while_uncommitted
run_test "versionbump-02: the change_pending gate is exercised on a throwaway scratch repo through its whole lifecycle -- off when clean, enforced while the bump is pending, retired vacuously once the human's bump commit lands, and never resurrected by a later legitimate bump (the suite exits 0 in both the pending and the committed state)" test_versionbump_02_change_pending_gate_enforced_while_pending_and_retires_when_committed
run_test "versionbump-02: the suite itself never commits, never tags, and never mutates the working tree -- every git invocation against the real repo is diff/show/tag-l, and every git invocation carries an explicit -C target" test_versionbump_02_suite_never_commits_tags_or_mutates_the_working_tree

run_test "versionbump-03: the single [4.8.0] entry covers the orchestrator prompt edit, install.sh's mechanics change, the command files' rendered shape, and the docs/tests edits together" test_versionbump_03_single_entry_covers_every_component
run_test "versionbump-03: exactly one CHANGELOG entry was added versus git HEAD and it is the newest one VERSION agrees with (no second bump for any part of the change) -- gated on change_pending" test_versionbump_03_exactly_one_new_entry_above_471
run_test "versionbump-03: the policy's docs-only clause (AGENTS.md, CLAUDE.md, docs/, spdd/ and tests/ need no bump) still stands in both byte-identical Versioning sections, so those parts ride on the single bump" test_versionbump_03_docs_and_tests_parts_need_no_bump_of_their_own

rm -f "$CHANGELOG_ENTRY" "$ENTRY_471" "$AGENTS_VSECTION" "$CLAUDE_VSECTION"

echo ""
echo "$pass_count passed, $fail_count failed (see 06-versionbump.feature)"
[ "$fail_count" -eq 0 ]
