#!/usr/bin/env bash
# Unit tests for the antz-commit.sh fence shared by the specifier, coder, and
# verifier role prompts. The script mechanizes the per-role commit rule the
# worktree-isolation plan documents: commits only from an isolated flow's
# working root (WORKING_ROOT set), staging only the explicit paths passed
# (never sweeping flags), and never committing empty trees.
#
# Also asserts the fence is byte-identical across the three role prompts —
# they must stay one artifact, not three drifting copies.
#
# Mirrors the harness style of tests/orchestrator-status-probe_test.sh. Run:
#   ./tests/antz-commit_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

pass_count=0
fail_count=0

SCRIPT=$(mktemp)
SCRIPT_CODER=$(mktemp)
SCRIPT_VERIFIER=$(mktemp)

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

SPECIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/specifier.prompt"
CODER_PROMPT="$SCRIPT_DIR/agents/prompts/coder.prompt"
VERIFIER_PROMPT="$SCRIPT_DIR/agents/prompts/verifier.prompt"

# ---- extracting the fence ---------------------------------------------------

# Each role prompt has exactly one zero-indent ```sh fence; extract it.
extract_commit() {
  awk '/^```sh$/{p=1; next} /^```$/{p=0} p' "$1"
}

extract_commit "$SPECIFIER_PROMPT" > "$SCRIPT"
extract_commit "$CODER_PROMPT" > "$SCRIPT_CODER"
extract_commit "$VERIFIER_PROMPT" > "$SCRIPT_VERIFIER"

# ---- tiny fixture ------------------------------------------------------------

REPO_ROOT=""
WORKING_ROOT=""

new_repo_with_worktree() {
  REPO_ROOT=$(mktemp -d)
  git -C "$REPO_ROOT" init -q
  echo hello > "$REPO_ROOT/a.txt"
  git -C "$REPO_ROOT" add .
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m init
  git -C "$REPO_ROOT" worktree add -q -b "antz/commit-test" "$REPO_ROOT/.worktrees/commit-test" HEAD >/dev/null 2>&1
}

cleanup() {
  if [ -n "${REPO_ROOT:-}" ] && [ -d "$REPO_ROOT" ]; then
    ( git -C "$REPO_ROOT" worktree remove --force "$REPO_ROOT/.worktrees/commit-test" >/dev/null 2>&1 ) || true
    rm -rf "$REPO_ROOT"
  fi
  REPO_ROOT=""
  WORKING_ROOT=""
}
trap cleanup EXIT

REPO_ROOT=""; WORKING_ROOT=""

run_commit_script() {
  S=$1; shift
  if [ -n "$WORKING_ROOT" ]; then
    ( cd "$REPO_ROOT" && WORKING_ROOT="$WORKING_ROOT" sh "$S" "$@" )
  else
    ( cd "$REPO_ROOT" && unset WORKING_ROOT && sh "$S" "$@" )
  fi
}

worktree_branch() {
  git -C "$REPO_ROOT" branch --list 'antz/commit-test' | sed 's/^[*+ ]*//'
}

# =============================================================================
# commit-gate-off: without WORKING_ROOT nothing is committed — manual/direct
# role invocations stay as uncommitting as before.
# =============================================================================
test_commit_gate_off() {
  new_repo_with_worktree
  out=$(run_commit_script "$SCRIPT" "gated off" a.txt 2>&1) || true
  case "$out" in "no working root: commit gated off") ;; *) echo "  unexpected output: $out"; return 1 ;; esac
  [ "$(git -C "$REPO_ROOT" rev-list --count HEAD)" = "1" ] \
    || { echo "  a commit was made despite the gate"; return 1; }
}

# =============================================================================
# commit-no-paths: paths are required.
# =============================================================================
test_commit_requires_paths() {
  new_repo_with_worktree
  WORKING_ROOT="$REPO_ROOT/.worktrees/commit-test"
  out=$(run_commit_script "$SCRIPT" "no paths" 2>&1) || true
  case "$out" in "no paths given") ;; *) echo "  unexpected output: $out"; return 1 ;; esac
}

# =============================================================================
# commit-stages-exact-paths: only the passed paths land in the commit.
# =============================================================================
test_commit_stages_exact_paths() {
  new_repo_with_worktree
  WORKING_ROOT="$REPO_ROOT/.worktrees/commit-test"
  mkdir -p "$WORKING_ROOT/spdd/changes/slug"
  echo s > "$WORKING_ROOT/spdd/changes/slug/s.md"
  echo untracked > "$WORKING_ROOT/spdd/changes/slug/not-passed.md"
  out=$(run_commit_script "$SCRIPT" "commit slug" spdd/changes/slug/s.md)
  case "$out" in "committed") ;; *) echo "  unexpected output: $out"; return 1 ;; esac
  listed=$(git -C "$WORKING_ROOT" show --name-only --format= HEAD | grep -v '^$')
  [ "$listed" = "spdd/changes/slug/s.md" ] \
    || { echo "  expected exactly s.md, got: $listed"; return 1; }
  ok=$(git -C "$WORKING_ROOT" status --porcelain)
  [ "$ok" = "?? spdd/changes/slug/not-passed.md" ] \
    || { echo "  unpassed file was swept into the commit: $ok"; return 1; }
}

# =============================================================================
# commit-no-sweeping-flags: git add -A/--all et al. are refused outright.
# =============================================================================
test_commit_refuses_sweeping_flags() {
  new_repo_with_worktree
  WORKING_ROOT="$REPO_ROOT/.worktrees/commit-test"
  echo x > "$WORKING_ROOT/x-untracked.md"
  before=$(git -C "$REPO_ROOT" rev-list --count HEAD)
  out=$(run_commit_script "$SCRIPT" "sweep" -A 2>&1) || true
  case "$out" in *"sweeping git add flag forbidden"*) ;; *) echo "  unexpected output: $out"; return 1 ;; esac
  after=$(git -C "$REPO_ROOT" rev-list --count HEAD)
  [ "$before" = "$after" ] || { echo "  a sweeping commit got made"; return 1; }
}

# =============================================================================
# commit-empty-tree-refused: nothing staged -> no commit.
# =============================================================================
test_commit_refuses_empty_tree() {
  new_repo_with_worktree
  WORKING_ROOT="$REPO_ROOT/.worktrees/commit-test"
  echo already-tracked-but-unmodified > /dev/null
  echo b > "$REPO_ROOT/b.txt"
  git -C "$REPO_ROOT" add b.txt
  git -C "$REPO_ROOT" -c user.email=t@t -c user.name=t commit -q -m b
  out=$(run_commit_script "$SCRIPT" "empty" a.txt 2>&1) || true
  case "$out" in "nothing staged") ;; *) echo "  unexpected output: $out"; return 1 ;; esac
  [ "$(git -C "$REPO_ROOT" rev-list --count HEAD)" = "2" ] \
    || { echo "  an empty commit slipped through"; return 1; }
}

# =============================================================================
# commit-lands-on-the-worktree-branch: the commit runs inside the working
# root, so its tree lands on antz/<slug>, not the main checkout's branch.
# =============================================================================
test_commit_lands_on_worktree_branch() {
  new_repo_with_worktree
  WORKING_ROOT="$REPO_ROOT/.worktrees/commit-test"
  mkdir -p "$WORKING_ROOT/spdd/changes/slug"
  echo s > "$WORKING_ROOT/spdd/changes/slug/s.md"
  run_commit_script "$SCRIPT" "commit slug" spdd/changes/slug/s.md >/dev/null
  branch=$(worktree_branch)
  [ "$branch" = "antz/commit-test" ] \
    || { echo "  worktree got off-branch: $branch"; return 1; }
  git -C "$REPO_ROOT" cat-file -e "refs/heads/antz/commit-test:spdd/changes/slug/s.md" 2>/dev/null \
    || { echo "  commit didn't land on the worktree branch"; return 1; }
}

# =============================================================================
# commit-fence-parity: the three role prompts carry the byte-identical fence.
# =============================================================================
test_commit_fence_parity() {
  cmp -s "$SCRIPT" "$SCRIPT_CODER" \
    || { echo "  specifier vs coder fence differ"; return 1; }
  cmp -s "$SCRIPT" "$SCRIPT_VERIFIER" \
    || { echo "  specifier vs verifier fence differ"; return 1; }
}

# =============================================================================
# commit-fence-shape: the fence carries the gate, the sweep-guard, and the
# empty-tree guard mechanically (not just historically): these are what make
# the fence the promise it claims.
# =============================================================================
test_commit_fence_shape() {
  guard() {
    grep -qF "$1" "$2" || { echo "  fence missing: $1"; return 1; }
  }
  for f in "$SCRIPT" "$SCRIPT_CODER" "$SCRIPT_VERIFIER"; do
    guard 'no working root: commit gated off' "$f" || return 1
    guard 'sweeping git add flag forbidden' "$f" || return 1
    guard 'nothing staged' "$f" || return 1
    guard 'cd "$WORKING_ROOT"' "$f" || return 1
    guard 'git add -- "$p"' "$f" || return 1
    if grep -qE 'git (add|commit) -A' "$f"; then echo "  fence itself sweeps: $f"; return 1; fi
  done
}

# ---- run everything ---------------------------------------------------------

run_test "commit-gate-off: unset WORKING_ROOT commits nothing" test_commit_gate_off
run_test "commit-no-paths: missing paths is an error, not a commit" test_commit_requires_paths
run_test "commit-stages-exact-paths: only the passed paths are staged" test_commit_stages_exact_paths
run_test "commit-no-sweeping-flags: -A/--all etc are refused outright" test_commit_refuses_sweeping_flags
run_test "commit-empty-tree-refused: nothing staged -> no commit" test_commit_refuses_empty_tree
run_test "commit-lands-on-the-worktree-branch: commit trees land on antz/<slug>" test_commit_lands_on_worktree_branch
run_test "commit-fence-parity: the fence is byte-identical across the three prompts" test_commit_fence_parity
run_test "commit-fence-shape: the fence carries its guards mechanically" test_commit_fence_shape

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]

rm -f "$SCRIPT" "$SCRIPT_CODER" "$SCRIPT_VERIFIER"
