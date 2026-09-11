#!/usr/bin/env bash
# Unit test for the render-consistency guard of change orchestrator-fast-path
# (spdd/changes/orchestrator-fast-path/03-testharness.feature, scenario
# testharness-04): the rendered antz-orchestrator body must embed the current
# scripts/orchestration/ files byte-for-byte at their three fences, so file
# and render cannot drift apart silently.
#
# install.sh's CLI is the test affordance: a full render (--all, both
# clients) runs against an isolated temp HOME, and each installed
# antz-orchestrator body -- ~/.claude/agents/antz-orchestrator.md and
# ~/.config/opencode/agents/antz-orchestrator.md -- is compared, fence by
# fence, against the expected block built from the current script file
# (every non-empty line prefixed with the three-space fence indent, blank
# lines empty, plus the one pinned antz-skills.sh under-indent carve-out
# install.sh itself carries -- see inject_includes there).
#
# Drift is mechanized: tampering one byte of one script fence in the
# installed temp copy must make the guard report that script out of sync --
# if a file changed without a matching re-render, this suite fails instead
# of a stale installed agent going unnoticed.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/renderinject_test.sh. Run directly:
#   ./tests/orchestrator-render-sync_test.sh
#
# Every reported test name embeds its scenario id (testharness-04) so a
# failure maps straight back to the scenario it covers. All filesystem work
# happens in temp dirs, never the real ~/.claude or ~/.config/opencode.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
SCRIPTS="antz-flow antz-probe antz-skills"

pass_count=0
fail_count=0

# ---- tiny test runner ------------------------------------------------------

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

tmp_roots=()
new_tmp_dir() {
  d=$(mktemp -d)
  tmp_roots+=("$d")
  printf '%s' "$d"
}

cleanup() {
  for d in "${tmp_roots[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

# ---- render affordance ------------------------------------------------------

render_all() {
  # Renders the full install (both clients) from the working tree into the
  # isolated HOME $1, logging stdout+stderr to $2.
  home="$1"; log="$2"
  (cd "$SCRIPT_DIR" && HOME="$home" sh ./install.sh --all > "$log" 2>&1)
}

# The expected fence body for a script file: the file's own content with the
# three-space fence indent re-applied to every non-empty line (blank lines
# render empty), sharing install.sh's one pinned antz-skills.sh carve-out --
# the pre-existing under-fence-indent "  done" loop-closer line renders
# verbatim. Byte-identical means indentation included.
expected_block() {
  case "$1" in
    antz-skills) sed -e "/./s/^/   /" -e 's/^     done$/  done/' \
      "$SCRIPT_DIR/scripts/orchestration/antz-skills.sh" ;;
    *) sed "/./s/^/   /" "$SCRIPT_DIR/scripts/orchestration/$1.sh" ;;
  esac
}

FENCE_BODIES=()
extract_fences() {
  # $1 = file; fills FENCE_BODIES with one temp file per fenced block's body
  # (``` or ```sh openers; prose carries no triple backticks).
  FENCE_BODIES=()
  cur=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'```'*)
        if [ -n "$cur" ]; then
          FENCE_BODIES+=("$cur")
          cur=""
        else
          cur=$(mktemp)
          tmp_roots+=("$cur")
          : > "$cur"
        fi
        continue
        ;;
    esac
    if [ -n "$cur" ]; then printf '%s\n' "$line" >> "$cur"; fi
  done < "$1"
}

out_of_sync_scripts() {
  # $1 = installed agent file. Prints the space-separated scripts whose
  # expected block matches no fence body of the installed file (empty output
  # = every script is embedded byte-identically, indentation included).
  installed="$1"
  extract_fences "$installed"
  bad=""
  for s in $SCRIPTS; do
    exp=$(mktemp)
    tmp_roots+=("$exp")
    expected_block "$s" > "$exp"
    matched=""
    for fb in "${FENCE_BODIES[@]}"; do
      if cmp -s "$fb" "$exp"; then matched=1; break; fi
    done
    [ -n "$matched" ] || bad="$bad $s"
  done
  # Trim the leading space so the caller can match exact single-script
  # drift reports.
  printf '%s' "${bad# }"
}

# =============================================================================
# testharness-04: for both clients, each of the three script fences in the
# installed antz-orchestrator body is byte-identical to the current
# scripts/orchestration/ file (indentation included).
# =============================================================================
test_testharness_04_render_matches_files() {
  ok=0
  home=$(new_tmp_dir)/home
  log="$home-render.log"
  tmp_roots+=("$(dirname "$log")")
  render_all "$home" "$log" \
    || { echo "  install.sh --all failed: $(cat "$log")"; return 1; }
  for dest in .claude/agents/antz-orchestrator.md \
              .config/opencode/agents/antz-orchestrator.md; do
    installed="$home/$dest"
    [ -f "$installed" ] || { echo "  missing installed file: $dest"; ok=1; continue; }
    bad=$(out_of_sync_scripts "$installed")
    [ -z "$bad" ] \
      || { echo "  $dest fences do not match the current scripts: $bad"; ok=1; }
  done
  return $ok
}

# =============================================================================
# testharness-04 (drift clause): the guard fails when a rendered fence no
# longer matches its file -- one tampered byte inside one script fence of the
# installed copy reports exactly that script out of sync (the other fences
# still matching), so file/render drift is caught by the suite, not by a
# stale installed agent.
# =============================================================================
test_testharness_04_drift_is_caught() {
  ok=0
  home=$(new_tmp_dir)/home
  log="$home-render.log"
  render_all "$home" "$log" \
    || { echo "  install.sh --all failed: $(cat "$log")"; return 1; }
  installed="$home/.claude/agents/antz-orchestrator.md"
  [ -f "$installed" ] || { echo "  missing installed Claude Code file"; return 1; }
  # Tamper one byte inside the flow fence: the first fence's `set -eu` line.
  opener=$(grep -nE '^   ```$' "$installed" | head -n 1 | cut -d: -f1)
  [ -n "$opener" ] || { echo "  no fence found in the installed body"; return 1; }
  target=$(awk -v o="$opener" 'NR > o && /^   set -eu$/ { print NR; exit }' "$installed")
  [ -n "$target" ] || { echo "  flow fence's set -eu line not found"; return 1; }
  sed -i "${target}s/^   set -eu$/   set -euX/" "$installed"
  bad=$(out_of_sync_scripts "$installed")
  [ "$bad" = "antz-flow" ] \
    || { echo "  expected exactly antz-flow out of sync after the tamper, got: '$bad'"; ok=1; }
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "testharness-04: both clients' rendered antz-orchestrator bodies embed the current scripts/orchestration/ files byte-for-byte at their three fences" test_testharness_04_render_matches_files
run_test "testharness-04: a file change without a matching re-render is caught -- one tampered byte in an installed fence reports that script out of sync" test_testharness_04_drift_is_caught

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
