#!/usr/bin/env bash
# Unit tests for install.sh's access-to-frontmatter rendering facets this
# suite owns (change optimize-test-suite, sub-spec 08-renderdedup): the
# Skill-grant scoping (render-02), the OpenCode frontmatter shape guard
# (render-03), and the marker format plus render determinism (render-04),
# plus the originating change's e2e-render-01 skip stub. renderindependence-01
# extends the same whole-render scan surface: every file install.sh produces
# -- agents, commands, and the installed libdir scripts -- is checked for
# references back to this repo, so a careless prompt edit cannot ship an
# artifact that points at the antz repo from a host project.
#
# The render-01 id is owned by tests/access-model_test.sh alone: this
# suite's three render-01 registrations pinned the same rendered bytes
# (the readwrite Claude tools line) and are removed (renderdedup-02). Per
# the owner's revision the retained coverage is current-version behavior
# only: the "only rendered change vs the pre-change renderer" scoping
# registration and its controlled-mutation fixture machinery are deleted
# with it, not left as dead code (renderdedup-03), and render-02 no longer
# re-pins the exact mapping strings (access-model render-04's facet) — it
# asserts only that the forced readonly and orchestrateonly renders grant
# no Skill. The current-version law for this suite: zero
# real-tree-vs-version-control comparisons, zero byte-pins against history,
# zero exact-phrase prose assertions.
#
# The shared harness library (tests/harness.sh) provides the runner, the
# content readers, temp bookkeeping, and the render helpers
# (stage_checkout + render_tree — install.sh renders only through those,
# always into a sandbox HOME, never the real user surface; every staged
# tree is rendered once per run). The renderdedup-02/-03 tests pin this
# suite's own shape by scanning its own non-comment source; needles are
# quote-split or column-0-anchored so the scanning code can never match
# itself.
#
# e2e-render-01 (spdd/changes/skills-activation/03-render.feature) is
# observable only by reinstalling on a user machine and reading the
# installed copies -- verifier's e2e suite; it stays an explicit SKIP stub
# so no scenario id is unaccounted for.
#
# Every variable inside a test or helper is prefixed: the harness runs
# plain functions with shared globals, so none may shadow a caller's.
#
# Run directly: sh tests/skills-activation-render_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"
VERSION=$(cat "$SCRIPT_DIR/VERSION")

# This suite's own source with comment lines stripped: the renderdedup
# self-checks scan non-comment lines only (the hygiene convention).
SELF_TEST="$SCRIPT_DIR/tests/skills-activation-render_test.sh"
SELF_ROOT=$(new_tmp_dir)
SELF_NONCOMMENTS="$SELF_ROOT/noncomments"
grep -v '^[[:space:]]*#' "$SELF_TEST" > "$SELF_NONCOMMENTS"

# ---- fixtures ----------------------------------------------------------------
# stage_checkout + render_tree come from the harness library.

# forced_meta_checkout <tree-dir> <access>: a staged checkout with every meta
# file forced to <access>, exercising the mapping levels no role declares
# anymore (render-02's forced renders).
forced_meta_checkout() {
  fmc_tree="$1"; fmc_access="$2"
  stage_checkout "$fmc_tree"
  for fmc_role in specifier coder verifier orchestrator; do
    sed -i "s/^access: .*/access: $fmc_access/" "$fmc_tree/agents/meta/$fmc_role.yaml"
  done
}

# agent_md <home> <client> <role>: the rendered agent file path.
agent_md() {
  case "$2" in
    claude) printf '%s/.claude/agents/antz-%s.md' "$1" "$3" ;;
    opencode) printf '%s/.config/opencode/agents/antz-%s.md' "$1" "$3" ;;
  esac
}

# tools_line <file>: the rendered Claude frontmatter tools value.
tools_line() { sed -n 's/^tools: //p' "$1"; }

# mask_home_path <file> <home> <dest>: rewrite the render home's path to a
# common token. The render legitimately embeds the resolved libdir (under
# each render's own sandbox home) into the orchestrator body, so a cross-home
# byte comparison masks that path first (and it is a no-op on every file that
# carries no path).
mask_home_path() {
  sed "s|$2|/MASKED_HOME|g" "$1" > "$3"
}

# The working tree's render, staged and run through the library's helpers:
# the source of every file this suite inspects.
tree_root=$(new_tmp_dir)
TREE="$tree_root/tree"
stage_checkout "$TREE"
WORK_HOME=$(render_tree "$TREE") \
  || { echo "FATAL: working-tree render failed"; exit 1; }

# =============================================================================
# render-02 (this suite owns the Skill-grant scoping): the Skill tool is
# readwrite-only -- the forced readonly and orchestrateonly renders grant no
# Skill to any role. (The exact mapping strings are access-model render-04's
# facet; no role declares these levels anymore, but install.sh keeps them.)
# =============================================================================
test_render_02() {
  r2_ok=0
  for r2_access in readonly orchestrateonly; do
    r2_fx=$(new_tmp_dir); forced_meta_checkout "$r2_fx/tree" "$r2_access"
    r2_home=$(render_tree "$r2_fx/tree") || { echo "  $r2_access render failed"; r2_ok=1; continue; }
    for r2_role in specifier coder verifier orchestrator; do
      r2_line=$(tools_line "$(agent_md "$r2_home" claude "$r2_role")")
      case "$r2_line" in
        *Skill*) echo "  forced $r2_access render grants Skill: $r2_role -> $r2_line"; r2_ok=1 ;;
      esac
    done
  done
  return $r2_ok
}

# =============================================================================
# render-03 (this suite owns the OpenCode frontmatter shape guard): no
# rendered OpenCode frontmatter carries a permission.skill block, a tools:
# entry, or any skill mention. (The prompt body legitimately mentions
# skills; only the frontmatter is in view.)
# =============================================================================
test_render_03() {
  r3_ok=0
  r3_fm="$SELF_ROOT/fm"
  for r3_role in specifier coder verifier orchestrator; do
    r3_f=$(agent_md "$WORK_HOME" opencode "$r3_role")
    [ -f "$r3_f" ] || { echo "  missing rendered file: $r3_f"; r3_ok=1; continue; }
    sed -n '2,/^---$/p' "$r3_f" > "$r3_fm"
    grep -qi 'skill' "$r3_fm" \
      && { echo "  OpenCode frontmatter mentions skill: $r3_role"; r3_ok=1; }
    grep -q 'permission.skill' "$r3_fm" \
      && { echo "  OpenCode frontmatter carries a permission.skill block: $r3_role"; r3_ok=1; }
    grep -q '^tools:' "$r3_fm" \
      && { echo "  OpenCode frontmatter carries a tools: entry: $r3_role"; r3_ok=1; }
  done
  return $r3_ok
}

# =============================================================================
# render-04 (this suite owns the marker format and render determinism): the
# marker line appears on every rendered agent and command file, and a second
# independent render of the same tree is byte-identical.
# =============================================================================
test_render_04() {
  r4_ok=0
  r4_marker=$(printf '# antz:generated version=%s -- do not edit by hand; regenerate with install.sh' "$VERSION")
  # (a) marker format, on every rendered agent and command file.
  for r4_client in claude opencode; do
    for r4_role in specifier coder verifier orchestrator; do
      grep -qF -- "$r4_marker" "$(agent_md "$WORK_HOME" "$r4_client" "$r4_role")" \
        || { echo "  bad marker in $r4_client/$r4_role"; r4_ok=1; }
    done
  done
  for r4_cmd in "$WORK_HOME/.claude/commands/antz.md" "$WORK_HOME/.config/opencode/commands/antz.md"; do
    [ -f "$r4_cmd" ] || { echo "  missing command render: $r4_cmd"; r4_ok=1; continue; }
    grep -qF -- "$r4_marker" "$r4_cmd" || { echo "  bad marker in command render $r4_cmd"; r4_ok=1; }
  done
  # (b) determinism: re-stage the same working tree, render it independently
  # (a distinct staged tree is the library's own render key), and compare
  # every agent file byte-for-byte with the home path masked.
  r4_again_root=$(new_tmp_dir)
  stage_checkout "$r4_again_root/tree"
  r4_again_home=$(render_tree "$r4_again_root/tree") || { echo "  second render failed"; return 1; }
  r4_cmp=$(new_tmp_dir)
  for r4_client in claude opencode; do
    for r4_role in specifier coder verifier orchestrator; do
      mask_home_path "$(agent_md "$WORK_HOME" "$r4_client" "$r4_role")" "$WORK_HOME" "$r4_cmp/first"
      mask_home_path "$(agent_md "$r4_again_home" "$r4_client" "$r4_role")" "$r4_again_home" "$r4_cmp/second"
      cmp -s "$r4_cmp/first" "$r4_cmp/second" \
        || { echo "  render not deterministic: $r4_client/$r4_role"; r4_ok=1; }
    done
  done
  return $r4_ok
}

# =============================================================================
# renderindependence-01: every file install.sh produces -- rendered agent
# files, command files, and the installed libdir scripts -- is free of
# references back to this repo (its policy docs, its test area, its docs
# directory). This asserts the render output, not doc prose: an installed
# artifact is shipped into an arbitrary host project, so pointing back here
# would be a product defect. URLs are stripped before the scan so a doc URL's
# path segment is not mistaken for a repo path; spdd/, the standard skills
# directories, the XDG libdir, and the antz:generated marker are design
# conventions, not violations. The four needles are quote-split so this
# suite's own source never carries them whole (the hygiene convention).
# =============================================================================
produced_files() {
  # $1 = a rendered sandbox home: every file install.sh produced there.
  find "$1" -type f | LC_ALL=C sort
}

test_renderindependence_01() {
  rind_ok=0
  rind_list="$SELF_ROOT/ri.files"
  rind_scan="$SELF_ROOT/ri.scan"
  produced_files "$WORK_HOME" > "$rind_list"
  rind_n=$(wc -l < "$rind_list" | tr -d ' ')
  [ "$rind_n" -eq 16 ] \
    || { echo "  expected 16 produced files, found $rind_n"; rind_ok=1; }
  for rind_pat in 'AGENTS.m''d' 'CLAUDE.m''d' 'tests''/' 'doc''s/'; do
    while IFS= read -r rind_f; do
      [ -n "$rind_f" ] || continue
      sed -E 's#https?://[^[:space:]]*##g' "$rind_f" > "$rind_scan"
      if rind_hits=$(grep -nF -- "$rind_pat" "$rind_scan"); then
        echo "  repo reference '$rind_pat' in $rind_f:"
        printf '%s\n' "$rind_hits" | sed 's/^/    /'
        rind_ok=1
      fi
    done < "$rind_list"
  done
  return $rind_ok
}

# =============================================================================
# renderdedup-02/-03 (change optimize-test-suite, sub-spec 08): this suite's
# own retained render shape, scanned from SELF_NONCOMMENTS (its own source
# minus comment lines -- a suite may read its own file). Needles are
# quote-split or column-0-anchored so the scanning code can never match
# itself.
# =============================================================================

# renderdedup-02: the three render-01 registrations -- the same rendered
# bytes access-model render-01 pins -- are gone; render-02, render-03, and
# render-04 stay registered under their ids, and the e2e-render-01 skip stub
# stays.
test_renderdedup_02() {
  ok=0
  n=$(grep -cE '^run_test "render-01' "$SELF_NONCOMMENTS")
  [ "$n" -eq 0 ] || { echo "  render-01 still registered here ($n times)"; ok=1; }
  refuse "$SELF_NONCOMMENTS" 'test_render_0''1' || ok=1
  for id in render-02 render-03 render-04; do
    n=$(grep -cE "^run_test \"$id" "$SELF_NONCOMMENTS")
    [ "$n" -eq 1 ] || { echo "  $id registered $n times, expected 1"; ok=1; }
  done
  n=$(grep -cE '^skip_test "e2e-render-01' "$SELF_NONCOMMENTS")
  [ "$n" -eq 1 ] || { echo "  e2e-render-01 skip stub registered $n times, expected 1"; ok=1; }
  return $ok
}

# renderdedup-03: the suite is re-keyed to current-version behavior only --
# render-02 asserts Skill scoping, render-03 asserts the OpenCode
# frontmatter shape, render-04 asserts marker format and determinism, and
# the scoping registration plus its controlled-mutation fixture machinery
# are deleted, not left as dead code. The suite never touches git, never
# compares against history, and never re-pins the mapping strings or the
# readwrite tools line (access-model's facets); every render goes through
# the harness library's helpers.
test_renderdedup_03() {
  ok=0
  n=$(grep -cE '^run_test "render-04' "$SELF_NONCOMMENTS")
  [ "$n" -eq 1 ] || { echo "  render-04 registered $n times, expected 1"; ok=1; }
  refuse "$SELF_NONCOMMENTS" 'test_render_04_sco''ping' || ok=1
  refuse "$SELF_NONCOMMENTS" 'prechange_install_checko''ut' || ok=1
  refuse "$SELF_NONCOMMENTS" 'gi''t ' || ok=1
  refuse "$SELF_NONCOMMENTS" 'HE''AD' || ok=1
  refuse "$SELF_NONCOMMENTS" 'INSTALL_S''H' || ok=1
  refuse "$SELF_NONCOMMENTS" 'Read, Grep, Glob, Ba''sh' || ok=1
  refuse "$SELF_NONCOMMENTS" 'Edit, Write, Skil''l' || ok=1
  d=$(new_tmp_dir)
  extract_fn "$SELF_NONCOMMENTS" test_render_02 "$d/r2"
  [ -s "$d/r2" ] || { echo "  render-02's test function is missing"; ok=1; }
  require "$d/r2" 'forced_meta_checko''ut' || ok=1
  require "$d/r2" 'readonly' || ok=1
  require "$d/r2" 'orchestrateonly' || ok=1
  require "$d/r2" 'Skill' || ok=1
  extract_fn "$SELF_NONCOMMENTS" test_render_03 "$d/r3"
  [ -s "$d/r3" ] || { echo "  render-03's test function is missing"; ok=1; }
  require "$d/r3" 'permission.skill' || ok=1
  require "$d/r3" '^tools:' || ok=1
  refuse "$d/r3" 'cmp ' || ok=1
  refuse "$d/r3" 'mask_home_pa''th' || ok=1
  refuse "$d/r3" 'diff ' || ok=1
  extract_fn "$SELF_NONCOMMENTS" test_render_04 "$d/r4"
  [ -s "$d/r4" ] || { echo "  render-04's test function is missing"; ok=1; }
  require "$d/r4" 'antz:generated version=' || ok=1
  require "$d/r4" 'commands/antz.md' || ok=1
  require "$d/r4" 'cmp -s' || ok=1
  require "$SELF_NONCOMMENTS" 'stage_checko''ut' || ok=1
  require "$SELF_NONCOMMENTS" 'render_tre''e' || ok=1
  refuse "$SELF_NONCOMMENTS" 'env -u XD''G' || ok=1
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "render-02: the Skill grant is readwrite-only -- forced readonly and orchestrateonly renders grant no Skill on any role's Claude tools line" test_render_02

run_test "render-03: the OpenCode frontmatter shape guard -- no permission.skill block, no tools: entry, and no skill mention anywhere in any rendered OpenCode frontmatter" test_render_03

run_test "render-04: the marker line appears on every rendered agent and command file, and a second independent render of the same tree is byte-identical" test_render_04

run_test "renderindependence-01: every file install.sh produces (all rendered agents and commands and the installed libdir scripts) is free of references back to this repo, with URLs excluded from the scan" test_renderindependence_01

run_test "renderdedup-02: this suite's three render-01 registrations are gone, render-02, render-03, and render-04 stay registered under their ids, and the e2e-render-01 skip stub stays" test_renderdedup_02
run_test "renderdedup-03: current-version re-keying -- render-02 asserts Skill scoping only, render-03 asserts the OpenCode frontmatter shape only, render-04 asserts marker format and determinism, and the scoping registration and its controlled-mutation fixture machinery are deleted, not left as dead code" test_renderdedup_03

# ---- e2e-only scenario: explicit SKIP stub -----------------------------------
skip_test "e2e-render-01: after reinstall from a post-change checkout, installed Claude copies carry the Skill tool and OpenCode copies keep their shape" \
  "e2e-only: requires running the installer's CLI against the user's real home, run by the verifier (03-render.feature)"

finish_suite
