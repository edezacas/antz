#!/usr/bin/env bash
# Unit tests for the antz-flow.sh fence embedded in
# agents/prompts/orchestrator.prompt (step 1's discover/ensure and step 5's
# release gate). The script computes purely mechanical, disk-derivable facts —
# which antz/* branches and worktrees exist, which state they're in, and
# whether the release gate holds — so the orchestrator prompt itself doesn't
# have to spell out that procedure in prose.
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
  # The flow fence is the prompt's only zero-indent ``` fence (the probe is
  # the 3-space ```sh fence; its shape is guarded by
  # tests/orchestrator-status-probe_test.sh).
  awk '/^   ```$/{c++; next} c==1' "$ORCHESTRATOR_PROMPT"
}

extract_flow > "$SCRIPT"

# The probe is embedded verbatim (its extraction is what
# orchestrator-status-probe_test.sh guards), and `state` subcommand runs it
# from inside the isolation, so we do the same for the state tests.
awk '/^   ```sh$/{p=1; next} /^   ```$/{p=0} p' "$ORCHESTRATOR_PROMPT" | sed 's/^   //' > "$PROBE_EXTRACT"

# ---- tiny git fixture --------------------------------------------------------

REPO_ROOT=""
WORKING_ROOT=""
SLUG=""

new_repo() {
  REPO_ROOT=$(mktemp -d)
  add_tmp_repo "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  # A work-tree creation needs at least one commit (the script itself
  # fail-closes on a repo with no commits -- tested explicitly via
  # git rev-parse HEAD).
  echo hello > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" add .
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m init
  SLUG="$1"
  WORKING_ROOT="$REPO_ROOT/.worktrees/$SLUG"
}

new_repo_no_commit() {
  REPO_ROOT=$(mktemp -d)
  add_tmp_repo "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  SLUG="$1"
  WORKING_ROOT="$REPO_ROOT/.worktrees/$SLUG"
}

run_flow() {
  # $@ = flow subcommand + args; runs from the main checkout.
  ( cd "$REPO_ROOT" && sh "$SCRIPT" "$@" )
}

run_state_through_flow() {
  ( cd "$REPO_ROOT" && sh "$SCRIPT" state "$SLUG" "$PROBE_EXTRACT" )
}

mk_archive() {
  # Simulate what a passing verifier's Merge & Archive leaves on disk:
  # spdd/archive/<slug> present, spdd/changes/<slug> gone, all committed.
  mkdir -p "$WORKING_ROOT/spdd/archive/$SLUG"
  echo ok > "$WORKING_ROOT/spdd/archive/$SLUG/x.md"
  git -C "$WORKING_ROOT" add -A
  git -C "$WORKING_ROOT" -c user.email=t@t -c user.name=t commit -q -m archive
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
  WORKING_ROOT=""
  SLUG=""
}
trap cleanup EXIT

# =============================================================================
# flow-extracted: the script was actually found and extracted (guards every
# other test against a silent no-op if the fence markers ever change shape).
# =============================================================================
test_flow_extracted() {
  grep -q 'wt_is_registered' "$SCRIPT" || { echo "  flow script didn't extract"; return 1; }
  return 0
}

# =============================================================================
# flow-01: discover with no antz/* branches prints nothing, exits 0.
# =============================================================================
test_flow_discover_empty() {
  new_repo fresh-slug
  out=$(run_flow discover)
  [ -z "$out" ] || { echo "  expected no candidates, got: $out"; return 1; }
}

# =============================================================================
# flow-02: ensure with neither branch nor dir creates branch + worktree.
# =============================================================================
test_flow_ensure_creates() {
  new_repo flow-ensure-creates
  out=$(run_flow ensure "$SLUG")
  case "$out" in
    "state=created path=$WORKING_ROOT") ;;
    *) echo "  expected state=created at $WORKING_ROOT, got: $out"; return 1 ;;
  esac
  [ -e "$WORKING_ROOT/.git" ] || { echo "  worktree dir not created"; return 1; }
  git -C "$REPO_ROOT" rev-parse --verify -q refs/heads/antz/"$SLUG" >/dev/null \
    || { echo "  branch not created"; return 1; }
}

# =============================================================================
# flow-03: ensure is idempotent — a second run on the same slug reuses.
# =============================================================================
test_flow_ensure_reuses() {
  new_repo flow-ensure-reuses
  run_flow ensure "$SLUG" >/dev/null
  out=$(run_flow ensure "$SLUG")
  case "$out" in
    "state=reused path=$WORKING_ROOT") ;;
    *) echo "  expected state=reused, got: $out"; return 1 ;;
  esac
}

# =============================================================================
# flow-04: branch exists but no registration/dir (deleted by hand) attaches.
# =============================================================================
test_flow_ensure_attaches_deleted_branch() {
  new_repo flow-ensure-attach
  run_flow ensure "$SLUG" >/dev/null
  git -C "$REPO_ROOT" worktree remove --force "$WORKING_ROOT" # leaves a stale entry
  # Prune stale registrations so the branch is branch-only, then ensure = attach.
  # (No -q: `git worktree prune` doesn't support --quiet.)
  git -C "$REPO_ROOT" worktree prune
  out=$(run_flow ensure "$SLUG")
  case "$out" in
    "state=attached path=$WORKING_ROOT") ;;
    *) echo "  expected state=attached, got: $out"; return 1 ;;
  esac
}

# =============================================================================
# flow-05: no unicode parenthesis — a plain dir at the worktree path that git
# doesn't register fail-closes with state=conflict, never created over.
# =============================================================================
test_flow_ensure_conflicts_on_plain_dir() {
  new_repo flow-ensure-conflict
  mkdir -p "$WORKING_ROOT"
  echo left-over > "$WORKING_ROOT/stale-content-marker"
  out=$(run_flow ensure "$SLUG")
  case "$out" in
    "state=conflict path=$WORKING_ROOT") ;;
    *) echo "  expected state=conflict, got: $out"; return 1 ;;
  esac
  [ -f "$WORKING_ROOT/stale-content-marker" ] \
    || { echo "  leftover dir contents were destroyed"; return 1; }
}

# =============================================================================
# flow-06: a repo with zero commits fail-closes with state=no_commits.
# =============================================================================
test_flow_ensure_fails_without_commits() {
  new_repo_no_commit flow-no-commit
  out=$(run_flow ensure "$SLUG")
  [ "$out" = "state=no_commits" ] || { echo "  expected state=no_commits, got: $out"; return 1; }
  [ ! -e "$WORKING_ROOT" ] || { echo "  worktree dir shouldn't exist"; return 1; }
}

# =============================================================================
# flow-07: ensure registeres .worktrees/ repo-locally in info/exclude, never
# touching the project's .gitignore.
# =============================================================================
test_flow_exclude_registered() {
  new_repo flow-exclude
  run_flow ensure "$SLUG" >/dev/null
  grep -qx '.worktrees/' "$(git -C "$REPO_ROOT" rev-parse --git-path info/exclude)" \
    || { echo "  .worktrees/ not in info/exclude"; return 1; }
  [ ! -f "$REPO_ROOT/.gitignore" ] || { echo "  host .gitignore was touched"; return 1; }
}

# =============================================================================
# flow-08: state runs the probe verbatim with CHANGE_DIR inside the worktree
# (the isolated branch state), matching the orchestrator prompt's probe
# outputs. With the change dir absent over there, probe reports missing.
# =============================================================================
test_flow_state_runs_probe() {
  new_repo flow-state
  run_flow ensure "$SLUG" >/dev/null
  out=$(run_flow state "$SLUG" "$PROBE_EXTRACT")
  case "$out" in
    "working_root=$WORKING_ROOT"* ) : ;;
    *) echo "  missing working_root line, got: $out"; return 1 ;;
  esac
  echo "$out" | grep -qxF 'change_dir=missing' \
    || { echo "  expected change_dir=missing from probe, got: $out"; return 1; }
}

# =============================================================================
# flow-09: state with an unregistered path reports worktree=missing.
# =============================================================================
test_flow_state_fails_without_worktree() {
  new_repo flow-state-missing
  out=$(run_state_through_flow "$SLUG")
  [ "$out" = "worktree=missing" ] || { echo "  expected worktree=missing, got: $out"; return 1; }
}

# =============================================================================
# flow-10: release refuses when spdd/archive/<slug> is missing on disk, and
# leaves the worktree in place (never speculative removal).
# =============================================================================
test_flow_release_refused_without_archive() {
  new_repo flow-release-refuse
  run_flow ensure "$SLUG" >/dev/null
  mkdir -p "$WORKING_ROOT/spdd/changes/$SLUG"
  echo stub > "$WORKING_ROOT/spdd/changes/$SLUG/s.feature"
  git -C "$WORKING_ROOT" add -A
  git -C "$WORKING_ROOT" -c user.email=t@t -c user.name=t commit -q -m change
  out=$(run_flow release "$SLUG" "$WORKING_ROOT")
  [ "$out" = "gate=refused reason=archive-missing" ] \
    || { echo "  expected archive-missing gate, got: $out"; return 1; }
  [ -d "$WORKING_ROOT" ] || { echo "  worktree was removed despite gate"; return 1; }
}

# =============================================================================
# flow-11: release refuses when spdd/changes/<slug> is still present.
# =============================================================================
test_flow_release_refused_with_changes_present() {
  new_repo flow-release-change
  run_flow ensure "$SLUG" >/dev/null
  mkdir -p "$WORKING_ROOT/spdd/archive/$SLUG" "$WORKING_ROOT/spdd/changes/$SLUG"
  echo ok > "$WORKING_ROOT/spdd/archive/$SLUG/x.md"
  echo still > "$WORKING_ROOT/spdd/changes/$SLUG/y.md"
  git -C "$WORKING_ROOT" add -A
  git -C "$WORKING_ROOT" -c user.email=t@t -c user.name=t commit -q -m both
  out=$(run_flow release "$SLUG" "$WORKING_ROOT")
  [ "$out" = "gate=refused reason=change-still-present" ] \
    || { echo "  expected change-still-present gate, got: $out"; return 1; }
  [ -d "$WORKING_ROOT" ] || { echo "  worktree was removed despite gate"; return 1; }
}

# =============================================================================
# flow-12: release removes the worktree after the gate holds and the branch
# survives (the branch is what the human later merges and deletes).
# =============================================================================
test_flow_release_holds_gate_and_keeps_branch() {
  new_repo flow-release-ok
  run_flow ensure "$SLUG" >/dev/null
  mk_archive
  out=$(run_flow release "$SLUG" "$WORKING_ROOT")
  [ "$out" = "released path=$WORKING_ROOT" ] \
    || { echo "  expected released path=..., got: $out"; return 1; }
  [ ! -d "$WORKING_ROOT" ] || { echo "  worktree survived release"; return 1; }
  git -C "$REPO_ROOT" rev-parse --verify -q refs/heads/antz/"$SLUG" >/dev/null \
    || { echo "  branch didn't survive release"; return 1; }
}

# =============================================================================
# flow-13: release with a mistyped/mismatched path refuses on the path check.
# =============================================================================
test_flow_release_refused_on_path_mismatch() {
  new_repo flow-release-mismatch
  run_flow ensure "$SLUG" >/dev/null
  mk_archive
  out=$(run_flow release "$SLUG" "$REPO_ROOT/.worktrees/wrong-slug")
  [ "$out" = "gate=refused reason=path-mismatch" ] \
    || { echo "  expected path-mismatch gate, got: $out"; return 1; }
  [ -d "$WORKING_ROOT" ] || { echo "  worktree was removed despite gate"; return 1; }
}

# =============================================================================
# flow-14: discover reports the candidate once a worktree exists.
# =============================================================================
test_flow_discover_reports_candidate() {
  new_repo flow-discover
  run_flow ensure "$SLUG" >/dev/null
  out=$(run_flow discover)
  case "$out" in
    "candidate=ready slug=$SLUG path=$WORKING_ROOT change="*) ;;
    *) echo "  expected a ready candidate, got: $out"; return 1 ;;
  esac
}

# =============================================================================
# flow-15: after release, discover doesn't list the removed worktree anymore
# (the branch's tree state says archived, but the worktree is gone — the
# orchestrator's own flow sees this as an orphan branch).
# =============================================================================
test_flow_discover_after_release_is_orphan() {
  new_repo flow-discover-post-release
  run_flow ensure "$SLUG" >/dev/null
  mk_archive
  run_flow release "$SLUG" "$WORKING_ROOT" >/dev/null
  out=$(run_flow discover)
  case "$out" in
    "candidate=orphan slug=$SLUG change=archived") ;;
    *) echo "  expected an orphan candidate with archived change, got: $out"; return 1 ;;
  esac
}

# =============================================================================
# flow-16: the concurrent-ensure race yields exactly ONE state= line. Forced
# deterministically: ensure once (branch + registered worktree), delete the
# worktree dir (registration + branch intact), then shim git so the attach
# attempt re-creates the dir and "fails" — like a losing concurrent ensure
# whose existence checks preceded its worktree add. reuse_or_conflict must
# report one single state=reused (not fall through and print it twice).
# =============================================================================
test_flow_ensure_racing_reuse_is_single_line() {
  new_repo flow-ensure-race-reuse
  run_flow ensure "$SLUG" >/dev/null || { echo "  initial ensure failed"; return 1; }
  rm -rf "$WORKING_ROOT"
  fakebin=$(mktemp -d)
  real_git=$(command -v git)
  cat > "$fakebin/git" <<EOF
#!/bin/sh
if [ "\$1" = worktree ] && [ "\$2" = add ]; then
  for a in "\$3" "\$4"; do
    case "\$a" in
    */.worktrees/*) mkdir -p "\$a"; break ;;
    esac
  done
  echo 'shim: simulated losing concurrent worktree add' >&2
  exit 1
fi
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"
  out=$( ( cd "$REPO_ROOT" && PATH="$fakebin:$PATH" sh "$SCRIPT" ensure "$SLUG" ) )
  rm -rf "$fakebin"
  [ "$out" = "state=reused path=$WORKING_ROOT" ] \
    || { echo "  expected exactly one state=reused line, got: $out"; return 1; }
}

# =============================================================================
# flow-17: a multi-line git stderr on a refused `git worktree remove` comes
# out as ONE collapsed git_error line (never raw multi-line output).
# =============================================================================
test_flow_release_git_error_is_single_line() {
  new_repo flow-release-git-error
  run_flow ensure "$SLUG" >/dev/null
  mk_archive
  fakebin=$(mktemp -d)
  real_git=$(command -v git)
  cat > "$fakebin/git" <<EOF
#!/bin/sh
if [ "\$1" = worktree ] && [ "\$2" = remove ]; then
  printf 'fatal: %s is dirty\nhint: commit or stash first\n' "\$3" >&2
  exit 1
fi
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"
  out=$( ( cd "$REPO_ROOT" && PATH="$fakebin:$PATH" sh "$SCRIPT" release "$SLUG" "$WORKING_ROOT" ) )
  rm -rf "$fakebin"
  [ "$(printf '%s\n' "$out" | wc -l)" = 2 ] \
    || { echo "  expected exactly 2 lines, got: $out"; return 1; }
  second=$(printf '%s\n' "$out" | sed -n 2p)
  [ "$second" = "git_error: fatal: $WORKING_ROOT is dirty hint: commit or stash first" ] \
    || { echo "  expected one collapsed git_error line, got: $second"; return 1; }
  [ -d "$WORKING_ROOT" ] \
    || { echo "  worktree was removed despite the gate"; return 1; }
}

# ---- run everything ---------------------------------------------------------

run_test "flow-extracted: the embedded flow script is found and looks correct" test_flow_extracted
run_test "flow-01: discover on a branchless repo prints no candidates" test_flow_discover_empty
run_test "flow-02: ensure creates new branch and worktree" test_flow_ensure_creates
run_test "flow-03: ensure is idempotent (reused on re-run)" test_flow_ensure_reuses
run_test "flow-04: ensure attaches when branch exists without a registration" test_flow_ensure_attaches_deleted_branch
run_test "flow-05: ensure fail-closes on an unregistered plain dir, without destroying it" test_flow_ensure_conflicts_on_plain_dir
run_test "flow-06: ensure fail-closes on a repo with no commits" test_flow_ensure_fails_without_commits
run_test "flow-07: ensure adds .worktrees/ to info/exclude, never touching .gitignore" test_flow_exclude_registered
run_test "flow-08: state runs the probe verbatim with CHANGE_DIR in the worktree" test_flow_state_runs_probe
run_test "flow-09: state fail-closes when no such worktree is registered" test_flow_state_fails_without_worktree
run_test "flow-10: release refuses without an archive on disk" test_flow_release_refused_without_archive
run_test "flow-11: release refuses while spdd/changes/<slug> still exists" test_flow_release_refused_with_changes_present
run_test "flow-12: release removes the worktree after the gate holds and keeps the branch" test_flow_release_holds_gate_and_keeps_branch
run_test "flow-13: release refuses a mistyped path (path-mismatch)" test_flow_release_refused_on_path_mismatch
run_test "flow-14: discover lists the registered candidate with branch state" test_flow_discover_reports_candidate
run_test "flow-15: discover post-release reports an orphan branch, formal archived change" test_flow_discover_after_release_is_orphan
run_test "flow-16: concurrent-ensure reuse reports exactly one state= line" test_flow_ensure_racing_reuse_is_single_line
run_test "flow-17: multi-line git stderr collapses to one git_error line in release" test_flow_release_git_error_is_single_line

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
