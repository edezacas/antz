#!/usr/bin/env sh
# tests/antz-flow_test.sh -- the owning suite for
# scripts/orchestration/antz-flow.sh, the flow's only git mutation.
#
# Contract under test (spdd/specs/flow.md, scenarios flow-01..flow-08): the
# single "start <slug>" subcommand validates the slug mechanically, runs its
# git preflight, refuses a new flow on a dirty tree while letting a resume
# through, creates and checks out the marker branch antz/<slug> (or reuses
# it), and prints exactly one machine line. It never commits, never forces a
# checkout, and never removes anything: every assertion below is made against
# throwaway git repos under temp space and a full branch-ref snapshot taken
# before and after each run.
#
# Run:  sh tests/antz-flow_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FLOW_SH="$SCRIPT_DIR/scripts/orchestration/antz-flow.sh"

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
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
}

# ---- git fixtures ------------------------------------------------------------

REPO_ROOT=""
SLUG=""
TMP_REPOS=""

add_tmp_repo() { TMP_REPOS="$TMP_REPOS $1"; }

new_repo() {
  REPO_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/antz-flow.XXXXXX")
  add_tmp_repo "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  echo hello > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" add .
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m init
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = master ] \
    || git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t branch -m master
  SLUG="$1"
}

new_repo_no_commit() {
  REPO_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/antz-flow.XXXXXX")
  add_tmp_repo "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  SLUG="$1"
}

run_flow() {
  ( cd "$REPO_ROOT" && sh "$FLOW_SH" "$@" )
}

mk_change_dir() {
  mkdir -p "$REPO_ROOT/spdd/changes/$SLUG"
  echo "# spec" > "$REPO_ROOT/spdd/changes/$SLUG/01-api.feature"
}

all_refs() { git -C "$REPO_ROOT" show-ref --heads; }

cleanup() {
  for d in $TMP_REPOS; do rm -rf "$d"; done
  return 0
}
trap cleanup EXIT

# ---- flow-01: a valid slug on a new flow -------------------------------------

test_flow_01_creates_and_positions() {
  new_repo cli-flag
  out=$(run_flow start "$SLUG")
  echo "$out" | grep -qx 'state=started root=.*' || { echo "  unexpected output: $out"; return 1; }
  git -C "$REPO_ROOT" show-ref --verify --quiet refs/heads/antz/cli-flag \
    || { echo "  branch antz/cli-flag missing"; return 1; }
  [ "$(git -C "$REPO_ROOT" branch --show-current)" = "antz/cli-flag" ] \
    || { echo "  not positioned on the marker branch"; return 1; }
}

test_flow_01_reports_absolute_root() {
  new_repo cli-flag
  out=$(run_flow start "$SLUG")
  printf '%s\n' "$out" | grep -qx "state=started root=$REPO_ROOT" \
    || { echo "  root mismatch: $out (expected $REPO_ROOT)"; return 1; }
}

test_flow_01_forty_char_slug_is_valid() {
  new_repo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  out=$(run_flow start "$SLUG")
  echo "$out" | grep -qx 'state=started root=.*' || { echo "  40-char slug refused: $out"; return 1; }
}

# ---- flow-02: reuse ----------------------------------------------------------

test_flow_02_reuses_without_moving_anything() {
  new_repo cli-flag
  run_flow start "$SLUG" >/dev/null
  before=$(all_refs)
  out=$(run_flow start "$SLUG")
  after=$(all_refs)
  echo "$out" | grep -qx 'state=reused root=.*' || { echo "  unexpected output: $out"; return 1; }
  echo "$out" | grep -q '^dirty=yes$' && { echo "  dirty=yes on a clean tree"; return 1; }
  [ "$before" = "$after" ] || { echo "  refs changed on reuse"; return 1; }
}

test_flow_02_dirty_reuse_appends_dirty() {
  new_repo cli-flag
  run_flow start "$SLUG" >/dev/null
  echo change >> "$REPO_ROOT/a.txt"
  out=$(run_flow start "$SLUG")
  echo "$out" | grep -qx 'state=reused root=.*' || { echo "  unexpected output: $out"; return 1; }
  echo "$out" | grep -qx 'dirty=yes' || { echo "  missing dirty=yes: $out"; return 1; }
}

# ---- flow-03: mechanical slug rejection --------------------------------------

reject_slug() {
  # $1 = slug to try, $2 = human label
  new_repo x
  before=$(all_refs)
  out=$(run_flow start "$1" 2>&1) && { echo "  $2 was accepted: $out"; return 1; }
  echo "$out" | grep -qx 'state=bad_slug' || { echo "  $2 gave: $out"; return 1; }
  [ "$before" = "$(all_refs)" ] || { echo "  $2 moved refs"; return 1; }
  [ -d "$REPO_ROOT/.git/refs/heads/antz" ] && { echo "  $2 created an antz branch"; return 1; }
  return 0
}

test_flow_03_empty()        { reject_slug '' 'empty slug'; }
test_flow_03_leading()      { reject_slug '-leading' 'leading hyphen'; }
test_flow_03_trailing()     { reject_slug 'trailing-' 'trailing hyphen'; }
test_flow_03_double()       { reject_slug 'double--hyphen' 'doubled hyphen'; }
test_flow_03_uppercase()    { reject_slug 'Uppercase' 'uppercase letters'; }
test_flow_03_underscore()   { reject_slug 'under_score' 'underscore'; }
test_flow_03_dot()          { reject_slug 'a.b' 'dot'; }
test_flow_03_too_long()     { reject_slug 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' '41 characters'; }

# ---- flow-04: preflight states ----------------------------------------------

test_flow_04_no_git() {
  new_repo cli-flag
  out=$( cd "$REPO_ROOT" && PATH=/nonexistent /bin/sh "$FLOW_SH" start cli-flag 2>&1 )
  echo "$out" | grep -qx 'state=no_git' || { echo "  gave: $out"; return 1; }
}

test_flow_04_no_repo() {
  d=$(mktemp -d "${TMPDIR:-/tmp}/antz-norepo.XXXXXX")
  add_tmp_repo "$d"
  out=$( cd "$d" && sh "$FLOW_SH" start cli-flag 2>&1 )
  echo "$out" | grep -qx 'state=no_repo' || { echo "  gave: $out"; return 1; }
}

test_flow_04_no_commits() {
  new_repo_no_commit cli-flag
  out=$(run_flow start "$SLUG" 2>&1)
  echo "$out" | grep -qx 'state=no_commits' || { echo "  gave: $out"; return 1; }
  git -C "$REPO_ROOT" show-ref --verify --quiet refs/heads/antz/cli-flag \
    && { echo "  branch created on an unborn repo"; return 1; }
  return 0
}

# ---- flow-05: the new-flow tree guard ---------------------------------------

test_flow_05_dirty_tree_refused_on_new_flow() {
  new_repo cli-flag
  echo untracked > "$REPO_ROOT/notes.txt"
  before=$(all_refs)
  out=$(run_flow start "$SLUG" 2>&1) && { echo "  dirty start accepted: $out"; return 1; }
  echo "$out" | grep -qx 'state=tree_dirty' || { echo "  gave: $out"; return 1; }
  [ "$before" = "$(all_refs)" ] || { echo "  refs moved on refusal"; return 1; }
}

test_flow_05_dirty_tree_allowed_once_change_dir_exists() {
  new_repo cli-flag
  echo untracked > "$REPO_ROOT/notes.txt"
  mk_change_dir
  out=$(run_flow start "$SLUG")
  echo "$out" | grep -qx 'state=started root=.*' || { echo "  resume refused: $out"; return 1; }
}

# ---- flow-06: a refused checkout is never forced ----------------------------

test_flow_06_checkout_refused() {
  new_repo cli-flag
  git -C "$REPO_ROOT" branch antz/cli-flag
  git -C "$REPO_ROOT" switch -q antz/cli-flag
  echo branch-side > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -am branch
  git -C "$REPO_ROOT" switch -q master
  echo worktree-side > "$REPO_ROOT/a.txt"
  before=$(cat "$REPO_ROOT/a.txt")
  out=$(run_flow start "$SLUG" 2>&1) && { echo "  refused switch reported success: $out"; return 1; }
  echo "$out" | grep -qx 'state=checkout_refused' || { echo "  gave: $out"; return 1; }
  [ "$(cat "$REPO_ROOT/a.txt")" = "$before" ] || { echo "  working tree was overwritten"; return 1; }
}

# ---- static: nothing destructive, one subcommand -----------------------------

test_static_no_destructive_verbs() {
  for token in 'git commit' 'git reset' 'git worktree' 'git stash' 'git push' 'branch -d' 'branch -D' 'show-ref --delete' 'checkout -f' 'switch -f'; do
    if grep -qF -- "$token" "$FLOW_SH"; then
      echo "  found destructive token: $token"
      return 1
    fi
  done
  return 0
}

test_static_rejects_unknown_subcommand() {
  new_repo cli-flag
  out=$(run_flow discover 2>&1) && { echo "  unknown subcommand accepted: $out"; return 1; }
  echo "$out" | grep -q 'usage:' || { echo "  no usage on unknown subcommand: $out"; return 1; }
}

test_static_requires_slug() {
  new_repo cli-flag
  run_flow start 2>&1 >/dev/null && { echo "  missing slug accepted"; return 1; }
  return 0
}

# ---- registration ------------------------------------------------------------

run_test "flow-01: start creates the marker branch and positions the session" test_flow_01_creates_and_positions
run_test "flow-01: start prints the absolute repo root" test_flow_01_reports_absolute_root
run_test "flow-01: a 40-character slug is valid" test_flow_01_forty_char_slug_is_valid
run_test "flow-02: reuse prints state=reused and moves nothing" test_flow_02_reuses_without_moving_anything
run_test "flow-02: a dirty reuse appends the advisory dirty=yes" test_flow_02_dirty_reuse_appends_dirty
run_test "flow-03: an empty slug is bad_slug" test_flow_03_empty
run_test "flow-03: a leading hyphen is bad_slug" test_flow_03_leading
run_test "flow-03: a trailing hyphen is bad_slug" test_flow_03_trailing
run_test "flow-03: a doubled hyphen is bad_slug" test_flow_03_double
run_test "flow-03: uppercase letters are bad_slug" test_flow_03_uppercase
run_test "flow-03: an underscore is bad_slug" test_flow_03_underscore
run_test "flow-03: a dot is bad_slug" test_flow_03_dot
run_test "flow-03: a 41-character slug is bad_slug" test_flow_03_too_long
run_test "flow-04: git absent fail-closes state=no_git" test_flow_04_no_git
run_test "flow-04: not a repository fail-closes state=no_repo" test_flow_04_no_repo
run_test "flow-04: an unborn repository fail-closes state=no_commits" test_flow_04_no_commits
run_test "flow-05: a dirty tree refuses a new flow" test_flow_05_dirty_tree_refused_on_new_flow
run_test "flow-05: the same dirty tree starts once the change dir exists" test_flow_05_dirty_tree_allowed_once_change_dir_exists
run_test "flow-06: a refused checkout stops clean and overwrites nothing" test_flow_06_checkout_refused
run_test "flow-static: the script carries no destructive git verb" test_static_no_destructive_verbs
run_test "flow-static: an unknown subcommand is refused with usage" test_static_rejects_unknown_subcommand
run_test "flow-static: a missing slug is refused" test_static_requires_slug

echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
