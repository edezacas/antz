#!/usr/bin/env bash
# Unit tests for the current version's role access model: the four
# agents/meta/*.yaml declarations (meta-01..03) and install.sh's
# access-to-grants render mappings (render-01, render-02, render-04).
#
# Re-keyed by change optimize-test-suite (sub-spec 08-renderdedup). This
# suite OWNS the render-01 id: render-01 is registered for all three
# readwrite roles (specifier, coder, verifier) as the sole pin of the role
# agents' Claude readwrite tools line. The suite lost its git-HEAD
# mechanisms: render-03 (the byte-compare of the coder/orchestrator renders
# against a pre-change meta render) is removed entirely, meta-03 keeps its
# field checks alone (its access/name/description checks replace the old
# regression pins), and render-04 is the sole mapping-level owner —
# readonly and orchestrateonly pinned once, functionally, via forced-access
# renders (its install.sh source-line greps removed). The docs-01..04 tests
# (exact-phrase policy-doc assertions) are deleted per the owner's
# revision. The current-version law for this suite: zero
# real-tree-vs-version-control comparisons, zero byte-pins against history,
# zero exact-phrase prose assertions.
#
# The ownership map (sub-spec 08): this suite owns the role agents'
# access-to-grants mapping pins and the meta declarations; the Skill-grant
# scoping, the OpenCode frontmatter shape guard, and the marker format plus
# render determinism are owned by tests/skills-activation-render_test.sh.
# The dedup law is carried by the map plus each suite's own self-pins — this
# suite never scans another suite's source (the decoupling law).
#
# The shared harness library (tests/harness.sh) provides the runner, the
# content readers, temp bookkeeping, and the render helpers
# (stage_checkout + render_tree — install.sh renders only through those,
# always into a sandbox HOME, never the real user surface). The
# renderdedup-01/-04/-05 tests pin this suite's own shape by scanning its
# own non-comment source; needles are quote-split or column-0-anchored so
# the scanning code can never match itself.
#
# The originating change's end-to-end scenarios (e2e-meta-01..02,
# e2e-render-01..02, e2e-docs-01) are observable only at the installed,
# user-visible surface, so they stay explicit SKIP stubs — the verifier's
# e2e suite runs them.
#
# Run directly: sh tests/access-model_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"
META_SPECIFIER="$SCRIPT_DIR/agents/meta/specifier.yaml"
META_CODER="$SCRIPT_DIR/agents/meta/coder.yaml"
META_VERIFIER="$SCRIPT_DIR/agents/meta/verifier.yaml"
META_ORCHESTRATOR="$SCRIPT_DIR/agents/meta/orchestrator.yaml"

# This suite's own source with comment lines stripped: the renderdedup
# self-checks scan non-comment lines only (the hygiene convention).
ACCESS_MODEL_TEST_SELF="$SCRIPT_DIR/tests/access-model_test.sh"
SELF_ROOT=$(new_tmp_dir)
ACCESS_NONCOMMENTS="$SELF_ROOT/noncomments"
grep -v '^[[:space:]]*#' "$ACCESS_MODEL_TEST_SELF" > "$ACCESS_NONCOMMENTS"

# meta_field <file> <field>: the value of a top-level single-line YAML field
# (the meta files are three flat "key: value" lines).
meta_field() {
  sed -n "s/^$2: //p" "$1"
}

# ---- render fixtures ---------------------------------------------------------
# Every render funnels through the harness library's helpers: the working
# tree's staged copy, plus forced-access staged copies that exercise the
# mapping levels no role declares anymore. render_tree caches each distinct
# staged tree once per run.

# agent_md <home> <client> <role>: the rendered agent file path.
agent_md() {
  case "$2" in
    claude) printf '%s/.claude/agents/antz-%s.md' "$1" "$3" ;;
    opencode) printf '%s/.config/opencode/agents/antz-%s.md' "$1" "$3" ;;
    pi) printf '%s/.pi/agent/agents/antz-%s.md' "$1" "$3" ;;
  esac
}

# tools_line <file>: the rendered Claude frontmatter tools value.
tools_line() { sed -n 's/^tools: //p' "$1"; }

# forced_meta_checkout <tree-dir> <access>: a staged checkout with every meta
# file forced to <access>. Every variable is fmc_-prefixed: the harness runs
# plain functions with shared globals, so none may shadow a caller's.
forced_meta_checkout() {
  fmc_tree="$1"; fmc_access="$2"
  stage_checkout "$fmc_tree"
  for fmc_role in specifier coder verifier orchestrator; do
    sed -i "s/^access: .*/access: $fmc_access/" "$fmc_tree/agents/meta/$fmc_role.yaml"
  done
}

# The lazily-rendered fixture homes:
#   WORK_HOME     -- the working tree as-is (readwrite roles, orchestrateonly
#                    orchestrator): render-01 and render-02 read this one
#   READONLY_HOME -- every meta forced to access: readonly   (render-04)
#   ORCH_HOME     -- every meta forced to access: orchestrateonly (render-04)
RENDERS_READY=""
WORK_HOME=""
READONLY_HOME=""
ORCH_HOME=""
prepare_renders() {
  [ -n "$RENDERS_READY" ] && return 0
  pr_rw=$(new_tmp_dir); stage_checkout "$pr_rw/tree"
  WORK_HOME=$(render_tree "$pr_rw/tree") || { echo "  working-tree render failed"; return 1; }
  pr_ro=$(new_tmp_dir); forced_meta_checkout "$pr_ro/tree" readonly
  READONLY_HOME=$(render_tree "$pr_ro/tree") || { echo "  readonly render failed"; return 1; }
  pr_oo=$(new_tmp_dir); forced_meta_checkout "$pr_oo/tree" orchestrateonly
  ORCH_HOME=$(render_tree "$pr_oo/tree") || { echo "  orchestrateonly render failed"; return 1; }
  RENDERS_READY=1
  return 0
}

# The marker line's fixed parts (presence pinned on the forced renders; the
# full marker FORMAT, every rendered file, is the sibling suite's facet).
MARKER_LINE_PREFIX='# antz:generated version='
MARKER_LINE_SUFFIX=' -- do not edit by hand; regenerate with install.sh'

# =============================================================================
# meta-01: the specifier role's meta declares access: readwrite -- it authors
# spdd/changes/<slug>/, which no readonly grant can write. name and
# description are the declared ones.
# =============================================================================
test_meta_01() {
  ok=0
  [ "$(meta_field "$META_SPECIFIER" access)" = "readwrite" ] \
    || { echo "  specifier access is not readwrite: $(meta_field "$META_SPECIFIER" access)"; ok=1; }
  refuse "$META_SPECIFIER" 'access: readonly' || ok=1
  [ "$(meta_field "$META_SPECIFIER" name)" = "antz-specifier" ] \
    || { echo "  specifier name changed: $(meta_field "$META_SPECIFIER" name)"; ok=1; }
  [ "$(meta_field "$META_SPECIFIER" description)" = "Turns a natural-language request into Gherkin behavior specs and an end-to-end QA suite under spdd/changes/. Use first for any non-trivial feature or change." ] \
    || { echo "  specifier description changed"; ok=1; }
  return $ok
}

# =============================================================================
# meta-02: the verifier role's meta declares access: readwrite -- it merges
# into spdd/specs/, moves approved changes to spdd/archive/, and appends
# REJECTED.md. name and description are the declared ones.
# =============================================================================
test_meta_02() {
  ok=0
  [ "$(meta_field "$META_VERIFIER" access)" = "readwrite" ] \
    || { echo "  verifier access is not readwrite: $(meta_field "$META_VERIFIER" access)"; ok=1; }
  refuse "$META_VERIFIER" 'access: readonly' || ok=1
  [ "$(meta_field "$META_VERIFIER" name)" = "antz-verifier" ] \
    || { echo "  verifier name changed: $(meta_field "$META_VERIFIER" name)"; ok=1; }
  [ "$(meta_field "$META_VERIFIER" description)" = "QA agent. Validates the coder's work against spdd/changes/ Gherkin sub-specs and the end-to-end QA suite. Merges approved changes into spdd/specs/ and archives them." ] \
    || { echo "  verifier description changed"; ok=1; }
  return $ok
}

# =============================================================================
# meta-03: coder declares access: readwrite and orchestrator declares
# access: orchestrateonly, each with its declared name and description --
# field checks, no history comparison (re-keyed by sub-spec 08).
# =============================================================================
test_meta_03() {
  ok=0
  [ "$(meta_field "$META_CODER" access)" = "readwrite" ] \
    || { echo "  coder access is not readwrite"; ok=1; }
  [ "$(meta_field "$META_CODER" name)" = "antz-coder" ] \
    || { echo "  coder name changed: $(meta_field "$META_CODER" name)"; ok=1; }
  [ "$(meta_field "$META_CODER" description)" = "Implements ONE sub-spec from spdd/changes/. Plans and codes it. Never a full multi-layer plan at once." ] \
    || { echo "  coder description changed"; ok=1; }
  [ "$(meta_field "$META_ORCHESTRATOR" access)" = "orchestrateonly" ] \
    || { echo "  orchestrator access is not orchestrateonly"; ok=1; }
  [ "$(meta_field "$META_ORCHESTRATOR" name)" = "antz-orchestrator" ] \
    || { echo "  orchestrator name changed: $(meta_field "$META_ORCHESTRATOR" name)"; ok=1; }
  [ "$(meta_field "$META_ORCHESTRATOR" description)" = "Recommended entry point (via /antz). Sequences specifier -> coder -> verifier for one change, reconstructing state from spdd/ alone on every invocation so it can resume after any interruption. Never writes to spdd/ itself." ] \
    || { echo "  orchestrator description changed"; ok=1; }
  return $ok
}

# =============================================================================
# render-01 (this suite owns the id, all three readwrite roles): install.sh
# renders the role's meta for Claude Code with the readwrite tools line.
# =============================================================================
test_render_01() {
  t1_role="$1"
  prepare_renders || return 1
  f=$(agent_md "$WORK_HOME" claude "$t1_role")
  [ -f "$f" ] || { echo "  missing rendered file: $f"; return 1; }
  [ "$(tools_line "$f")" = "Read, Grep, Glob, Bash, Edit, Write, Skill" ] \
    || { echo "  tools line is: $(tools_line "$f")"; return 1; }
  # Pi carries the same readwrite grant in its own lowercase vocabulary,
  # plus the skills-catalog inheritance the roles' ## Skills sections need.
  pf=$(agent_md "$WORK_HOME" pi "$t1_role")
  [ -f "$pf" ] || { echo "  missing rendered Pi file: $pf"; return 1; }
  [ "$(tools_line "$pf")" = "read, grep, find, ls, bash, edit, write" ] \
    || { echo "  Pi tools line is: $(tools_line "$pf")"; return 1; }
  grep -qxF 'inheritSkills: true' "$pf" \
    || { echo "  Pi render lost inheritSkills: true"; return 1; }
  return 0
}

# =============================================================================
# render-02: the readwrite roles render on OpenCode with edit allowed, task
# delegation denied, subagent mode kept.
# =============================================================================
test_render_02() {
  t2_role="$1"
  prepare_renders || return 1
  f=$(agent_md "$WORK_HOME" opencode "$t2_role")
  [ -f "$f" ] || { echo "  missing rendered file: $f"; return 1; }
  require "$f" 'mode: subagent' || return 1
  require "$f" '  edit: allow' || return 1
  require "$f" '  task: deny' || return 1
  return 0
}

# =============================================================================
# render-04 (this suite owns the mapping levels): forced-access renders pin
# the readonly and orchestrateonly mappings once -- readonly maps to
# "Read, Grep, Glob, Bash" on Claude (no Edit, Write, or Skill) and to mode:
# subagent with edit: deny and task: deny on OpenCode; orchestrateonly maps
# to "Read, Grep, Glob, Bash, Agent" on Claude (no Skill); markers present.
# =============================================================================
test_render_04() {
  prepare_renders || return 1
  ok=0
  cf=$(agent_md "$READONLY_HOME" claude specifier)
  of=$(agent_md "$READONLY_HOME" opencode specifier)
  oc=$(agent_md "$ORCH_HOME" claude orchestrator)
  pf_ro=$(agent_md "$READONLY_HOME" pi specifier)
  pf_oo=$(agent_md "$ORCH_HOME" pi orchestrator)
  [ "$(tools_line "$cf")" = "Read, Grep, Glob, Bash" ] \
    || { echo "  readonly tools line is: $(tools_line "$cf")"; ok=1; }
  case "$(tools_line "$cf")" in
    *Edit*|*Write*|*Skill*) echo "  readonly tools line grants Edit, Write, or Skill: $(tools_line "$cf")"; ok=1 ;;
  esac
  require "$of" 'mode: subagent' || ok=1
  require "$of" '  edit: deny' || ok=1
  require "$of" '  task: deny' || ok=1
  [ "$(tools_line "$oc")" = "Read, Grep, Glob, Bash, Agent" ] \
    || { echo "  orchestrateonly tools line is: $(tools_line "$oc")"; ok=1; }
  case "$(tools_line "$oc")" in
    *Skill*) echo "  orchestrateonly tools line grants Skill: $(tools_line "$oc")"; ok=1 ;;
  esac
  # Pi mapping levels, forced renders: readonly grants no edit/write, and
  # orchestrateonly adds exactly the delegation tool over readonly.
  [ "$(tools_line "$pf_ro")" = "read, grep, find, ls, bash" ] \
    || { echo "  Pi readonly tools line is: $(tools_line "$pf_ro")"; ok=1; }
  case "$(tools_line "$pf_ro")" in
    *edit*|*write*|*subagent*) echo "  Pi readonly tools line grants a writer or delegator: $(tools_line "$pf_ro")"; ok=1 ;;
  esac
  [ "$(tools_line "$pf_oo")" = "read, grep, find, ls, bash, subagent" ] \
    || { echo "  Pi orchestrateonly tools line is: $(tools_line "$pf_oo")"; ok=1; }
  case "$(tools_line "$pf_oo")" in
    *edit*|*write*) echo "  Pi orchestrateonly tools line grants a writer: $(tools_line "$pf_oo")"; ok=1 ;;
  esac
  # The Pi skills-catalog inheritance mirrors the Claude Skill grant: only
  # the readwrite roles see it.
  grep -qxF 'inheritSkills: false' "$pf_ro" || { echo "  Pi readonly render inherits the skills catalog"; ok=1; }
  grep -qxF 'inheritSkills: false' "$pf_oo" || { echo "  Pi orchestrateonly render inherits the skills catalog"; ok=1; }
  for f in "$cf" "$of" "$oc" "$pf_ro" "$pf_oo"; do
    grep -qF -- "$MARKER_LINE_PREFIX" "$f" || { echo "  marker version prefix missing in $f"; ok=1; }
    grep -qF -- "$MARKER_LINE_SUFFIX" "$f" || { echo "  marker suffix missing in $f"; ok=1; }
  done
  return $ok
}

# =============================================================================
# renderdedup-01/-04/-05 (change optimize-test-suite, sub-spec 08): this
# suite's own retained render shape, scanned from ACCESS_NONCOMMENTS (its own
# source minus comment lines -- a suite may read its own file). Needles are
# quote-split or column-0-anchored so the scanning code can never match
# itself.
# =============================================================================

# renderdedup-01: the render-01 id is owned by this suite -- registered once
# for each readwrite role (specifier, coder, verifier) -- and render-02 stays
# registered for specifier and verifier only.
test_renderdedup_01() {
  ok=0
  for role in specifier coder verifier; do
    n=$(grep -cF "run_test \"render-01 ($role)" "$ACCESS_NONCOMMENTS")
    [ "$n" -eq 1 ] || { echo "  render-01 ($role) registered $n times, expected 1"; ok=1; }
  done
  n=$(grep -cE '^run_test "render-01' "$ACCESS_NONCOMMENTS")
  [ "$n" -eq 3 ] || { echo "  render-01 registered $n times in total, expected 3"; ok=1; }
  for role in specifier verifier; do
    n=$(grep -cF "run_test \"render-02 ($role)" "$ACCESS_NONCOMMENTS")
    [ "$n" -eq 1 ] || { echo "  render-02 ($role) registered $n times, expected 1"; ok=1; }
  done
  n=$(grep -cE '^run_test "render-02' "$ACCESS_NONCOMMENTS")
  [ "$n" -eq 2 ] || { echo "  render-02 registered $n times in total, expected 2"; ok=1; }
  return $ok
}

# renderdedup-04: the history-comparison machinery is gone -- no
# version-control command or history baseline anywhere in the non-comment
# source, render-03 removed entirely (no registration, no function), meta-03
# reduced to field checks, render-04 pinning the mapping levels via
# forced-access renders only -- and every render goes through the harness
# library's helpers.
test_renderdedup_04() {
  ok=0
  refuse "$ACCESS_NONCOMMENTS" 'gi''t ' || ok=1
  refuse "$ACCESS_NONCOMMENTS" 'HE''AD' || ok=1
  refuse "$ACCESS_NONCOMMENTS" 'byte_identical_to_hea''d' || ok=1
  refuse "$ACCESS_NONCOMMENTS" 'head_meta_a''t' || ok=1
  refuse "$ACCESS_NONCOMMENTS" 'INSTALL_S''H' || ok=1
  refuse "$ACCESS_NONCOMMENTS" 'env -u XD''G' || ok=1
  n=$(grep -cE '^run_test "render-03' "$ACCESS_NONCOMMENTS")
  [ "$n" -eq 0 ] || { echo "  render-03 still registered ($n times)"; ok=1; }
  refuse "$ACCESS_NONCOMMENTS" 'test_render_0''3' || ok=1
  d=$(new_tmp_dir)
  extract_fn "$ACCESS_NONCOMMENTS" test_meta_03 "$d/meta03"
  [ -s "$d/meta03" ] || { echo "  meta-03's test function is missing"; ok=1; }
  require "$d/meta03" 'meta_field "$META_CODER" access' || ok=1
  require "$d/meta03" 'meta_field "$META_CODER" name' || ok=1
  require "$d/meta03" 'meta_field "$META_CODER" description' || ok=1
  require "$d/meta03" 'meta_field "$META_ORCHESTRATOR" access' || ok=1
  require "$d/meta03" 'meta_field "$META_ORCHESTRATOR" name' || ok=1
  require "$d/meta03" 'meta_field "$META_ORCHESTRATOR" description' || ok=1
  extract_fn "$ACCESS_NONCOMMENTS" test_render_04 "$d/render04"
  [ -s "$d/render04" ] || { echo "  render-04's test function is missing"; ok=1; }
  require "$d/render04" '"Read, Grep, Glob, Bash"' || ok=1
  require "$d/render04" '"Read, Grep, Glob, Bash, Agent"' || ok=1
  require "$d/render04" 'READONLY_HOME' || ok=1
  require "$d/render04" 'ORCH_HOME' || ok=1
  # The library route: staged trees rendered through render_tree, never a
  # hand-rolled install.sh invocation.
  require "$ACCESS_NONCOMMENTS" 'stage_checko''ut' || ok=1
  require "$ACCESS_NONCOMMENTS" 'render_tre''e' || ok=1
  return $ok
}

# renderdedup-05: docs-01..04 are no longer registered and no exact-phrase
# policy-doc assertion survives in this suite; the access model stays pinned
# by the meta declarations and the render mappings.
test_renderdedup_05() {
  ok=0
  for id in docs-01 docs-02 docs-03 docs-04; do
    n=$(grep -cE "^[[:space:]]*(run_test|skip_test)[[:space:]]+\"$id" "$ACCESS_NONCOMMENTS")
    [ "$n" -eq 0 ] || { echo "  $id still registered ($n times)"; ok=1; }
  done
  refuse "$ACCESS_NONCOMMENTS" 'AGENTS.m''d' || ok=1
  refuse "$ACCESS_NONCOMMENTS" 'CLAUDE.m''d' || ok=1
  refuse "$ACCESS_NONCOMMENTS" 'docs/orchestrator.m''d' || ok=1
  for id in meta-01 meta-02 meta-03 render-04; do
    n=$(grep -cE "^run_test \"$id" "$ACCESS_NONCOMMENTS")
    [ "$n" -eq 1 ] || { echo "  $id registered $n times, expected 1"; ok=1; }
  done
  for id in render-01 render-02; do
    n=$(grep -cE "^run_test \"$id" "$ACCESS_NONCOMMENTS")
    [ "$n" -ge 1 ] || { echo "  $id no longer registered"; ok=1; }
  done
  return $ok
}

# ---- run everything ---------------------------------------------------------

run_test "meta-01: agents/meta/specifier.yaml declares access: readwrite (name/description unchanged)" test_meta_01
run_test "meta-02: agents/meta/verifier.yaml declares access: readwrite (name/description unchanged)" test_meta_02
run_test "meta-03: coder.yaml declares access: readwrite and orchestrator.yaml declares access: orchestrateonly, each with its declared name and description" test_meta_03

run_test "render-01 (specifier): Claude render of agents/meta/specifier.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 specifier
run_test "render-01 (coder): Claude render of agents/meta/coder.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 coder
run_test "render-01 (verifier): Claude render of agents/meta/verifier.yaml carries tools: Read, Grep, Glob, Bash, Edit, Write, Skill" test_render_01 verifier
run_test "render-02 (specifier): OpenCode render of agents/meta/specifier.yaml carries mode: subagent, edit: allow, task: deny" test_render_02 specifier
run_test "render-02 (verifier): OpenCode render of agents/meta/verifier.yaml carries mode: subagent, edit: allow, task: deny" test_render_02 verifier
run_test "render-04: the mapping levels pinned once via forced-access renders -- readonly maps to the four-reader Claude line (no Edit, Write, or Skill) and mode: subagent with edit: deny and task: deny on OpenCode; orchestrateonly maps to the Claude line plus Agent (no Skill); markers present" test_render_04

run_test "renderdedup-01: render-01 is registered for specifier, coder, and verifier (sole owner of the role agents' Claude readwrite tools line) and render-02 stays registered for specifier and verifier only" test_renderdedup_01
run_test "renderdedup-04: render-03 is removed entirely, meta-03 keeps its field checks alone, and render-04 pins the mapping levels via forced renders with no source-line greps -- current-version mechanisms only" test_renderdedup_04
run_test "renderdedup-05: docs-01..04 are no longer registered, no exact-phrase policy-doc assertion survives here, and the access model stays pinned by the meta declarations and the render mappings" test_renderdedup_05

# ---- e2e-only scenarios: explicit SKIP stubs ---------------------------------
# e2e-meta-01..02 (spdd/changes/specifier-write-access/01-meta.feature),
# e2e-render-01..02 (02-render.feature), and e2e-docs-01 (03-docs.feature)
# operate at the user's machine-level UI (installed agent files under the
# real home, or reading the docs at the user surface) -- e2e only, run by
# the verifier. Explicit stubs so every scenario id is accounted for.

E2E_REASON="e2e-only: requires invoking the installed agents, run by the verifier (01-meta.feature)"
E2E_RENDER_REASON="e2e-only: requires running the installer's CLI against the user's real home, run by the verifier (02-render.feature)"
E2E_DOCS_REASON="e2e-only: operates at the user-visible reading surface, run by the verifier (03-docs.feature)"

skip_test "e2e-meta-01: a specifier invocation actually writes spdd/changes/<slug>/ artifacts (no silent no-op for lack of edit permission)" "$E2E_REASON"
skip_test "e2e-meta-02: a verifier invocation actually writes (spec merge + archive move, or a REJECTED.md append; no silent no-op)" "$E2E_REASON"
skip_test "e2e-render-01: ./install.sh --all overwrites the hand-patched temporary edit grants with the real renders, marker format unchanged" "$E2E_RENDER_REASON"
skip_test "e2e-render-02: ./install.sh --check reports the drift and prints the changelog before reinstall, and reports up to date after" "$E2E_RENDER_REASON"
skip_test "e2e-docs-01: a user reading the docs derives the real access model, with no contradiction left against the meta files or the roles' prompts" "$E2E_DOCS_REASON"

finish_suite
