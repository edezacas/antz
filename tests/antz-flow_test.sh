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
# It also guards the orchestrator prompt's own prose that consumes the
# script (sub-spec "orchestrator", scenarios orchestrator-01..05): the
# step-1 ensure instructions' state meanings, the step-5 human follow-up
# print with its placeholder merge target, the law wording, and the
# unchanged surface — static assertions on the prompt text (precedent:
# tests/versioning-rule_test.sh).
#
# Helpers are exercised against throwaway git repos under a temp dir; every
# scenario id carries the ensure-<n> or orchestrator-<n> prefix (and each
# example-table row is its own test), which the sub-spec convention expects.
#
# Since change orchestrator-fast-path (sub-spec 01) the scripts live as real
# files under scripts/orchestration/ and the prompt's fences carry only
# include markers, so this suite loads antz-flow.sh (and the probe, for the
# state tests) as files directly — no extraction from the prompt anymore
# (testharness-01); a prompt fence can no longer drift from the tested code.
#
# Self-contained bash test harness, mirroring the harness style of
# tests/orchestrator-status-probe_test.sh. Run:
#   sh tests/antz-flow_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
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

# ---- prompt-prose extracts (sub-spec "orchestrator") -------------------------
#
# The prose scenarios assert on section-scoped extracts of the prompt, not
# the whole file, so a stray mention elsewhere can't satisfy them. The flow
# fence (script) is excluded from prose extracts — its comments are the
# script's own law wording, asserted via the FLOW_SCRIPT file.

# ---- content-assertion helpers (precedent: tests/versioning-rule_test.sh) ----

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

FLOW_SCRIPT="$FLOW_SH"

# Step 1's prose after the flow fence: from the flow fence's closing ```
# (the second 3-space fence line) to the step-2 heading. Covers the
# discover table, the bullet list, and the ensure-state-meaning bullet.
PROSE_STEP1=$(mktemp)
awk '/^   ```$/{n++; next} /^2\. \*\*Probe/{exit} n>=2' "$ORCHESTRATOR_PROMPT" > "$PROSE_STEP1"

# Step 5's release section: from the step-5 heading to the step-6 heading.
PROSE_STEP5=$(mktemp)
awk '/^5\. On any/{s=1} /^6\. On a fresh/{s=0} s' "$ORCHESTRATOR_PROMPT" > "$PROSE_STEP5"

# The "## Owns" section.
PROSE_OWNS=$(mktemp)
awk '/^## Owns/{s=1} s && /^## / && !/^## Owns/{s=0} s' "$ORCHESTRATOR_PROMPT" > "$PROSE_OWNS"

# The "## What you don't do" section.
PROSE_DONT=$(mktemp)
awk '/^## What you don.t do/{s=1} s && /^## / && !/^## What/{s=0} s' "$ORCHESTRATOR_PROMPT" > "$PROSE_DONT"

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
# since sub-spec 01 the prompt's flow fence carries exactly its include
# marker line, so there is no embedded script left to extract and the tested
# code cannot drift from the file.
# =============================================================================
test_testharness_01_file_source() {
  ok=0
  [ "$FLOW_SH" = "$SCRIPT_DIR/scripts/orchestration/antz-flow.sh" ] \
    || { echo "  the suite is not running scripts/orchestration/antz-flow.sh"; ok=1; }
  # The prompt's flow fence (first 3-space fence) holds exactly the one
  # include marker line — nothing to extract.
  body=$(awk '/^   ```$/{c++; next} c==1' "$ORCHESTRATOR_PROMPT" | sed 's/^   //')
  [ "$body" = '# antz-include: scripts/orchestration/antz-flow.sh' ] \
    || { echo "  prompt flow fence is not a bare include marker: $body"; ok=1; }
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
# ensure-02: uncommitted working-tree work survives the positioning untouched
# — carried over, not destroyed or stashed.
# =============================================================================
test_ensure_02_uncommitted_work_survives() {
  new_repo carry-slug
  printf 'first\n' > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" add . && git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m base
  printf 'dirty\n' > "$REPO_ROOT/a.txt"
  out=$(run_flow ensure "$SLUG")
  [ "$out" = "state=created" ] || { echo "  expected state=created, got: $out"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "antz/$SLUG" ] \
    || { echo "  not positioned on the flow branch"; return 1; }
  [ "$(cat "$REPO_ROOT/a.txt")" = "dirty" ] \
    || { echo "  working-tree content changed"; return 1; }
  git -C "$REPO_ROOT" status --porcelain -- a.txt | grep -q '^ M a.txt' \
    || { echo "  a.txt no longer reported modified"; return 1; }
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
# ensure-05: when git refuses the positioning (a destructive-checkout
# conflict), the script stops machine-readably and forces nothing.
# =============================================================================
test_ensure_05_refused_switch_stops_clean() {
  new_repo conflict-slug
  # antz/<slug> committed a.txt at its own distinct content…
  git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  # …master commits a different content…
  printf 'two\n' > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -am master-move
  master_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
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
# orchestrator-01: step 1's ensure instructions document the new state
# meanings — created/reused imply positioned on antz/<slug> with the work
# uncommitted on that branch; checkout_refused and no_branch are documented
# stop-and-report outcomes with a user-controlled resolution; no_commits
# keeps its meaning.
# =============================================================================
test_orchestrator_01_state_meanings() {
  ok=0
  require "$PROSE_STEP1" 'state=created' || ok=1
  require "$PROSE_STEP1" 'state=reused' || ok=1
  # Both success states are described as having positioned the session.
  require "$PROSE_STEP1" 'both position the session on branch `antz/<slug>`' || ok=1
  require "$PROSE_STEP1" "the flow's work now happens on that branch, uncommitted" || ok=1
  # The refused stop and its user-controlled resolution.
  require "$PROSE_STEP1" 'state=checkout_refused' || ok=1
  require "$PROSE_STEP1" 'git refused the positioning because it would overwrite uncommitted changes' || ok=1
  require "$PROSE_STEP1" 'the user resolves the conflict themselves (e.g. commit or stash) and re-invokes' || ok=1
  require "$PROSE_STEP1" 'nothing is ever forced' || ok=1
  # The truthful failed-creation stop, documented the same way.
  require "$PROSE_STEP1" 'state=no_branch' || ok=1
  require "$PROSE_STEP1" 'the branch could not be made to exist' || ok=1
  # The unchanged unborn-repo stop.
  require "$PROSE_STEP1" 'state=no_commits' || ok=1
  require "$PROSE_STEP1" 'the repo has no commits yet' || ok=1
  return $ok
}

# =============================================================================
# orchestrator-02: step 5's human follow-up print reflects that the user is
# already on antz/<slug>, hands review/commit/merge/delete entirely to the
# user, shows the merge target only as a placeholder, and states the
# orchestrator never runs them.
# =============================================================================
test_orchestrator_02_followups() {
  ok=0
  # The user's position and the uncommitted state, visible via git status.
  require "$PROSE_STEP5" 'sits uncommitted in the working tree' || ok=1
  require "$PROSE_STEP5" 'the user sees it on branch `antz/<slug>` via `git status`' || ok=1
  # Committing is the user's whenever/how decision, not one mandated form.
  require "$PROSE_STEP5" 'whenever and however you prefer' || ok=1
  refuse "$PROSE_STEP5" 'git add -A && git commit' || ok=1
  # Merging is the user's whether-and-where decision with a placeholder target.
  require "$PROSE_STEP5" 'whether and where' || ok=1
  require "$PROSE_STEP5" 'git switch <integration> && git merge antz/<slug>' || ok=1
  # Branch deletion is the user's optional cleanup.
  require "$PROSE_STEP5" 'optional cleanup' || ok=1
  require "$PROSE_STEP5" 'git branch -d antz/<slug>' || ok=1
  # The orchestrator never runs them.
  require "$PROSE_STEP5" 'the orchestrator never runs them' || ok=1
  return $ok
}

# =============================================================================
# orchestrator-03: no concrete integration branch name appears as a merge
# target anywhere in the prompt; every merge/delete example names only
# antz/<slug> or a placeholder.
# =============================================================================
test_orchestrator_03_no_hardcoded_integration_branch() {
  ok=0
  # The placeholder is present; no hardcoded target anywhere in the prompt.
  require "$ORCHESTRATOR_PROMPT" 'git switch <integration>' || ok=1
  # "merge" appears in the prose only as the user's own action or the law's
  # "no merges" — never followed by a concrete branch name. Grep every
  # merge/branch -d mention and assert none names master/main.
  if grep -inE '(merge|branch -d)[^`]*`(master|main)`' "$ORCHESTRATOR_PROMPT" | grep -q .; then
    echo "  a concrete integration branch appears as a merge/delete target"
    grep -inE '(merge|branch -d)[^`]*`(master|main)`' "$ORCHESTRATOR_PROMPT"
    ok=1
  fi
  if grep -inE '(merge|branch -d)[^a-z/](master|main)\b' "$ORCHESTRATOR_PROMPT" | grep -q .; then
    echo "  a bare master/main appears as a merge/delete target"
    grep -inE '(merge|branch -d)[^a-z/](master|main)\b' "$ORCHESTRATOR_PROMPT"
    ok=1
  fi
  return $ok
}

# =============================================================================
# orchestrator-04: the law wording — the branch is created AND checked out
# by ensure (re-positioned on resume), still a base-commit marker with the
# work uncommitted; the destruction law names the refused checkout; the
# never-commits law survives verbatim in meaning in both sections; the
# "What you don't do" bullet confines the orchestrator to the four
# subcommands with no ad-hoc git.
# =============================================================================
test_orchestrator_04_law_wording() {
  ok=0
  # The owns section: created AND checked out, re-positioned, marker of the
  # base commit, work uncommitted.
  require "$PROSE_OWNS" 'created and checked out by the embedded script'"'"'s `ensure`' || ok=1
  require "$PROSE_OWNS" 're-positioned onto on resume' || ok=1
  require "$PROSE_OWNS" 'marker of the commit the flow started from' || ok=1
  require "$PROSE_OWNS" 'always stays uncommitted in the main checkout'"'"'s working tree' || ok=1
  # The script header's destruction law, now naming the refused checkout.
  require "$FLOW_SCRIPT" 'no reset, no merges, no branch deletes, and never a forced or overwriting checkout' || ok=1
  require "$FLOW_SCRIPT" 'refused, not forced, when it would destroy uncommitted work' || ok=1
  # Never-commits, in meaning verbatim, in both the law list and the owns section.
  require "$FLOW_SCRIPT" 'no role ever commits' || ok=1
  require "$PROSE_OWNS" 'no role ever commits' || ok=1
  # The four-subcommand boundary with no ad-hoc git.
  require "$PROSE_DONT" 'four subcommands (`discover`/`ensure`/`state`/`release`)' || ok=1
  require "$PROSE_DONT" 'no ad-hoc git' || ok=1
  return $ok
}

# =============================================================================
# orchestrator-05: everything not named by the other scenarios is unchanged —
# the release table keeps its four exact machine lines; discover keeps its
# candidate= forms; the state table keeps branch=missing; no new subcommand,
# probe, or process step was added.
# =============================================================================
test_orchestrator_05_unchanged_surface() {
  ok=0
  # The release table's four exact machine lines.
  for line in 'gate=refused reason=branch-missing' \
              'gate=refused reason=archive-missing' \
              'gate=refused reason=change-still-present' \
              'released branch='; do
    require "$PROSE_STEP5" "$line" || ok=1
  done
  # discover's candidate forms and the state table's branch=missing.
  require "$PROSE_STEP1" 'candidate=branch slug=' || ok=1
  require "$PROSE_STEP1" 'candidate=on-disk slug=' || ok=1
  require "$ORCHESTRATOR_PROMPT" 'branch=missing' || ok=1
  # Exactly four subcommands, and the four original fenced blocks (the
  # flow fence, the working-root lines block, the step-5 follow-up print
  # block, and the probe fence) survive untouched the three blocks the
  # skills-activation delegation block adds (templates for none-matched and
  # with-matches, plus the antz-skills.sh derivation snippet — see
  # spdd/changes/skills-activation/02-orchestrator.feature): seven blocks,
  # fourteen fence lines, still exactly one of them a ```sh opener.
  require "$ORCHESTRATOR_PROMPT" 'discover`/`ensure`/`state`/`release`' || ok=1
  fences=$(grep -cE '^   ```(sh)?$' "$ORCHESTRATOR_PROMPT")
  [ "$fences" = "14" ] || { echo "  expected 14 fence lines (7 blocks), got: $fences"; ok=1; }
  shfences=$(grep -c '^   ```sh$' "$ORCHESTRATOR_PROMPT")
  [ "$shfences" = "1" ] || { echo "  expected exactly 1 probe fence, got: $shfences"; ok=1; }
  # No new process step: the numbered steps still end at 6.
  require "$ORCHESTRATOR_PROMPT" '6. On a fresh rejection' || ok=1
  if grep -qE '^7\. ' "$ORCHESTRATOR_PROMPT"; then
    echo "  a new process step appeared"; ok=1
  fi
  return $ok
}

# ---- run ----------------------------------------------------------------------

run_test "ensure-extracted: the flow script is loaded from scripts/orchestration/antz-flow.sh and parses as POSIX sh" test_ensure_extracted
run_test "testharness-01: the flow suite loads scripts/orchestration/antz-flow.sh as a file (no extraction from the prompt)" test_testharness_01_file_source
run_test "ensure-01: ensure creates the branch at HEAD and positions the session" test_ensure_01_fresh_creates_and_positions
run_test "ensure-02: uncommitted working-tree work survives the positioning" test_ensure_02_uncommitted_work_survives
run_test "ensure-03: resume positions onto the existing branch without rewriting it" test_ensure_03_resume_positions_without_rewriting
run_test "ensure-04: re-running ensure while positioned is a safe no-op" test_ensure_04_ensure_again_is_noop
run_test "ensure-05: a refused switch stop-state alters nothing" test_ensure_05_refused_switch_stops_clean
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

run_test "orchestrator-01: step 1's ensure instructions document the new state meanings" test_orchestrator_01_state_meanings
run_test "orchestrator-02: step 5's human follow-up print is user-controlled with a placeholder merge target" test_orchestrator_02_followups
run_test "orchestrator-03: no concrete integration branch name appears as a merge target anywhere" test_orchestrator_03_no_hardcoded_integration_branch
run_test "orchestrator-04: the law wording reflects the checkout contract" test_orchestrator_04_law_wording
run_test "orchestrator-05: the unchanged surface stays unchanged" test_orchestrator_05_unchanged_surface

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
rm -f "$PROSE_STEP1" "$PROSE_STEP5" "$PROSE_OWNS" "$PROSE_DONT"
[ "$fail_count" -eq 0 ]
