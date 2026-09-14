#!/usr/bin/env bash
# Unit tests for scripts/orchestration/antz-flow.sh — the branch-marked,
# never-committed variant: each change gets its own marker branch antz/<slug>,
# ensure
# positions the session on that branch (create-then-switch fresh, plain
# switch on resume, refused-checked when git would destroy uncommitted
# work), and nothing is ever committed or removed, so the script computes
# purely mechanical, disk-derivable facts — which antz/* branches exist in
# the main checkout, what change state sits uncommitted in its working
# tree, and whether the release gate holds.
#
# Extended by change flow-script-guards (sub-spec 01, scenarios ensure-15..
# ensure-20, plus the rewrites of ensure-02/ensure-05): mechanical slug
# validation (state=bad_slug before the no-commits check and any branch or
# positioning work — lowercase letters/digits/hyphen, no leading/trailing or
# doubled hyphen, at most 40 chars), the new-flow tree guard (state=
# tree_dirty only when the change dir is absent AND the marker branch would
# be newly created, on a non-empty git status --porcelain; skipped on
# resume), and the advisory dirty=yes line appended after any state=reused
# on a dirty tree. The flow-09 scripts byte-unchanged guard is re-scoped off
# antz-flow.sh (this change's subject) onto the untouched probe+skills
# scripts (ensure-19); ensure-20's counterpart lands in
# tests/renderinject_test.sh.
#
# Extended again by change flow-script-guards (sub-spec 02, scenarios
# orchestrator-01 and orchestrator-06): step 1's ensure instructions also
# document state=tree_dirty, state=bad_slug, and the dirty=yes advisory
# (orchestrator-01's extension), and the new orchestrator-06 test pins the
# Session guards' latch stop list and the Report Format's stopped
# enumeration naming the two new machine-line stops as hard status=stopped
# variants with their resume actions, the advisory's not-a-stop framing,
# and the scenario's structural clauses.
#
# It also guards the orchestrator prompt's own prose that consumes the
# script (sub-spec "orchestrator", scenarios orchestrator-01..06): the
# step-1 ensure instructions' state meanings, the step-5 human follow-up
# print with its placeholder merge target, the law wording, and the
# unchanged surface — static assertions on the prompt text (precedent:
# tests/versioning-rule_test.sh).
#
# Extended by change fix-orchestrator-flow (sub-spec 01, scenarios flow-01..
# flow-10): the post-ensure change_dir=missing routing (never-specified ->
# specifier delegation; on-disk candidate -> mid-session-deletion stop;
# post-verifier -> step 5), step 5's disk-based verifier-outcome detection
# (re-probe + release gate + rejected_count comparison), the dedup guard's
# exactly-two step-4 exceptions, the stopped/waiting-user stop vocabulary,
# and the unchanged-surface constraints (14 fence lines / one ```sh fence /
# steps end at 6 / the four tables / the untouched scripts/orchestration/
# probe+skills byte-unchanged — re-scoped by flow-script-guards, ensure-19).
#
# Helpers are exercised against throwaway git repos under a temp dir; every
# scenario id carries the ensure-<n>, orchestrator-<n> or flow-<n> prefix
# (and each example-table row is its own test), which the sub-spec convention
# expects.
#
# Since change orchestrator-fast-path (sub-spec 01) the scripts live as real
# files under scripts/orchestration/, so this suite loads antz-flow.sh (and
# the probe, for the state tests) as files directly — no extraction from the
# prompt anymore (testharness-01); a prompt body can no longer drift from the
# tested code.
#
# Trimmed by change optimize-test-suite (sub-spec 09): every prompt-prose
# pin this suite carried (the orchestrator-01..06 and flow-01..10 families,
# their PROSE_* extractors, testsuite-01's fence pins, and ensure-19's
# scripts-byte-unchanged guard vs git HEAD) was deleted under the four
# permanent laws (no HEAD comparisons, no prose pins — the living facts
# these scenarios certified are asserted on the installed render by
# tests/invocations_test.sh's re-keyed invocations-01/-06). What remains is
# the full ensure/discover/state/release behavior suite, run against throw-
# away git fixtures under temp space and the byte-identical script files.
#
# Self-contained bash test harness, mirroring the harness style of
# tests/orchestrator-status-probe_test.sh. Run:
#   sh tests/antz-flow_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FLOW_SH="$SCRIPT_DIR/scripts/orchestration/antz-flow.sh"
PROBE_SH="$SCRIPT_DIR/scripts/orchestration/antz-probe.sh"

pass_count=0
fail_count=0
skip_count=0

run_test() {
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

# ---- tiny git fixture --------------------------------------------------------

REPO_ROOT=""
SLUG=""

add_tmp_repo() {
  TMP_REPOS="$TMP_REPOS $1"
}

new_repo() {
  REPO_ROOT=$(mktemp -d)
  add_tmp_repo "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  # Branch creation/positioning needs at least one commit (the script
  # fail-closes on a repo with no commits -- tested explicitly via
  # git rev-parse HEAD).
  echo hello > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" add .
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m init
  # New repos may default to any initial branch name; normalize to master
  # (a pure fixture concern only — the script itself never renames).
  if [ "$(git -C "$REPO_ROOT" branch --show-current)" != "master" ]; then
    git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t branch -m master
  fi
  SLUG="$1"
}

new_repo_no_commit() {
  REPO_ROOT=$(mktemp -d)
  add_tmp_repo "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  SLUG="$1"
}

run_flow() {
  # $@ = flow subcommand + args; runs from inside the repo.
  ( cd "$REPO_ROOT" && sh "$FLOW_SH" "$@" )
}

run_state_through_flow() {
  ( cd "$REPO_ROOT" && sh "$FLOW_SH" state "$SLUG" "$PROBE_SH" )
}

mk_change_dir() {
  # Simulate what the specifier leaves on disk: the change dir exists,
  # uncommitted (as everything always is in this variant).
  mkdir -p "$REPO_ROOT/spdd/changes/$SLUG"
  echo "# spec" > "$REPO_ROOT/spdd/changes/$SLUG/01-api.feature"
}

mk_archive() {
  # Simulate what a passing verifier's Merge & Archive leaves on disk:
  # spdd/archive/<slug> present, spdd/changes/<slug> gone, all uncommitted.
  mkdir -p "$REPO_ROOT/spdd/archive/$SLUG"
  echo ok > "$REPO_ROOT/spdd/archive/$SLUG/x.md"
}

# Full branch-ref snapshot: for the never-commits/no-destruction assertions,
# the complete `git show-ref --heads` output is compared byte-identically
# before and after.
all_refs() {
  git -C "$REPO_ROOT" show-ref --heads
}

# ---- fixture teardown --------------------------------------------------------

# Every tmp repo ever created, space-separated (POSIX sh: no arrays). cleanup
# removes them all on EXIT — without the accumulation, only the last repo
# would be deleted and each test would orphan its mktemp dir.
TMP_REPOS=""

cleanup() {
  for d in $TMP_REPOS; do
    # Never rely on git state beyond the throwaway repo; force-remove the
    # whole temp dir (this is the test's own repo, not a user's).
    [ -d "$d" ] && rm -rf "$d"
  done
  REPO_ROOT=""
  SLUG=""
}
trap cleanup EXIT

# =============================================================================
# loaded guard: the script under test is the real file (guards every other
# test against a silent no-op if the file ever goes missing or its shape
# changes).
# =============================================================================
test_ensure_extracted() {
  [ -f "$FLOW_SH" ] || { echo "  no flow script at scripts/orchestration/antz-flow.sh"; return 1; }
  sh -n "$FLOW_SH" || { echo "  flow script fails sh -n"; return 1; }
  grep -q 'br_exists' "$FLOW_SH" || { echo "  flow script doesn't look like the flow script"; return 1; }
  return 0
}

# =============================================================================
# testharness-01: the suite loads scripts/orchestration/antz-flow.sh as a
# file, with no extraction step reading agents/prompts/orchestrator.prompt —
# since change deembed-orchestration-scripts (testsuite-01 re-key) the
# prompt carries no script fence at all: step 1 references the flow script
# by its __ANTZ_SCRIPTS_DIR__/<name>.sh path form, so there is nothing to
# extract and the tested code cannot drift from the file.
# =============================================================================
test_testharness_01_file_source() {
  ok=0
  [ "$FLOW_SH" = "$SCRIPT_DIR/scripts/orchestration/antz-flow.sh" ] \
    || { echo "  the suite is not running scripts/orchestration/antz-flow.sh"; ok=1; }
  return $ok
}

# =============================================================================
# ensure-01: the fresh path creates the marker branch at the current HEAD and
# positions the session on it, with zero new commits.
# =============================================================================
test_ensure_01_fresh_creates_and_positions() {
  new_repo fresh-slug
  base_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=created" ] || { echo "  expected state=created, got: $out"; return 1; }
  [ "$st" -eq 0 ] || { echo "  expected exit 0, got: $st"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "antz/$SLUG" ] \
    || { echo "  session not positioned on antz/$SLUG"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse "refs/heads/antz/$SLUG")" = "$base_head" ] \
    || { echo "  marker branch not at pre-call HEAD"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-list --count HEAD)" = "1" ] \
    || { echo "  a commit happened"; return 1; }
}

# =============================================================================
# ensure-02 (rewritten by change flow-script-guards): a dirty tree at a new
# flow's start is refused with state=tree_dirty before any branch is created
# or checked out — uncommitted work is neither carried in nor destroyed.
# =============================================================================
test_ensure_02_new_flow_dirty_tree_refused() {
  new_repo carry-slug
  printf 'first\n' > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" add . && git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m base
  base_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  before_refs=$(all_refs)
  printf 'dirty\n' > "$REPO_ROOT/a.txt"
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=tree_dirty" ] \
    || { echo "  expected state=tree_dirty, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" branch --list 'antz/*')" ] \
    || { echo "  the marker branch was created despite the refusal"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "master" ] \
    || { echo "  the session moved off master"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$base_head" ] \
    || { echo "  HEAD moved"; return 1; }
  [ "$(all_refs)" = "$before_refs" ] || { echo "  a branch ref changed"; return 1; }
  [ "$(cat "$REPO_ROOT/a.txt")" = "dirty" ] \
    || { echo "  working-tree content changed"; return 1; }
  git -C "$REPO_ROOT" status --porcelain -- a.txt | grep -q '^ M a.txt' \
    || { echo "  a.txt no longer reported modified"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" stash list)" ] \
    || { echo "  a stash entry was created"; return 1; }
}

# =============================================================================
# ensure-17: non-empty git status --porcelain is the whole trigger — an
# untracked, non-ignored file blocks a new flow the same way a tracked
# modification does (fail-closed by design).
# =============================================================================
test_ensure_17_untracked_file_blocks_new_flow() {
  new_repo untracked-slug
  base_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  before_refs=$(all_refs)
  printf 'scratch\n' > "$REPO_ROOT/scratch.txt"
  git -C "$REPO_ROOT" status --porcelain | grep -q '^?? scratch.txt$' \
    || { echo "  fixture broken: scratch.txt is not untracked-non-ignored porcelain"; return 1; }
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=tree_dirty" ] \
    || { echo "  expected state=tree_dirty, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" branch --list 'antz/*')" ] \
    || { echo "  the marker branch was created despite the refusal"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "master" ] \
    || { echo "  the session moved off master"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$base_head" ] \
    || { echo "  HEAD moved"; return 1; }
  [ "$(all_refs)" = "$before_refs" ] || { echo "  a branch ref changed"; return 1; }
  [ "$(cat "$REPO_ROOT/scratch.txt")" = "scratch" ] \
    || { echo "  the untracked file was altered"; return 1; }
  git -C "$REPO_ROOT" status --porcelain | grep -q '^?? scratch.txt$' \
    || { echo "  the untracked file no longer reported"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" stash list)" ] \
    || { echo "  a stash entry was created"; return 1; }
}

# =============================================================================
# ensure-03: the resume path positions the session onto the existing branch
# without ever rewriting it.
# =============================================================================
test_ensure_03_resume_positions_without_rewriting() {
  new_repo reuse-slug
  base_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  git -C "$REPO_ROOT" branch -q "antz/$SLUG" "$base_head"
  # Advance the fixture's master past the flow's base commit (test-only
  # commit; the branch antz/<slug> stays behind, like an earlier session's
  # marker) — if ensure had -B semantics it would rewrite the ref.
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m later
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=reused" ] || { echo "  expected state=reused, got: $out"; return 1; }
  [ "$st" -eq 0 ] || { echo "  expected exit 0, got: $st"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "antz/$SLUG" ] \
    || { echo "  not positioned on antz/$SLUG"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse "refs/heads/antz/$SLUG")" = "$base_head" ] \
    || { echo "  marker branch ref was rewritten"; return 1; }
}

# =============================================================================
# ensure-04: re-running ensure mid-flow (already positioned) is a safe no-op.
# =============================================================================
test_ensure_04_ensure_again_is_noop() {
  new_repo again-slug
  run_flow ensure "$SLUG" >/dev/null
  before_refs=$(all_refs)
  before_tree=$(cat "$REPO_ROOT/a.txt")
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=reused" ] || { echo "  expected state=reused, got: $out"; return 1; }
  [ "$st" -eq 0 ] || { echo "  expected exit 0, got: $st"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "antz/$SLUG" ] \
    || { echo "  position lost"; return 1; }
  [ "$(all_refs)" = "$before_refs" ] || { echo "  a ref changed"; return 1; }
  [ "$(cat "$REPO_ROOT/a.txt")" = "$before_tree" ] \
    || { echo "  working tree touched"; return 1; }
}

# =============================================================================
# ensure-05 (rewritten by change flow-script-guards): the destructive-checkout
# refusal now lives on the resume path — change dir present, so the tree
# guard is skipped and the plain switch is what refuses. Stops machine-
# readably and forces nothing.
# =============================================================================
test_ensure_05_refused_switch_on_resume_stops_clean() {
  new_repo conflict-slug
  # antz/<slug> stays at the earlier commit (the initial one)…
  git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  # …master commits a different content…
  printf 'two\n' > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -am master-move
  master_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  before_refs=$(all_refs)
  # …the change dir exists (a resume: the tree guard is skipped)…
  mk_change_dir
  # …and the working tree holds a third, uncommitted content switching would
  # overwrite (the destructive-checkout conflict).
  printf 'dirty\n' > "$REPO_ROOT/a.txt"
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=checkout_refused" ] \
    || { echo "  expected state=checkout_refused, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  [ "$(cat "$REPO_ROOT/a.txt")" = "dirty" ] \
    || { echo "  uncommitted content destroyed"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "master" ] \
    || { echo "  session moved off master"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$master_head" ] \
    || { echo "  HEAD moved"; return 1; }
  [ "$(all_refs)" = "$before_refs" ] \
    || { echo "  a branch ref moved"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse "refs/heads/antz/$SLUG")" \
      = "$(git -C "$REPO_ROOT" rev-parse "master~1")" ] \
    || { echo "  marker branch moved"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" stash list)" ] \
    || { echo "  a stash entry was created"; return 1; }
}

# =============================================================================
# ensure-06: the script is statically free of destructive mechanisms — no
# force/reset/clean/stash/restore/branch-delete capability anywhere.
# =============================================================================
test_ensure_06_no_destructive_flags() {
  # Scan only invocation lines: comments inside the fence mention git freely
  # (the laws' prose) and are not invocations.
  git_lines=$(grep -v '^[[:space:]]*#' "$FLOW_SH" | grep 'git')
  [ -n "$git_lines" ] || { echo "  no git invocations found"; return 1; }
  if printf '%s\n' "$git_lines" | grep -E -- '[[:space:]](--force|-f|-B|-d|-D|-C|-m|-M)([[:space:]])' >/dev/null; then
    echo "  a git invocation carries a destructive/force flag:"; return 1
  fi
  if printf '%s\n' "$git_lines" | grep -E 'git (reset|clean|stash|restore)' >/dev/null; then
    echo "  a destructive git subcommand is present"; return 1
  fi
  # git branch appears only as the discover listing and the plain marker
  # creation.
  if printf '%s\n' "$git_lines" | grep 'git branch' \
       | grep -vE "git branch (--list 'antz/\*'|-q \"antz/\\\$slug\"|\"antz/\\\$slug\")" | grep -q .; then
    echo "  unexpected git branch invocation:"; return 1
  fi
  # The positioning appears only as a plain, flagless switch onto the
  # marker branch, and it exists (the law this sub-spec changes).
  switch_lines=$(printf '%s\n' "$git_lines" | grep 'git switch')
  [ "$(printf '%s\n' "$switch_lines" | grep -c 'git switch')" = "1" ] \
    || { echo "  git switch appears more than once:"; return 1; }
  printf '%s\n' "$switch_lines" | grep -q 'git switch "antz/\$slug"' \
    || { echo "  positioning is not a plain flagless switch: $switch_lines"; return 1; }
}

# =============================================================================
# ensure-07: no subcommand ever commits — HEAD and every branch ref hold
# steady across discover/ensure/state, a refused release, and a successful
# one.
# =============================================================================
test_ensure_07_no_subcommand_commits() {
  new_repo noc-slug
  run_flow ensure "$SLUG" >/dev/null
  mk_change_dir
  base_refs=$(all_refs)
  commit_count=$(git -C "$REPO_ROOT" rev-list --count HEAD)
  base_tree=$(cat "$REPO_ROOT/spdd/changes/$SLUG/01-api.feature")
  run_flow discover > /dev/null
  run_flow ensure "$SLUG" > /dev/null
  run_state_through_flow > /dev/null
  run_flow release "$SLUG" > /dev/null 2>&1
  # Refused: the change dir is still present — nothing may change.
  mv "$REPO_ROOT/spdd/changes/$SLUG" "$REPO_ROOT/spdd/archive-$SLUG"
  mkdir -p "$REPO_ROOT/spdd/archive/$SLUG"
  mv "$REPO_ROOT/spdd/archive-$SLUG"/* "$REPO_ROOT/spdd/archive/$SLUG/"
  rmdir "$REPO_ROOT/spdd/changes/$SLUG" 2>/dev/null || true
  rmdir "$REPO_ROOT/spdd/changes" 2>/dev/null || true
  run_flow release "$SLUG" > /dev/null
  [ "$(git -C "$REPO_ROOT" rev-list --count HEAD)" = "$commit_count" ] \
    || { echo "  HEAD's commit count grew"; return 1; }
  [ "$(all_refs)" = "$base_refs" ] \
    || { echo "  branch refs changed"; return 1; }
  [ "$(cat "$REPO_ROOT/spdd/archive/$SLUG/01-api.feature")" = "$base_tree" ] \
    || { echo "  working tree content lost"; return 1; }
}

# =============================================================================
# ensure-08 (outline, one test per row): the preflight fail-close is
# unchanged — every subcommand, both environments.
# =============================================================================
test_ensure_08_no_git_discover() {
  new_repo nogit-slug
  shellsh=$(command -v sh)
  out=$(PATH="/nonexistent" "$shellsh" "$FLOW_SH" discover 2>/dev/null); st=$?
  [ "$out" = "state=no_git" ] || { echo "  expected state=no_git, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
}

test_ensure_08_no_git_ensure() {
  new_repo nogit-slug
  shellsh=$(command -v sh)
  out=$(PATH="/nonexistent" "$shellsh" "$FLOW_SH" ensure "$SLUG" 2>/dev/null); st=$?
  [ "$out" = "state=no_git" ] || { echo "  expected state=no_git, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
}

test_ensure_08_no_repo_discover() {
  nonrepo=$(mktemp -d); add_tmp_repo "$nonrepo"
  out=$(cd "$nonrepo" && sh "$FLOW_SH" discover 2>/dev/null); st=$?
  [ "$out" = "state=no_repo" ] || { echo "  expected state=no_repo, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
}

test_ensure_08_no_repo_ensure() {
  nonrepo=$(mktemp -d); add_tmp_repo "$nonrepo"
  out=$(cd "$nonrepo" && sh "$FLOW_SH" ensure no-repo-slug 2>/dev/null); st=$?
  [ "$out" = "state=no_repo" ] || { echo "  expected state=no_repo, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
}

# =============================================================================
# ensure-09: the unborn-repo fail-close is unchanged — no branch, no
# positioning attempt.
# =============================================================================
test_ensure_09_unborn_repo_no_branch() {
  new_repo_no_commit unborn-slug
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=no_commits" ] || { echo "  expected state=no_commits, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/antz/$SLUG" \
    && { echo "  branch created despite no commits"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" != "antz/$SLUG" ] \
    || { echo "  positioning was attempted"; return 1; }
}

# =============================================================================
# ensure-10: when the branch cannot be made to exist (creation fails and it
# is still absent), ensure fail-closes truthfully — never a false "reused".
# A plain `git branch antz/<slug>` doesn't fail on a valid HEAD, so the
# create arm is exercised through a git shim on PATH that exits nonzero on
# `git branch` while delegating everything else to the real git.
# =============================================================================
test_ensure_10_creation_failed_reports_no_branch() {
  new_repo nobranch-slug
  shimdir=$(mktemp -d); add_tmp_repo "$shimdir"
  real_git=$(command -v git)
  {
    printf '#!/bin/sh\n'
    printf 'case "$1" in branch) exit 1;; esac\n'
    printf 'exec "%s" "$@"\n' "$real_git"
  } > "$shimdir/git"
  chmod +x "$shimdir/git"
  before=$(git -C "$REPO_ROOT" branch --show-current)
  out=$(cd "$REPO_ROOT" && PATH="$shimdir:$PATH" sh "$FLOW_SH" ensure "$SLUG"); st=$?
  [ "$out" = "state=no_branch" ] || { echo "  expected state=no_branch, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "$before" ] \
    || { echo "  session position changed"; return 1; }
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/antz/$SLUG"; then
    { echo "  branch exists despite the failure"; return 1; }
  fi
  return 0
}

# =============================================================================
# ensure-11 (outline, one test per row): the release gate is unchanged.
# =============================================================================
test_ensure_11_release_refused_archive_missing() {
  new_repo gate-slug
  run_flow ensure "$SLUG" >/dev/null
  mk_change_dir
  before_refs=$(all_refs)
  out=$(run_flow release "$SLUG"); st=$?
  [ "$out" = "gate=refused reason=archive-missing" ] \
    || { echo "  expected archive-missing, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  [ "$(all_refs)" = "$before_refs" ] || { echo "  something changed on disk"; return 1; }
  [ -d "$REPO_ROOT/spdd/changes/$SLUG" ] \
    || { echo "  change dir altered on a refusal"; return 1; }
}

test_ensure_11_release_refused_change_still_present() {
  new_repo gate-slug
  run_flow ensure "$SLUG" >/dev/null
  mk_change_dir; mk_archive
  out=$(run_flow release "$SLUG"); st=$?
  [ "$out" = "gate=refused reason=change-still-present" ] \
    || { echo "  expected change-still-present, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  [ -d "$REPO_ROOT/spdd/changes/$SLUG" ] && [ -f "$REPO_ROOT/spdd/changes/$SLUG/01-api.feature" ] \
    || { echo "  change dir altered on a refusal"; return 1; }
  [ -f "$REPO_ROOT/spdd/archive/$SLUG/x.md" ] \
    || { echo "  archive altered on a refusal"; return 1; }
}

test_ensure_11_release_refused_branch_missing() {
  new_repo gate-slug
  mk_archive
  out=$(run_flow release "$SLUG"); st=$?
  [ "$out" = "gate=refused reason=branch-missing" ] \
    || { echo "  expected branch-missing, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  before=$(ls -R "$REPO_ROOT/spdd")
  out2=$(run_flow release "$SLUG")
  [ "$out2" = "$out" ] || { echo "  gate output not stable"; return 1; }
  [ "$(ls -R "$REPO_ROOT/spdd")" = "$before" ] \
    || { echo "  nothing may change on a refusal"; return 1; }
}

# =============================================================================
# ensure-12: a successful release prints exactly the branch line, removes
# nothing, and prints no commands for anyone to run.
# =============================================================================
test_ensure_12_release_reports_and_removes_nothing() {
  new_repo rel-slug
  run_flow ensure "$SLUG" >/dev/null
  mk_change_dir
  mv "$REPO_ROOT/spdd/changes/$SLUG" "$REPO_ROOT/spdd/archive-$SLUG"
  mkdir -p "$REPO_ROOT/spdd/archive/$SLUG"
  mv "$REPO_ROOT/spdd/archive-$SLUG"/* "$REPO_ROOT/spdd/archive/$SLUG/"
  rmdir "$REPO_ROOT/spdd/changes/$SLUG" 2>/dev/null || true
  rmdir "$REPO_ROOT/spdd/changes" 2>/dev/null || true
  out=$(run_flow release "$SLUG"); st=$?
  [ "$out" = "released branch=antz/$SLUG" ] \
    || { echo "  expected released branch=..., got: $out"; return 1; }
  [ "$st" -eq 0 ] || { echo "  expected exit 0, got: $st"; return 1; }
  printf '%s' "$out" | grep -qE 'git|merge|delete|commit' \
    && { echo "  stdout carries a command suggestion"; return 1; }
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/antz/$SLUG" \
    || { echo "  branch didn't survive release"; return 1; }
  [ -d "$REPO_ROOT/spdd/archive/$SLUG" ] \
    || { echo "  archive was removed despite the contract"; return 1; }
}

# =============================================================================
# ensure-13: discover is unchanged — nothing when neither exists; exactly one
# branch line and one on-disk line when both do.
# =============================================================================
test_ensure_13_discover_unchanged() {
  new_repo fresh-slug
  out=$(run_flow discover)
  [ -z "$out" ] || { echo "  expected no candidates, got: $out"; return 1; }
  # Now both marker branch and change dir exist.
  run_flow ensure "$SLUG" >/dev/null
  mk_change_dir
  out=$(run_flow discover)
  printf '%s\n' "$out" | grep -qx "candidate=branch slug=$SLUG" \
    || { echo "  missing candidate=branch in: $out"; return 1; }
  printf '%s\n' "$out" | grep -qx "candidate=on-disk slug=$SLUG" \
    || { echo "  missing candidate=on-disk in: $out"; return 1; }
  [ "$(printf '%s\n' "$out" | grep -c 'candidate=')" = "2" ] \
    || { echo "  discover printed extra candidates: $out"; return 1; }
}

# =============================================================================
# ensure-14: state is unchanged — it verifies the marker branch, resolves the
# repo root, and runs the probe verbatim with CHANGE_DIR at the working
# tree's change dir; branch=missing without the branch.
# =============================================================================
test_ensure_14_state_unchanged() {
  new_repo probing-slug
  run_flow ensure "$SLUG" >/dev/null
  mk_change_dir
  out=$(run_state_through_flow)
  printf '%s\n' "$out" | grep -qx "working_root=$REPO_ROOT" \
    || { echo "  missing working_root line in: $out"; return 1; }
  printf '%s\n' "$out" | grep -q '^open_questions=no$' \
    || { echo "  probe didn't run with CHANGE_DIR set: $out"; return 1; }
  printf '%s\n' "$out" | grep -q '^subspec=01-api.feature ids=' \
    || { echo "  probe output missing subspec line: $out"; return 1; }
  # branch=missing fails closed when the marker branch is absent.
  new_repo ghost-slug
  out=$(run_state_through_flow); st=$?
  [ "$out" = "branch=missing" ] || { echo "  expected branch=missing, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
}

# =============================================================================
# ensure-15 (outline, one test per row): a mechanically invalid slug is
# rejected with exactly state=bad_slug (exit 1) before any branch or
# positioning work — non-destructively: no antz/* branch is created, the
# session stays put, HEAD, every branch ref, and the working tree are
# byte-unchanged, and no stash entry exists. The rule: lowercase letters,
# digits, and hyphen only; no leading/trailing hyphen; no double hyphen;
# length at most 40.
# =============================================================================
ensure_15_row() {
  # $1 = the invalid slug exactly as it appears on ensure's argv (the empty
  # row passes the empty string).
  new_repo other-flow-slug        # clean tree, no antz/* branch, no change dir
  SLUG="$1"
  base_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  before_refs=$(all_refs)
  before_branch=$(git -C "$REPO_ROOT" branch --show-current)
  before_file=$(cat "$REPO_ROOT/a.txt")
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=bad_slug" ] || { echo "  expected state=bad_slug, got: $out"; return 1; }
  [ "$st" -eq 1 ] || { echo "  expected exit 1, got: $st"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" branch --list 'antz/*')" ] \
    || { echo "  an antz/* branch was created for an invalid slug"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "$before_branch" ] \
    || { echo "  the session moved"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$base_head" ] \
    || { echo "  HEAD moved"; return 1; }
  [ "$(all_refs)" = "$before_refs" ] || { echo "  a branch ref changed"; return 1; }
  [ "$(cat "$REPO_ROOT/a.txt")" = "$before_file" ] \
    || { echo "  working-tree content changed"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] \
    || { echo "  the working tree was dirtied"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" stash list)" ] \
    || { echo "  a stash entry was created"; return 1; }
}

test_ensure_15_empty()        { ensure_15_row ''; }
test_ensure_15_uppercase()    { ensure_15_row 'Bad-Upper'; }
test_ensure_15_underscore()   { ensure_15_row 'under_score'; }
test_ensure_15_dot()          { ensure_15_row 'foo.bar'; }
test_ensure_15_slash()        { ensure_15_row 'foo/bar'; }
test_ensure_15_leading_hy()   { ensure_15_row '-leading'; }
test_ensure_15_trailing_hy()  { ensure_15_row 'trailing-'; }
test_ensure_15_double_hy()    { ensure_15_row 'double--hyphen'; }
test_ensure_15_len41()        { ensure_15_row "$(printf 'a%.0s' $(seq 41))"; }

# =============================================================================
# ensure-16: the length boundary — a slug of exactly 40 lowercase characters
# is valid: the fresh path runs through it and reports state=created.
# =============================================================================
test_ensure_16_len40_slug_is_valid() {
  new_repo "$(printf 'a%.0s' $(seq 40))"
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$out" = "state=created" ] || { echo "  expected state=created, got: $out"; return 1; }
  [ "$st" -eq 0 ] || { echo "  expected exit 0, got: $st"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "antz/$SLUG" ] \
    || { echo "  session not positioned on the 40-character flow branch"; return 1; }
}

# =============================================================================
# ensure-18: the guard is skipped on resume — a dirty tree still positions,
# and the reuse reports the pre-existing dirt as an advisory machine line
# ("dirty=yes" immediately after "state=reused", exit 0). The advisory is
# emitted on any non-empty-porcelain state=reused: the change-dir resume and
# the branch-only reuse whose change dir is still absent alike. The third
# row pins the change-dir half of the guard's conjunction: with the change
# dir on disk but no marker branch, the tree is dirty and this is still a
# resume (guard skipped) — ensure creates the marker fresh (state=created,
# which carries no advisory line).
# =============================================================================
ensure_18_row() {
  # $1 = change-dir (branch exists) | branch-only | change-dir-nobranch.
  new_repo resume-dirty-slug
  [ "$1" = change-dir ] && git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  [ "$1" = branch-only ] && git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  [ "$1" = change-dir ] && mk_change_dir
  [ "$1" = change-dir-nobranch ] && mk_change_dir
  base_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  printf 'dirty\n' > "$REPO_ROOT/a.txt"
  out=$(run_flow ensure "$SLUG"); st=$?
  [ "$st" -eq 0 ] || { echo "  expected exit 0, got: $st"; return 1; }
  if [ "$1" = change-dir-nobranch ]; then
    # A fresh creation carries no advisory: dirty=yes follows reused only.
    [ "$out" = "state=created" ] \
      || { echo "  expected state=created, got: $out"; return 1; }
  else
    [ "$out" = "$(printf 'state=reused\ndirty=yes')" ] \
      || { echo "  expected state=reused + dirty=yes, got: $out"; return 1; }
  fi
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "antz/$SLUG" ] \
    || { echo "  session not positioned on antz/$SLUG"; return 1; }
  [ "$(cat "$REPO_ROOT/a.txt")" = "dirty" ] \
    || { echo "  the modification was not carried over untouched"; return 1; }
  git -C "$REPO_ROOT" status --porcelain -- a.txt | grep -q '^ M a.txt' \
    || { echo "  a.txt no longer reported modified"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$base_head" ] \
    || { echo "  HEAD moved"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse "refs/heads/antz/$SLUG")" = "$base_head" ] \
    || { echo "  the marker branch ref moved"; return 1; }
  [ -z "$(git -C "$REPO_ROOT" stash list)" ] \
    || { echo "  a stash entry was created"; return 1; }
}

test_ensure_18_change_dir_resume() { ensure_18_row change-dir; }
test_ensure_18_branch_only_reuse()  { ensure_18_row branch-only; }
test_ensure_18_change_dir_no_branch() { ensure_18_row change-dir-nobranch; }


# ---- run ----------------------------------------------------------------------

run_test "ensure-extracted: the flow script is loaded from scripts/orchestration/antz-flow.sh and parses as POSIX sh" test_ensure_extracted
run_test "testharness-01: the flow suite loads scripts/orchestration/antz-flow.sh as a file (no extraction from the prompt)" test_testharness_01_file_source
run_test "ensure-01: ensure creates the branch at HEAD and positions the session" test_ensure_01_fresh_creates_and_positions
run_test "ensure-02: a dirty tree at a new flow's start is refused state=tree_dirty, nothing created or moved" test_ensure_02_new_flow_dirty_tree_refused
run_test "ensure-03: resume positions onto the existing branch without rewriting it" test_ensure_03_resume_positions_without_rewriting
run_test "ensure-04: re-running ensure while positioned is a safe no-op" test_ensure_04_ensure_again_is_noop
run_test "ensure-05: a refused switch on the resume path stops clean, guard skipped (change dir present)" test_ensure_05_refused_switch_on_resume_stops_clean
run_test "ensure-06: the script is statically free of destructive mechanisms" test_ensure_06_no_destructive_flags
run_test "ensure-07: no subcommand ever commits anything" test_ensure_07_no_subcommand_commits
run_test "ensure-08 git absent: discover fail-closes state=no_git" test_ensure_08_no_git_discover
run_test "ensure-08 git absent: ensure fail-closes state=no_git" test_ensure_08_no_git_ensure
run_test "ensure-08 non-repo: discover fail-closes state=no_repo" test_ensure_08_no_repo_discover
run_test "ensure-08 non-repo: ensure fail-closes state=no_repo" test_ensure_08_no_repo_ensure
run_test "ensure-09: unborn repo fail-closes state=no_commits" test_ensure_09_unborn_repo_no_branch
run_test "ensure-10: a failed creation reports state=no_branch, never reused" test_ensure_10_creation_failed_reports_no_branch
run_test "ensure-11 archive missing: release refuses and removes nothing" test_ensure_11_release_refused_archive_missing
run_test "ensure-11 change present: release refuses and removes nothing" test_ensure_11_release_refused_change_still_present
run_test "ensure-11 branch missing: release refuses and removes nothing" test_ensure_11_release_refused_branch_missing
run_test "ensure-12: release reports the branch and removes nothing, ever" test_ensure_12_release_reports_and_removes_nothing
run_test "ensure-13: discover is unchanged (empty listing and full listing)" test_ensure_13_discover_unchanged
run_test "ensure-14: state is unchanged (probe run and branch=missing)" test_ensure_14_state_unchanged
run_test "ensure-15 empty slug: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_empty
run_test "ensure-15 uppercase: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_uppercase
run_test "ensure-15 underscore: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_underscore
run_test "ensure-15 dot: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_dot
run_test "ensure-15 slash: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_slash
run_test "ensure-15 leading hyphen: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_leading_hy
run_test "ensure-15 trailing hyphen: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_trailing_hy
run_test "ensure-15 double hyphen: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_double_hy
run_test "ensure-15 41 chars: ensure rejects with state=bad_slug and changes nothing" test_ensure_15_len41
run_test "ensure-16: a 40-character slug is valid (state=created, positioned)" test_ensure_16_len40_slug_is_valid
run_test "ensure-17: an untracked non-ignored file blocks a new flow with state=tree_dirty" test_ensure_17_untracked_file_blocks_new_flow
run_test "ensure-18: a dirty change-dir resume positions and appends the advisory dirty=yes" test_ensure_18_change_dir_resume
run_test "ensure-18: a dirty branch-only reuse (no change dir) positions and appends dirty=yes" test_ensure_18_branch_only_reuse
run_test "ensure-18: a dirty change-dir resume with no marker branch is a resume, not a guarded new flow" test_ensure_18_change_dir_no_branch



# e2e-orchestrator-01 (spdd/changes/flow-branch-checkout/e2e-qa.feature) is
# observable only by driving a live antz-orchestrator session end to end —
# the verifier's Integration Verification, not this unit suite. Explicit
# stub so the scenario id is accounted for (suite convention: see
# tests/versioning-rule_test.sh).
skip_test "e2e-orchestrator-01: a live orchestrated run leaves the user on antz/<slug> and prints user-controlled follow-ups with a placeholder merge target" \
  "e2e-only: observable only in a live orchestrated run (verifier's e2e-qa.feature)"

# e2e-02 (spdd/changes/orchestrator-fast-path/07-e2e.feature) is the change's
# verifier-owned end-to-end QA suite: the user runs the three script suites
# from the source tree and checks the runnable-file affordances at the user
# surface. This suite is one of the three, so it cannot run its siblings from
# inside itself without recursing; the discover machine lines and `sh -n`
# cleanliness it observes are covered by this suite's own tests (ensure-13
# and the file-loading assertions) -- the scenario id itself still gets an
# explicit stub (suite convention: see tests/versioning-rule_test.sh).
skip_test "e2e-02: the three script suites pass reading scripts/orchestration/ files directly, in-repo discover prints the same candidate= lines as the temp-file invocation, and sh -n passes for each of the three files" \
  "e2e-only: the suite run itself is the verifier's step -- a suite cannot run its siblings from inside itself, run by the verifier (07-e2e.feature)"

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
