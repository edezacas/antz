#!/usr/bin/env bash
# Unit tests for the repo versioning policy docs (AGENTS.md + CLAUDE.md),
# covering every scenario in
# spdd/changes/versioning-install-sh/01-versioning.feature
# (versioning-01..07; the two scenario outlines get one test per example
# row, with the row label in the test name alongside the id).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), mirroring the harness style
# of tests/set-model-command_test.sh. Run directly:
#   ./tests/versioning-rule_test.sh
#
# These are docs-content tests: they read the repo's AGENTS.md and CLAUDE.md
# and assert the documented versioning rule -- the tracked set includes
# install.sh with the same-commit VERSION/CHANGELOG.md bump requirement, one
# patch/minor/major scale for agents/ and install.sh changes alike, the
# preserved docs-only no-bump clause, the recorded rationale, and byte-
# identical Versioning sections across the two files. Negative assertions
# cover the removed exemption sentence and any install.sh-exempt wording.
#
# The change's end-to-end scenarios (e2e-qa-01..05 in
# spdd/changes/versioning-install-sh/e2e-qa.feature) are observable only by
# driving the real repo/install lifecycle (live installs, careful working-
# tree restore semantics), so the sub-spec's Verification levels assign them
# to the verifier's e2e suite, not to this unit suite. They appear below as
# explicit SKIP stubs so no scenario id is silently unaccounted for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner (mirrors tests/set-model-command_test.sh) ------------

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

# Extract each file's "## Versioning" section once (both files carry it as
# their final section); content tests grep these extracts, and the parity
# test (versioning-06) compares them byte-for-byte.
AGENTS_VSECTION=$(mktemp)
CLAUDE_VSECTION=$(mktemp)
sed -n '/^## Versioning$/,$p' "$AGENTS_MD" > "$AGENTS_VSECTION"
sed -n '/^## Versioning$/,$p' "$CLAUDE_MD" > "$CLAUDE_VSECTION"

exemption_sentences() {
  # $1 = file; prints each sentence (period-delimited) that uses bump-
  # exemption language ("don't require a bump", "no bump required", "exempt
  # from", ...). The preserved docs-only no-bump clause is expected to match;
  # the point is to inspect what it exempts.
  tr '\n' ' ' < "$1" | sed 's/\.\s/\.\n/g' |
    grep -iE "(don.t|does not|doesn.t|do not|won.t|will not) require (a |an |any )?(bump|VERSION)|no bump (is|was|required)|require no (bump|VERSION|CHANGELOG)|exempt from" || true
}

check_exemption_sentences() {
  # $1 = file. Every bump-exemption sentence must be the preserved docs-only
  # clause: it names "docs" and never mentions "install.sh" as exempt.
  bad=0
  found=0
  while IFS= read -r sentence; do
    [ -z "$sentence" ] && continue
    found=$((found + 1))
    case "$sentence" in
      *docs*) ;;
      *) echo "  $1: exemption sentence does not name docs: $sentence"; bad=1 ;;
    esac
    case "$sentence" in
      *install.sh*) echo "  $1: exemption sentence mentions install.sh: $sentence"; bad=1 ;;
    esac
  done < <(exemption_sentences "$1")
  [ "$found" -gt 0 ] || { echo "  $1: no docs-only no-bump clause found"; bad=1; }
  return $bad
}

docs_only_clause() {
  # Common assertion for every versioning-03 row: the section explicitly
  # states which paths are NOT tracked and require no bump.
  require "$AGENTS_VSECTION" 'Changes to docs (`AGENTS.md`, `CLAUDE.md`, `docs/`, `spdd/`)' || return 1
  require "$AGENTS_VSECTION" "don't require a bump" || return 1
}

# =============================================================================
# versioning-01: the tracked set expands to include install.sh, and the
# same-commit bump requirement carries over regardless of what else a commit
# contains (mixed commits are still bump commits).
# =============================================================================
test_versioning_01() {
  ok=0
  require "$AGENTS_VSECTION" 'track changes to `agents/prompts/`, `agents/meta/`, and `install.sh`' || ok=1
  require "$AGENTS_VSECTION" 'Any commit that changes any of those three must bump `VERSION` and add a matching `CHANGELOG.md` entry in the same commit' || ok=1
  require "$AGENTS_VSECTION" 'regardless of what else that commit contains' || ok=1
  require "$AGENTS_VSECTION" 'together with docs or tests is still a bump commit' || ok=1
  return $ok
}

# =============================================================================
# versioning-02: the wrong sentence is gone from both files in full, and
# nothing equivalent takes its place -- no statement exempts install.sh from
# the VERSION/CHANGELOG.md bump requirement.
# =============================================================================
test_versioning_02() {
  ok=0
  refuse "$AGENTS_MD" 'Changes elsewhere' || ok=1
  refuse "$CLAUDE_MD" 'Changes elsewhere' || ok=1
  check_exemption_sentences "$AGENTS_MD" || ok=1
  check_exemption_sentences "$CLAUDE_MD" || ok=1
  return $ok
}

# =============================================================================
# versioning-03 (row: agents/prompts/): the stated rule resolves a commit
# changing only agents/prompts/ as a VERSION bump + matching CHANGELOG.md
# entry, same commit.
# =============================================================================
test_versioning_03_row_agents_prompts() {
  ok=0
  docs_only_clause || ok=1
  require "$AGENTS_VSECTION" 'track changes to `agents/prompts/`' || ok=1
  require "$AGENTS_VSECTION" 'must bump `VERSION` and add a matching `CHANGELOG.md` entry in the same commit' || ok=1
  return $ok
}

# =============================================================================
# versioning-03 (row: agents/meta/): resolves to a VERSION bump + matching
# CHANGELOG.md entry, same commit.
# =============================================================================
test_versioning_03_row_agents_meta() {
  ok=0
  docs_only_clause || ok=1
  require "$AGENTS_VSECTION" '`, `agents/meta/`' || ok=1
  require "$AGENTS_VSECTION" 'must bump `VERSION` and add a matching `CHANGELOG.md` entry in the same commit' || ok=1
  return $ok
}

# =============================================================================
# versioning-03 (row: install.sh): resolves to a VERSION bump + matching
# CHANGELOG.md entry, same commit.
# =============================================================================
test_versioning_03_row_install_sh() {
  ok=0
  docs_only_clause || ok=1
  require "$AGENTS_VSECTION" 'and `install.sh`' || ok=1
  require "$AGENTS_VSECTION" 'must bump `VERSION` and add a matching `CHANGELOG.md` entry in the same commit' || ok=1
  return $ok
}

# =============================================================================
# versioning-03 (row: agents/ and install.sh in one commit): a mixed commit
# with any tracked path still resolves to a VERSION bump + matching
# CHANGELOG.md entry, same commit.
# =============================================================================
test_versioning_03_row_agents_and_install_sh() {
  ok=0
  docs_only_clause || ok=1
  require "$AGENTS_VSECTION" 'Any commit that changes any of those three' || ok=1
  require "$AGENTS_VSECTION" 'regardless of what else that commit contains' || ok=1
  require "$AGENTS_VSECTION" 'together with docs or tests is still a bump commit' || ok=1
  return $ok
}

# =============================================================================
# versioning-03 (row: AGENTS.md, CLAUDE.md, docs/, or spdd/): resolves to no
# VERSION bump and no CHANGELOG.md entry.
# =============================================================================
test_versioning_03_row_docs() {
  ok=0
  docs_only_clause || ok=1
  require "$AGENTS_VSECTION" 'Changes to docs (`AGENTS.md`, `CLAUDE.md`, `docs/`, `spdd/`)' || ok=1
  return $ok
}

# =============================================================================
# versioning-03 (row: tests/): resolves to no VERSION bump and no
# CHANGELOG.md entry.
# =============================================================================
test_versioning_03_row_tests() {
  ok=0
  docs_only_clause || ok=1
  require "$AGENTS_VSECTION" 'and to `tests/`' || ok=1
  return $ok
}

# =============================================================================
# versioning-04 (row: patch): one scale for agents/ and install.sh alike --
# an install.sh wording-only tweak (comment/string-only, internal refactor,
# no rendered-output or reported-behavior change) grades as a patch bump.
# =============================================================================
test_versioning_04_row_patch() {
  ok=0
  require "$AGENTS_VSECTION" 'one scale for `agents/` and `install.sh` changes alike' || ok=1
  require "$AGENTS_VSECTION" 'grades by its most severe component' || ok=1
  require "$AGENTS_VSECTION" 'patch for non-behavioral wording tweaks' || ok=1
  require "$AGENTS_VSECTION" 'comment/string-only tweaks and internal refactors' || ok=1
  require "$AGENTS_VSECTION" 'no change to rendered output or reported behavior' || ok=1
  return $ok
}

# =============================================================================
# versioning-04 (row: minor): an install.sh behavior change (rendered
# agent/command bodies, flags, install paths, detection logic, --check
# report) grades as a minor bump.
# =============================================================================
test_versioning_04_row_minor() {
  ok=0
  require "$AGENTS_VSECTION" 'one scale for `agents/` and `install.sh` changes alike' || ok=1
  require "$AGENTS_VSECTION" 'grades by its most severe component' || ok=1
  require "$AGENTS_VSECTION" 'minor for behavior changes' || ok=1
  require "$AGENTS_VSECTION" 'install mechanics and rendered commands/agents' || ok=1
  require "$AGENTS_VSECTION" 'the `--check` report' || ok=1
  return $ok
}

# =============================================================================
# versioning-04 (row: major): a breaking change to the workflow contract or
# the rendered command contract (the antz:generated marker format, the
# access-to-frontmatter mapping, install locations) grades as a major bump.
# =============================================================================
test_versioning_04_row_major() {
  ok=0
  require "$AGENTS_VSECTION" 'one scale for `agents/` and `install.sh` changes alike' || ok=1
  require "$AGENTS_VSECTION" 'grades by its most severe component' || ok=1
  require "$AGENTS_VSECTION" 'major for breaking changes to the workflow contract or the rendered command contract' || ok=1
  require "$AGENTS_VSECTION" 'the `antz:generated` marker format' || ok=1
  require "$AGENTS_VSECTION" 'access-to-frontmatter mapping' || ok=1
  require "$AGENTS_VSECTION" 'install locations' || ok=1
  return $ok
}

# =============================================================================
# versioning-05: the section records why install.sh is tracked (it renders
# the installed agent and command files directly and embeds the source
# VERSION in each installed file's antz:generated marker comment) and that
# without a bump, ./install.sh --check's version comparison reports no
# drift -- installed copies silently go stale, and the documented bump rule
# is the only defense.
# =============================================================================
test_versioning_05() {
  ok=0
  require "$AGENTS_VSECTION" 'renders the installed agent and command files directly' || ok=1
  require "$AGENTS_VSECTION" 'files directly and embeds the source `VERSION`' || ok=1
  require "$AGENTS_VSECTION" '`antz:generated` marker comment' || ok=1
  require "$AGENTS_VSECTION" 'silently stale' || ok=1
  require "$AGENTS_VSECTION" 'version comparison reports no drift' || ok=1
  require "$AGENTS_VSECTION" 'the documented bump rule is the only defense' || ok=1
  return $ok
}

# =============================================================================
# versioning-06: the two policy docs state the identical rule -- their
# "## Versioning" sections are byte-identical. (The scenario's "a future rule
# change updates both files in the same commit" clause is process discipline
# for maintainers; the byte-identical parity asserted here is its observable
# consequence in the docs.)
# =============================================================================
test_versioning_06() {
  ok=0
  [ -s "$AGENTS_VSECTION" ] || { echo "  AGENTS.md has no ## Versioning section"; ok=1; }
  [ -s "$CLAUDE_VSECTION" ] || { echo "  CLAUDE.md has no ## Versioning section"; ok=1; }
  cmp -s "$AGENTS_VSECTION" "$CLAUDE_VSECTION" \
    || { echo "  ## Versioning sections differ between AGENTS.md and CLAUDE.md"; ok=1; }
  return $ok
}

# =============================================================================
# versioning-07: the section's other two bullets survive with unchanged
# meaning -- the marker-embedding/--check description, and the local vX.Y.Z
# git tag per bump. Saying "Every VERSION bump", the tag rule already covers
# install.sh-mandated bumps without being reworded.
# =============================================================================
test_versioning_07() {
  ok=0
  require "$AGENTS_VSECTION" 'embeds the source `VERSION` in each installed file' || ok=1
  require "$AGENTS_VSECTION" "in each installed file's marker comment. Every run compares that to the installed copy" || ok=1
  require "$AGENTS_VSECTION" 'embedded version and, if newer, prints the intervening `CHANGELOG.md` entries before overwriting' || ok=1
  require "$AGENTS_VSECTION" 'only prints that report' || ok=1
  require "$AGENTS_VSECTION" 'no files are written' || ok=1
  require "$AGENTS_VSECTION" 'Every `VERSION` bump gets a matching git tag (`vX.Y.Z`) created locally against the commit that makes the bump, in the same change' || ok=1
  require "$AGENTS_VSECTION" 'pushed automatically, only on explicit request' || ok=1
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "versioning-01: VERSION/CHANGELOG.md track agents/prompts/, agents/meta/, AND install.sh; same-commit bump requirement regardless of what else the commit contains" test_versioning_01
run_test "versioning-02: the old 'Changes elsewhere (install.sh, docs) don't require a bump' sentence is gone from both files, with no install.sh-exempt wording left" test_versioning_02
run_test "versioning-03 (row: agents/prompts/): resolves to a VERSION bump + matching CHANGELOG.md entry, same commit" test_versioning_03_row_agents_prompts
run_test "versioning-03 (row: agents/meta/): resolves to a VERSION bump + matching CHANGELOG.md entry, same commit" test_versioning_03_row_agents_meta
run_test "versioning-03 (row: install.sh): resolves to a VERSION bump + matching CHANGELOG.md entry, same commit" test_versioning_03_row_install_sh
run_test "versioning-03 (row: agents/ and install.sh in one commit): resolves to a VERSION bump + matching CHANGELOG.md entry, same commit" test_versioning_03_row_agents_and_install_sh
run_test "versioning-03 (row: AGENTS.md, CLAUDE.md, docs/, or spdd/): resolves to no VERSION bump and no CHANGELOG.md entry" test_versioning_03_row_docs
run_test "versioning-03 (row: tests/): resolves to no VERSION bump and no CHANGELOG.md entry" test_versioning_03_row_tests
run_test "versioning-04 (row: patch): one scale for agents/ and install.sh alike -- install.sh wording-only tweak (comment/string-only, internal refactor, no rendered-output or reported-behavior change) is a patch bump" test_versioning_04_row_patch
run_test "versioning-04 (row: minor): install.sh behavior change (rendered bodies, flags, install paths, detection logic, --check report) is a minor bump" test_versioning_04_row_minor
run_test "versioning-04 (row: major): breaking change to the workflow or rendered-command contract (marker format, access mapping, install locations) is a major bump" test_versioning_04_row_major
run_test "versioning-05: the section records why install.sh is tracked (renders installed files, embeds VERSION in the antz:generated marker) and that --check would otherwise report no drift" test_versioning_05
run_test "versioning-06: AGENTS.md and CLAUDE.md state the identical rule -- their ## Versioning sections are byte-identical" test_versioning_06
run_test "versioning-07: the marker/--check bullet and the vX.Y.Z tag bullet survive with unchanged meaning (tag rule already covers install.sh-mandated bumps)" test_versioning_07

# ---- e2e-only scenarios: explicit SKIP stubs ---------------------------------
# e2e-qa-01..05 (spdd/changes/versioning-install-sh/e2e-qa.feature) drive the
# real repo/install lifecycle (live installs into a real HOME, careful
# working-tree restore semantics) and belong to the verifier's end-to-end
# suite, not to this unit suite. Explicit stubs so every scenario id is
# accounted for.

E2E_REASON="e2e-only: live install / restore semantics, run by the verifier (e2e-qa.feature)"

skip_test "e2e-qa-01: user reads both policy docs and finds the identical corrected rule with the docs-only clause intact" "$E2E_REASON"
skip_test "e2e-qa-02: an unbumped install.sh-only description edit is invisible to ./install.sh --check; tree and installs restored after" "$E2E_REASON"
skip_test "e2e-qa-03 (3 example rows): the documented rule alone resolves the patch/minor/major gradation for install.sh-only changes" "$E2E_REASON"
skip_test "e2e-qa-04: this docs-only change itself is the worked example -- docs predict no bump, repo state confirms it" "$E2E_REASON"
skip_test "e2e-qa-05: a rule-following install.sh change with a same-commit bump makes --check report the drift and print the changelog; restored after" "$E2E_REASON"

rm -f "$AGENTS_VSECTION" "$CLAUDE_VSECTION"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see e2e-qa.feature)"
[ "$fail_count" -eq 0 ]
