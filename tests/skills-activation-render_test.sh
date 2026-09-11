#!/usr/bin/env bash
# Unit tests for install.sh's access-to-frontmatter rendering, covering every
# unit-level scenario in spdd/changes/skills-activation/03-render.feature
# (render-01..04; render-01 is a Scenario Outline over the three readwrite
# roles). The change: the Claude Code `readwrite` mapping gains the `Skill`
# tool; the readonly/orchestrateonly mappings and the entire OpenCode render
# stay byte-for-byte unchanged; the marker format and determinism survive.
#
# The pre-change render pins for the OLD access-model contract live in
# tests/access-model_test.sh; that suite's expectations are evolved by this
# (skills-activation) change where 03-render.feature MODIFIES them.
#
# Harness style mirrors tests/installsh-posixsh_test.sh: `sh install.sh
# --all` against isolated temp HOMEs, never the real ~/.claude or
# ~/.config/opencode.
#
# e2e-render-01 (03-render.feature) is observable only by reinstalling on a
# user machine and reading the installed copies -- verifier's e2e suite; it
# appears below as an explicit SKIP stub so no scenario id is unaccounted for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
VERSION_FILE="$SCRIPT_DIR/VERSION"

pass_count=0
fail_count=0
skip_count=0

# ---- temp-dir bookkeeping (mirrors tests/installsh-posixsh_test.sh) ---------

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

# ---- tiny test runner -------------------------------------------------------

run_test() {
  name="$1"; fn="$2"; shift 2
  if "$fn" "$@"; then
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

# ---- fixtures ---------------------------------------------------------------

# stage_checkout <dest>: materializes a minimal install.sh checkout at <dest>
# from the working tree (install.sh, VERSION, CHANGELOG.md, agents/) so
# `sh <dest>/install.sh --all` renders from the staged tree.
stage_checkout() {
  dest="$1"
  mkdir -p "$dest"
  cp "$SCRIPT_DIR/install.sh" "$dest/install.sh"
  cp "$SCRIPT_DIR/VERSION" "$dest/VERSION"
  cp "$SCRIPT_DIR/CHANGELOG.md" "$dest/CHANGELOG.md"
  mkdir -p "$dest/agents/prompts" "$dest/agents/meta" "$dest/scripts/orchestration"
  cp "$SCRIPT_DIR"/agents/prompts/*.prompt "$dest/agents/prompts/"
  cp "$SCRIPT_DIR"/agents/meta/*.yaml "$dest/agents/meta/"
  # The orchestrator prompt's include markers are substituted from
  # scripts/orchestration/ at render time (orchestrator-fast-path), so the
  # staged tree must carry them or the render fails.
  cp "$SCRIPT_DIR"/scripts/orchestration/*.sh "$dest/scripts/orchestration/"
}

# forced_meta_checkout <dest> <access>: staged checkout with every meta file
# forced to <access>, to exercise install.sh's non-readwrite mapping branches
# even though no role declares them (render-02).
forced_meta_checkout() {
  tree="$1"; access="$2"
  stage_checkout "$tree"
  for role in specifier coder verifier orchestrator; do
    sed -i "s/^access: .*/access: $access/" "$tree/agents/meta/$role.yaml"
  done
}

# prechange_install_checkout <dest>: staged checkout identical to the working
# tree except install.sh's readwrite Claude tools string is mutated back to
# the pre-change value. Renderer-vs-renderer with a controlled single-line
# mutation: robust over time (a git-HEAD baseline goes vacuous/incorrect the
# moment this change is committed), and any renderer change outside the tools
# line still shows up as a rendered diff (render-03, render-04 scoping).
prechange_install_checkout() {
  dest="$1"
  stage_checkout "$dest"
  sed -i 's/Read, Grep, Glob, Bash, Edit, Write, Skill/Read, Grep, Glob, Bash, Edit, Write/' \
    "$dest/install.sh"
  grep -qF 'Edit, Write, Skill' "$dest/install.sh" \
    && { echo "  prechange_install_checkout: sed did not apply"; return 1; }
}

tree_root=$(new_tmp_dir)
TREE="$tree_root/tree"
stage_checkout "$TREE"
VERSION=$(cat "$VERSION_FILE")

HOMES_ROOT=$(new_tmp_dir)

# render_to <home> <tree-dir> <log>: full render of all four agents + both
# commands into <home> via install.sh's real --all path.
render_to() {
  home="$1"; tree="$2"; log="$3"
  mkdir -p "$home"
  HOME="$home" sh "$tree/install.sh" --all > "$log" 2>&1
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

render_root=$(new_tmp_dir)
WORK_HOME="$HOMES_ROOT/work"
render_to "$WORK_HOME" "$TREE" "$render_root/work.log" \
  || { echo "FATAL: working-tree render failed:"; cat "$render_root/work.log"; exit 1; }

# =============================================================================
# render-01 (Scenario Outline): install.sh renders agents/meta/<role>.yaml
# for Claude Code with the readwrite tools string that now carries Skill.
# Examples: role = specifier | coder | verifier.
# =============================================================================
test_render_01() {
  role="$1"
  f=$(agent_md "$WORK_HOME" claude "$role")
  [ -f "$f" ] || { echo "  missing rendered file: $f"; return 1; }
  [ "$(tools_line "$f")" = "Read, Grep, Glob, Bash, Edit, Write, Skill" ] \
    || { echo "  tools line is: $(tools_line "$f")"; return 1; }
  return 0
}

# =============================================================================
# render-02: the Skill grant is readwrite-only -- the readonly and
# orchestrateonly branches of claude_tools_for_access still map to the
# byte-for-byte old strings, proven functionally via forced-access renders
# (no role declares these levels anymore, but install.sh keeps the mapping).
# =============================================================================
test_render_02() {
  ok=0
  ro_root=$(new_tmp_dir); oo_root=$(new_tmp_dir)
  forced_meta_checkout "$ro_root/tree" readonly
  forced_meta_checkout "$oo_root/tree" orchestrateonly
  ro_home="$HOMES_ROOT/readonly"; oo_home="$HOMES_ROOT/orchestrateonly"
  render_to "$ro_home" "$ro_root/tree" "$ro_root/render.log" \
    || { echo "  readonly render failed"; cat "$ro_root/render.log"; return 1; }
  render_to "$oo_home" "$oo_root/tree" "$oo_root/render.log" \
    || { echo "  orchestrateonly render failed"; cat "$oo_root/render.log"; return 1; }
  [ "$(tools_line "$(agent_md "$ro_home" claude specifier)")" = "Read, Grep, Glob, Bash" ] \
    || { echo "  readonly tools: $(tools_line "$(agent_md "$ro_home" claude specifier)")"; ok=1; }
  [ "$(tools_line "$(agent_md "$ro_home" claude coder)")" = "Read, Grep, Glob, Bash" ] \
    || { echo "  readonly tools: $(tools_line "$(agent_md "$ro_home" claude coder)")"; ok=1; }
  [ "$(tools_line "$(agent_md "$oo_home" claude orchestrator)")" = "Read, Grep, Glob, Bash, Agent" ] \
    || { echo "  orchestrateonly tools: $(tools_line "$(agent_md "$oo_home" claude orchestrator)")"; ok=1; }
  # Neither unchanged mapping may carry Skill.
  tools_line "$(agent_md "$ro_home" claude specifier)" | grep -q Skill \
    && { echo "  readonly mapping grants Skill"; ok=1; }
  tools_line "$(agent_md "$oo_home" claude orchestrator)" | grep -q Skill \
    && { echo "  orchestrateonly mapping grants Skill"; ok=1; }
  return $ok
}

# =============================================================================
# render-03: the OpenCode render is unchanged in every respect. Proof: the
# same staged tree rendered with working install.sh vs git HEAD's install.sh
# produces byte-for-byte identical OpenCode agent files (prompts/meta/VERSION
# are the same inputs; the renderer is the only difference), and no rendered
# OpenCode frontmatter carries a permission.skill block or a tools: entry.
# (A before-change *filesystem* render can't be used directly: the working
# prompts already carry 01/05 sub-spec body edits, which flow into both
# clients' bodies alike -- the renderer comparison isolates exactly this
# change's layer.)
# =============================================================================
test_render_03() {
  head_root=$(new_tmp_dir)
  prechange_install_checkout "$head_root/tree"
  head_home="$HOMES_ROOT/headinstall"
  render_to "$head_home" "$head_root/tree" "$head_root/render.log" \
    || { echo "  HEAD-install render failed:"; cat "$head_root/render.log"; return 1; }
  ok=0
  for role in specifier coder verifier orchestrator; do
    a=$(agent_md "$WORK_HOME" opencode "$role")
    b=$(agent_md "$head_home" opencode "$role")
    cmp -s "$a" "$b" \
      || { echo "  OpenCode render differs from pre-change renderer: $role (HEAD vs work)"; diff "$a" "$b" | head -5; ok=1; }
  done
  for role in specifier coder verifier orchestrator; do
    f=$(agent_md "$WORK_HOME" opencode "$role")
    # Frontmatter only: the prompt body legitimately mentions skills
    # (01/02 sub-specs); the byte-identity check above pins the body too.
    sed -n '2,/^---$/p' "$f" | grep -qi 'skill' \
      && { echo "  OpenCode frontmatter mentions skill: $role"; sed -n '2,/^---$/p' "$f" | grep -i '.\{0,40\}skill.\{0,40\}'; ok=1; }
    sed -n '2,/^---$/p' "$f" | grep -q 'permission.skill' \
      && { echo "  OpenCode render carries a permission.skill block: $role"; ok=1; }
    sed -n '2,/^---$/p' "$f" | grep -q '^tools:' \
      && { echo "  OpenCode render carries a tools: entry: $role"; ok=1; }
  done
  return $ok
}

# =============================================================================
# render-04: the marker format is unchanged and rendering stays deterministic
# from (prompt body, meta access, source VERSION); the only rendered change
# anywhere is the readwrite Claude tools string (the renderer diff vs HEAD's
# install.sh shows tools:-line changes on the three readwrite Claude files
# and nothing else).
# =============================================================================
test_render_04() {
  ok=0
  marker_line=$(printf '# antz:generated version=%s -- do not edit by hand; regenerate with install.sh' "$VERSION")
  # (a) marker format unchanged, on every rendered agent and command file.
  for client in claude opencode; do
    for role in specifier coder verifier orchestrator; do
      grep -qF -- "$marker_line" "$(agent_md "$WORK_HOME" $client "$role")" \
        || { echo "  bad marker in $client/$role"; ok=1; }
    done
  done
  cf_cmd="$WORK_HOME/.claude/commands/antz.md"
  oc_cmd="$WORK_HOME/.config/opencode/commands/antz.md"
  [ -f "$cf_cmd" ] && { grep -qF -- "$marker_line" "$cf_cmd" || { echo "  bad marker in claude antz command"; ok=1; }; }
  [ -f "$oc_cmd" ] && { grep -qF -- "$marker_line" "$oc_cmd" || { echo "  bad marker in opencode antz command"; ok=1; }; }
  # (b) determinism: rendering the same tree again is byte-identical.
  again_root=$(new_tmp_dir)
  again_home="$HOMES_ROOT/again"
  render_to "$again_home" "$TREE" "$again_root/render.log" \
    || { echo "  second render failed"; cat "$again_root/render.log"; return 1; }
  for client in claude opencode; do
    for role in specifier coder verifier orchestrator; do
      cmp -s "$(agent_md "$WORK_HOME" $client "$role")" "$(agent_md "$again_home" $client "$role")" \
        || { echo "  render not deterministic: $client/$role"; ok=1; }
    done
  done
  # (c) scoping: the renderer diff vs HEAD's install.sh touches only the
  # tools lines of the three readwrite Claude agent files.
  return $ok
}

# render-04 (scoping half): the only rendered change vs the pre-change
# renderer is the readwrite Claude tools string. Diff every rendered file
# between the controlled-mutation render (see prechange_install_checkout:
# prompts are shared with the working render, so
# mutation-only diff) and the working render: exactly the three Claude
# readwrite agent files differ, and each diff is exactly its tools line.
test_render_04_scoping() {
  head_root=$(new_tmp_dir)
  prechange_install_checkout "$head_root/tree"
  head_home="$HOMES_ROOT/headinstall"
  [ -f "$(agent_md "$head_home" claude specifier)" ] \
    || { render_to "$head_home" "$head_root/tree" "$head_root/render.log" || return 1; }
  ok=0
  for client in claude opencode; do
    for role in specifier coder verifier orchestrator; do
      a=$(agent_md "$head_home" $client "$role")
      b=$(agent_md "$WORK_HOME" $client "$role")
      if [ "$client" = claude ] && [ "$role" != orchestrator ]; then
        # Expected diff: exactly the one tools line.
        if diff "$a" "$b" | grep -v '^---$' \
             | grep -vE '^[0-9,acd]+$' \
             | grep -vF --  "tools: Read, Grep, Glob, Bash, Edit, Write, Skill" \
             | grep -vF -- "tools: Read, Grep, Glob, Bash, Edit, Write" \
             | grep -vE '^[<>] ' \
             | grep -q .; then
          echo "  unexpected renderer diff in $client/$role"; diff "$a" "$b" | head -8; ok=1
        fi
        [ "$(tools_line "$b")" = "Read, Grep, Glob, Bash, Edit, Write, Skill" ] || { echo "  post-change tools wrong: $role"; ok=1; }
        [ "$(tools_line "$a")" = "Read, Grep, Glob, Bash, Edit, Write" ] || { echo "  pre-change tools wrong: $role"; ok=1; }
      else
        cmp -s "$a" "$b" \
          || { echo "  renderer changed output unexpectedly: $client/$role"; diff "$a" "$b" | head -8; ok=1; }
      fi
    done
  done
  # Command renders are out of this sub-spec's scope but must stay identical.
  cmp -s "$head_home/.claude/commands/antz.md" "$WORK_HOME/.claude/commands/antz.md" \
    || { echo "  claude antz command render changed"; ok=1; }
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "render-01 (specifier): Claude render of agents/meta/specifier.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 specifier
run_test "render-01 (coder): Claude render of agents/meta/coder.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 coder
run_test "render-01 (verifier): Claude render of agents/meta/verifier.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 verifier

run_test "render-02: readonly still maps to Read, Grep, Glob, Bash and orchestrateonly still maps to Read, Grep, Glob, Bash, Agent (forced-access renders)" test_render_02

run_test "render-03: OpenCode renders byte-identical between pre-change and post-change renderer; no permission.skill, no tools: entry, no skill mention" test_render_03

run_test "render-04: marker format unchanged and rendering deterministic (second render byte-identical)" test_render_04
run_test "render-04 (scoping): with the mutated pre-change renderer, the only rendered change is the three readwrite Claude tools lines" test_render_04_scoping

# ---- e2e-only scenario: explicit SKIP stub -----------------------------------
skip_test "e2e-render-01: after reinstall from a post-change checkout, installed Claude copies carry the Skill tool and OpenCode copies keep their shape" \
  "e2e-only: requires running install.sh's CLI against the user's real HOME, run by the verifier (03-render.feature)"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see 03-render.feature)"
[ "$fail_count" -eq 0 ]
