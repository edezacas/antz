#!/usr/bin/env bash
# Unit tests for the antz-flow.sh fence embedded in
# agents/prompts/orchestrator.prompt (step 1's discover/ensure and step 5's
# release gate) — the branch-marked, never-committed variant: each change
# gets its own marker branch antz/<slug> and nothing is ever committed or
# removed, so the script computes purely mechanical, disk-derivable facts —
# which antz/* branches exist in the main checkout, what change state sits
# uncommitted in its working tree, and whether the release gate holds.
#
# Helpers are exercised against throwaway git repos under a temp dir; every
# scenario id carries the flow-<n> prefix the sub-spec convention expects.
#
# Self-contained bash test harness, mirroring the harness style of
# tests/orchestrator-status-probe_test.sh. Run:
#   ./tests/antz-flow_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ORCHESTRATOR_PROMPT="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"

pass_count=0
fail_count=0

SCRIPT=$(mktemp)
PROBE_EXTRACT=$(mktemp)

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

# ---- extracting the embedded scripts from the prompt ------------------------

extract_flow() {
  # The flow fence is the prompt's first 3-space-``` fence (the probe is the
  # ```sh fence; its shape is guarded by
  # tests/orchestrator-status-probe_test.sh).
  awk '/^   ```$/{c++; next} c==1' "$ORCHESTRATOR_PROMPT"
}

extract_flow > "$SCRIPT"

# The probe is embedded verbatim (its extraction is what
# orchestrator-status-probe_test.sh guards), and `state` runs it via the
# flow script's state subcommand, so we do the same for the state tests.
awk '/^   ```sh$/{p=1; next} /^   ```$/{p=0} p' "$ORCHESTRATOR_PROMPT" | sed 's/^   //' > "$PROBE_EXTRACT"

# ---- tiny git fixture --------------------------------------------------------

REPO_ROOT=""
SLUG=""

new_repo() {
  REPO_ROOT=$(mktemp -d)
  add_tmp_repo "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  # Branch creation needs at least one commit (the script itself
  # fail-closes on a repo with no commits -- tested explicitly via
  # git rev-parse HEAD).
  echo hello > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" add .
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m init
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
  ( cd "$REPO_ROOT" && sh "$SCRIPT" "$@" )
}

run_state_through_flow() {
  ( cd "$REPO_ROOT" && sh "$SCRIPT" state "$SLUG" "$PROBE_EXTRACT" )
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

# ---- fixture teardown --------------------------------------------------------

# Every tmp repo ever created, space-separated (POSIX sh: no arrays). cleanup
# removes them all on EXIT — without the accumulation, only the last repo
# would be deleted and each test would orphan its mktemp dir.
TMP_REPOS=""

add_tmp_repo() {
  TMP_REPOS="$TMP_REPOS $1"
}

cleanup() {
  rm -f "$SCRIPT" "$PROBE_EXTRACT"
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
# flow-extracted: the script was actually found and extracted (guards every
# other test against a silent no-op if the fence markers ever change shape).
# =============================================================================
test_flow_extracted() {
  grep -q 'br_exists' "$SCRIPT" || { echo "  flow script didn't extract"; return 1; }
  return 0
}

# =============================================================================
# flow-01: discover with no antz/* branches and no change dirs prints nothing.
# =============================================================================
test_flow_discover_empty() {
  new_repo fresh-slug
  out=$(run_flow discover)
  [ -z "$out" ] || { echo "  expected no candidates, got: $out"; return 1; }
}

# =============================================================================
# flow-02: discover lists a marker branch (candidate=branch) and an on-disk
# change dir (candidate=on-disk).
# =============================================================================
test_flow_discover_lists() {
  new_repo listed-slug
  git -C "$REPO_ROOT" branch -q antz/listed-slug
  mk_change_dir
  out=$(run_flow discover)
  printf '%s\n' "$out" | grep -qx 'candidate=branch slug=listed-slug' \
    || { echo "  missing candidate=branch in: $out"; return 1; }
  printf '%s\n' "$out" | grep -qx 'candidate=on-disk slug=listed-slug' \
    || { echo "  missing candidate=on-disk in: $out"; return 1; }
}

# =============================================================================
# flow-03: ensure with no existing marker branch creates it (state=created),
# pointing at the repo's current HEAD.
# =============================================================================
test_flow_ensure_creates() {
  new_repo new-slug
  out=$(run_flow ensure "$SLUG")
  [ "$out" = "state=created" ] || { echo "  expected state=created, got: $out"; return 1; }
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/antz/$SLUG" \
    || { echo "  branch not created"; return 1; }
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$(git -C "$REPO_ROOT" rev-parse "antz/$SLUG")" ] \
    || { echo "  marker branch doesn't point at HEAD"; return 1; }
}

# =============================================================================
# flow-03-bis: nothing is ever checked out — the caller's branch is untouched.
# =============================================================================
test_flow_ensure_no_checkout() {
  new_repo stay-slug
  git -C "$REPO_ROOT" branch -q marker-baseHEAD
  before=$(git -C "$REPO_ROOT" branch --show-current)
  run_flow ensure "$SLUG" >/dev/null
  after=$(git -C "$REPO_ROOT" branch --show-current)
  [ "$before" = "$after" ] || { echo "  checkout moved: $before -> $after"; return 1; }
}

# =============================================================================
# flow-04: ensure with an existing marker branch reports state=reused and
# never rewrites it (no -B semantics on hidden refs).
# =============================================================================
test_flow_ensure_reused() {
  new_repo reuse-slug
  git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  out=$(run_flow ensure "$SLUG")
  [ "$out" = "state=reused" ] || { echo "  expected state=reused, got: $out"; return 1; }
}

# =============================================================================
# flow-06: ensure in a repo with no commits fail-closes state=no_commits.
# =============================================================================
test_flow_ensure_no_commits() {
  new_repo_no_commit unborn-slug
  out=$(run_flow ensure "$SLUG")
  [ "$out" = "state=no_commits" ] || { echo "  expected state=no_commits, got: $out"; return 1; }
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/antz/$SLUG" \
    && { echo "  branch created despite no commits"; return 1; }
  return 0
}

# =============================================================================
# flow-07: state runs the probe verbatim with CHANGE_DIR pointed at the main
# checkout's spdd/changes/<slug>.
# =============================================================================
test_flow_state_runs_probe() {
  new_repo probe-slug
  git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  mk_change_dir
  out=$(run_state_through_flow)
  printf '%s\n' "$out" | grep -qx "working_root=$REPO_ROOT" \
    || { echo "  missing working_root line in: $out"; return 1; }
  printf '%s\n' "$out" | grep -q '^open_questions=no$' \
    || { echo "  probe didn't run against CHANGE_DIR: $out"; return 1; }
}

# =============================================================================
# flow-09: state fail-closes with branch=missing when the marker branch
# doesn't exist.
# =============================================================================
test_flow_state_fails_without_branch() {
  new_repo ghost-slug
  out=$(run_state_through_flow)
  [ "$out" = "branch=missing" ] || { echo "  expected branch=missing, got: $out"; return 1; }
}

# =============================================================================
# flow-10/prefix: release fail-closes on every gate combination, and never
# touches anything on any refusal.
# =============================================================================
test_flow_release_gate_archive_missing() {
  new_repo gate-slug
  git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  out=$(run_flow release "$SLUG")
  [ "$out" = "gate=refused reason=archive-missing" ] \
    || { echo "  expected archive-missing, got: $out"; return 1; }
}

test_flow_release_gate_change_still_present() {
  new_repo gate-slug
  git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  mk_change_dir; mk_archive
  out=$(run_flow release "$SLUG")
  [ "$out" = "gate=refused reason=change-still-present" ] \
    || { echo "  expected change-still-present, got: $out"; return 1; }
}

test_flow_release_gate_branch_missing() {
  new_repo gate-slug
  mk_archive
  out=$(run_flow release "$SLUG")
  [ "$out" = "gate=refused reason=branch-missing" ] \
    || { echo "  expected branch-missing, got: $out"; return 1; }
}

# =============================================================================
# flow-12: release after the gate holds reports the branch and removes
# nothing, ever.
# =============================================================================
test_flow_release_releases_and_keeps_everything() {
  new_repo rel-slug
  git -C "$REPO_ROOT" branch -q "antz/$SLUG"
  mk_archive
  out=$(run_flow release "$SLUG")
  [ "$out" = "released branch=antz/$SLUG" ] \
    || { echo "  expected released branch=..., got: $out"; return 1; }
  git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/antz/$SLUG" \
    || { echo "  branch didn't survive release"; return 1; }
  [ -d "$REPO_ROOT/spdd/archive/$SLUG" ] \
    || { echo "  archive was removed despite the contract"; return 1; }
}

# =============================================================================
# flow-13: no subcommand ever commits — git's HEAD and status hold steady
# across ensure/state/release.
# =============================================================================
test_flow_never_commits() {
  new_repo noc-1-slug
  mk_change_dir
  run_flow ensure "$SLUG" >/dev/null
  ( cd "$REPO_ROOT" && sh "$SCRIPT" state "$SLUG" "$PROBE_EXTRACT" >/dev/null )
  run_flow release "$SLUG" >/dev/null 2>&1
  [ "$(git -C "$REPO_ROOT" rev-list --count HEAD)" = "1" ] \
    || { echo "  HEAD grew: a commit happened"; return 1; }
  git -C "$REPO_ROOT" cat-file -e "refs/heads/antz/$SLUG" 2>/dev/null
  [ "$(git -C "$REPO_ROOT" rev-parse "refs/heads/antz/$SLUG")" = "$(git -C "$REPO_ROOT" rev-parse HEAD)" ] \
    || { echo "  marker branch moved off HEAD"; return 1; }
}

# =============================================================================
# flow-18/19 (ported from the worktree variant's suite): preflight
# fail-closes discover and ensure when git is absent from the environment
# (sanitized PATH) or the directory is not a git repository.
# =============================================================================
test_flow_preflight_no_git() {
  new_repo nogit-slug
  SHELLSH=$(command -v sh)
  out=$(PATH="/nonexistent" "$SHELLSH" "$SCRIPT" discover 2>/dev/null)
  [ "$out" = "state=no_git" ] || { echo "  expected state=no_git, got: $out"; return 1; }
  out=$(PATH="/nonexistent" "$SHELLSH" "$SCRIPT" ensure "nogit-slug" 2>/dev/null)
  [ "$out" = "state=no_git" ] || { echo "  expected state=no_git, got: $out"; return 1; }
}

test_flow_preflight_no_repo() {
  nonrepo=$(mktemp -d)
  add_tmp_repo "$nonrepo"
  out=$( cd "$nonrepo" && sh "$SCRIPT" discover 2>/dev/null )
  [ "$out" = "state=no_repo" ] || { echo "  expected state=no_repo, got: $out"; return 1; }
  # ensure fail-closes the same way from a non-repo.
  out=$( cd "$nonrepo" && sh "$SCRIPT" ensure no-repo-slug 2>/dev/null )
  [ "$out" = "state=no_repo" ] || { echo "  expected state=no_repo, got: $out"; return 1; }
}

# ---- run ----------------------------------------------------------------------

run_test "flow-extracted: the embedded flow script extracts from the prompt" test_flow_extracted
run_test "flow-01: discover prints nothing with no branches and no change dirs" test_flow_discover_empty
run_test "flow-02: discover lists marker branches and on-disk change dirs" test_flow_discover_lists
run_test "flow-03: ensure creates the marker branch at HEAD (state=created)" test_flow_ensure_creates
run_test "flow-03-bis: ensure never checks anything out" test_flow_ensure_no_checkout
run_test "flow-04: ensure on an existing marker branch reports state=reused" test_flow_ensure_reused
run_test "flow-06: ensure fail-closes state=no_commits on an unborn repo" test_flow_ensure_no_commits
run_test "flow-07: state runs the probe with CHANGE_DIR in the main checkout" test_flow_state_runs_probe
run_test "flow-09: state fail-closes branch=missing without the marker branch" test_flow_state_fails_without_branch
run_test "flow-10: release refuses when the archive is missing" test_flow_release_gate_archive_missing
run_test "flow-11: release refuses when the change dir is still present" test_flow_release_gate_change_still_present
run_test "flow-11b: release refuses when the marker branch is missing" test_flow_release_gate_branch_missing
run_test "flow-12: release reports the branch and removes nothing, ever" test_flow_release_releases_and_keeps_everything
run_test "flow-13: no subcommand ever commits anything" test_flow_never_commits
run_test "flow-18: preflight fail-closes with state=no_git" test_flow_preflight_no_git
run_test "flow-19: preflight fail-closes with state=no_repo" test_flow_preflight_no_repo

echo
echo "pass=$pass_count fail=$fail_count"
[ "$fail_count" -eq 0 ]
