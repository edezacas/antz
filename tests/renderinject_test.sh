#!/usr/bin/env bash
# Unit tests for install.sh's orchestrator include-marker injection, covering
# every scenario in spdd/changes/orchestrator-fast-path/02-renderinject.feature
# (renderinject-01..07). The change: agents/prompts/orchestrator.prompt carries
# one "# antz-include: scripts/orchestration/<name>.sh" marker line per script
# fence (sub-spec 01), and install.sh substitutes each marker with the verbatim
# content of the named file when rendering the antz-orchestrator agent -- for
# both Claude Code and OpenCode. No behavior change: the rendered orchestrator
# body is byte-identical to the pre-change render (same version marker).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/installsh-posixsh_test.sh. Run directly:
#   ./tests/renderinject_test.sh
#
# Each reported test name embeds its scenario id (renderinject-01..07) from
# the feature file above, so a failure maps straight back to the scenario it
# covers. Every test that touches the filesystem runs against isolated temp
# dirs, never the real ~/.claude or ~/.config/opencode.
#
# The pre-change render baseline is materialized from git at this change's
# base (merge-base with master), so the suite keeps passing after the change
# is committed: once the base tree equals the working tree (post-merge), the
# base-derived byte-identity assertions are vacuous and are skipped without
# failing (same convention as tests/installsh-posixsh_test.sh), while the
# structural assertions (no marker survives, verbatim script content at the
# fences, frontmatter shape, runtime wording, failure behavior, docs wording)
# hold against the working tree forever.
#
# Evolved by change orchestrator-fast-path (sub-spec 04, sessionguards): the
# orchestrator prompt legitimately gains additive prose (the session guards),
# so the base-render byte-identity assertions are additionally gated on the
# prompt's prose (the file minus its fenced blocks) being unchanged vs the
# base. While the only prompt change vs the base is the fence->marker
# conversion, they remain the no-drift proof of the injection itself; once a
# prompt-prose sub-spec of this change lands, they are vacuously retired
# (with a loud note, like a skip) -- the render then legitimately differs by
# that prose, and the structural assertions keep holding forever.
#
# Evolved again by sub-spec 05 (receipts): the step-3 rewrite makes the
# orchestrator prose distinct (retiring the orchestrator base-render
# identity) and the coder prompt gains its "## Receipt" section, so
# renderinject-05's non-orchestrator byte-identity assertions are gated per
# role the same way (role_prompt_prose_distinct): the coder's rendered
# copies retire with a loud note while the specifier/verifier renders and
# the command renders stay byte-identity-enforced.
#
# Version-marker note: the byte-identity comparisons mask each rendered
# file's "version=X.Y.Z" marker value before cmp, so the suite stays green
# when a later sub-spec of this change (06 closingblock) legitimately bumps
# VERSION -- the pin asserts body identity, not version equality; the
# inventory and frontmatter assertions are unaffected either way.
#
# Evolved by change flow-script-guards (sub-spec 01, ensure-20): an injected
# scripts/orchestration/ file is a third retirement source for the
# orchestrator base-render byte-identity gate (scripts_distinct /
# SCRIPTS_DISTINCT). A script-only sub-spec changes the working tree while
# the prompt's prose is untouched, so the prose key alone could not retire
# the vacuous assertion; a change touching both sources retires it once,
# with a note per reason -- never a double failure. The marker-substitution
# reconstruction and the structural render assertions stay enforced either
# way.
#
# Evolved by change hardening-installsh (sub-spec 01, marker): renderinject-
# 06's base-vs-working install.sh header byte-identity window is retired
# (loud note) for that change's legitimate header edits; its tracked-set
# sentence assertion stays enforced.
#
# Evolved again by change hardening-installsh (sub-spec 02, quoting): the
# rendered description: values are double-quoted YAML scalars at all three
# render sites, so the pre-change render legitimately differs from the base
# render on exactly those lines. Loud re-scope note: the base-vs-working
# byte-identity comparisons in renderinject-01/02/03/05 now normalize each
# working render through dequote_description (the exact inverse of the
# quoting) before comparing, so each assertion keeps pinning the full
# pre-change render modulo the quoting change itself -- the injection's
# no-drift proof survives rather than being dropped. All structural
# assertions (reconstruction, frontmatter shape, fences, inventory, keyed
# behavior, --check report) are unaffected and stay enforced.
#
# Evolved again by change hardening-installsh (sub-spec 04, setmodel): the
# embedded /antz-set-model script legitimately gains its anchored line-start
# header-marker check and mktemp cleanup trap, so the pre-change render of
# the two antz-set-model.md command files differs from the working render
# inside exactly that ```sh fence. renderinject-03/-05 keep the byte-identity
# pin for everything else by masking the fence's script body on both sides
# (mask_set_model_script) -- the no-drift proof is preserved everywhere it
# still applies, and the masked script's behavior is pinned forever by
# tests/set-model-command_test.sh (set-model-cmd-01..12, setmodel-01..04).
#
# Re-scoped by change deembed-orchestration-scripts (sub-spec 05,
# testsuite-05): the include-marker injection is retired.
#   - LOUD NOTE: the marker-substitution reconstruction
#     (reconstruct_expected_body) retires -- there are no markers to
#     reconstruct, and the fence-carve-out checks (```sh probe opener,
#     '  done' glitch line, injected-script-start presence) retire with it;
#     the scripts' behavior is pinned forever by the script suites against
#     the byte-identical sources.
#   - The no-survivor assertion re-keys to: no '# antz-include:' marker AND
#     no script-content fence in any rendered file.
#   - The prompt usage-line pins re-key to the path-based forms (the
#     rendered body carries the flow/skills/probe invocations with the
#     concrete resolved libdir substituted for __ANTZ_SCRIPTS_DIR__).
#   - The AGENTS.md/CLAUDE.md runtime-wording check re-keys to sub-spec 04's
#     installed-library wording.
#   - LOUD NOTE: the set-model command byte-identity masks retire -- those
#     command bodies legitimately changed in sub-spec 03 (fence gone, path
#     invocation, client first argument); their contract is pinned forever
#     by tests/set-model-command_test.sh and tests/setmodeldeembed_test.sh.
#   - The --check report-shape clause re-keys the same way: sub-spec 01's
#     legitimate extension appends one artifact line per libdir script after
#     the per-client lines; the four script lines are masked for the base
#     comparison, and "--check writes nothing" stays enforced.
#   - Fixed here too: dequote_description was applied only to the working
#     side -- a normalization fitting a pre-quoting BASE era. The base tree
#     (merge-base at 4.7.1) already carries quoted descriptions, so the
#     quote-stripping now reactivates as a one-sided bug. Both sides are
#     normalized alike, making the comparison era-neutral.
#   - Hermeticity: every render/--check run masks the session environment
#     (env -u XDG_CONFIG_HOME HOME=<temp home>), so install.sh's libdir step
#     resolves INSIDE the temp home and no test writes outside a temp dir on
#     a box with XDG_CONFIG_HOME exported.
# The structural assertions that stay enforced -- frontmatter shape, install
# inventory (12 client files plus the four libdir scripts), placeholder-free
# rendering with no substitution leaking anywhere, quoted descriptions --
# re-key to and keep passing on the invocation shape.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

pass_count=0
fail_count=0
skip_count=0

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

skip_test() {
  # $1 = reported test name (must contain its scenario id), $2 = reason.
  # An explicit, accounted-for stub for a scenario that is out of scope for
  # unit-level TDD (never a silent omission) -- same helper as
  # tests/versioning-rule_test.sh.
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
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

# ---- base-tree materialization ---------------------------------------------

# The change's base commit (pre-change tree: orchestrator.prompt still carries
# the embedded script snippets; install.sh still renders bodies verbatim).
base_commit() {
  git -C "$SCRIPT_DIR" merge-base master HEAD 2>/dev/null || echo HEAD
}

# Materializes the base tree to $1 via git archive (tracked files only, which
# is exactly the pre-change tree) and echoes 1 when the base install.sh is
# still distinct from the working tree's, 0 when the two already agree (a
# post-merge degenerate tree: every base-derived identity assertion is vacuous
# and must not fail, like prep_base_if_distinct in the posixsh suite).
prep_base_tree() {
  out="$1"
  mkdir -p "$out"
  git -C "$SCRIPT_DIR" archive "$(base_commit)" | tar -x -C "$out" || return 1
  if cmp -s "$INSTALL_SH" "$out/install.sh"; then
    printf '0'
  else
    printf '1'
  fi
}

# Renders the full install (both clients, --all) from the tree at $1 into the
# isolated HOME $2, logging stdout+stderr to $3. Hermetic since change
# deembed-orchestration-scripts (testsuite-05): the session's XDG_CONFIG_HOME
# is masked so install.sh's libdir step resolves the scripts dir INSIDE the
# temp home (empty falls back like unset) instead of writing to the real
# ~/.config/antz on an exported-XDG box.
render_tree() {
  src="$1"; home="$2"; log="$3"
  mkdir -p "$home"
  (cd "$src" && env -u XDG_CONFIG_HOME HOME="$home" sh ./install.sh --all > "$log" 2>&1)
}

# Strips a rendered agent file's frontmatter (the two '---' fences and the
# blank separator line), printing only the body to stdout.
strip_frontmatter() {
  awk '
    /^---$/ { if (n < 2) { n++; next } }
    n < 2 { next }
    n == 2 && !seen && $0 == "" { seen = 1; next }
    { print }
  ' "$1"
}

# Masks the embedded version value in a rendered file's marker comment (see
# the file-header version-marker note).
mask_version() {
  sed 's/version=[0-9][0-9.]*/version=VERSIONMASKED/' "$1"
}

# Inverse of install.sh's 02-quoting transformation for base-render
# comparisons: prints $1 with its frontmatter `description: "<escaped>"`
# line rewritten to the pre-quoting plain form (outer quotes stripped,
# \" -> " and \\ -> \ undone left-to-right, first quoted description line
# only, within the first frontmatter). Files whose description is already
# plain pass through unchanged, so unquoted renders (the /antz commands)
# and the git base tree are unaffected. Trailing-newline fidelity: every
# rendered file ends WITHOUT a newline (install_file writes command-
# substituted content with printf '%s'), so the awk-added ORS is stripped
# again here to keep the byte-identity comparisons byte-exact. See the
# # re-scoped note. Era-neutralized by change deembed-orchestration-scripts
# (testsuite-05): this was applied only to the WORKING side, which fits a
# pre-quoting base era only; the base tree at merge-base 4.7.1 already
# carries quoted descriptions, so a one-sided dequote fabricates a drift.
# norm_render below applies it (plus the version mask) to BOTH sides.
dequote_description() {
  out=$(awk '
    /^---[ \t]*$/ { fences++; print; next }
    fences == 1 && !dqdone && /^description: "/ {
      dqdone = 1
      v = $0
      sub(/^description: "/, "", v)
      sub(/"$/, "", v)
      out = ""
      n = length(v)
      i = 1
      while (i <= n) {
        c = substr(v, i, 1)
        if (c == "\\") {
          d = substr(v, i + 1, 1)
          if (d == "\\" || d == "\"") { out = out d; i += 2; continue }
        }
        out = out c
        i++
      }
      print "description: " out
      next
    }
    { print }
  ' "$1")
  printf '%s' "$out"
}

# norm_render <file> <dest>: the era-neutral base-vs-working normalization --
# dequote_description plus the version mask, applied to BOTH sides of every
# byte-identity comparison alike (testsuite-05: the one-sided application
# was a normalization fitting a pre-quoting base era; both sides carry
# quoted descriptions now, and masking both keeps the pin exact whatever
# era the base tree is from).
norm_render() {
  dequote_description "$1" | sed 's/version=[0-9][0-9.]*/version=VERSIONMASKED/' > "$2"
}

# Re-scope normalization for the /antz-set-model command renders (change
# hardening-installsh, sub-spec 04): the renders embed the set-model script,
# and 04 legitimately edits that script (anchored line-start header-marker
# check + mktemp cleanup trap), so the base-vs-working byte-identity pins for
# the two antz-set-model.md files compare them with the single ```sh fence's
# BODY replaced by a one-line placeholder (the fence lines stay). Loud note:
# every other byte of the command render (frontmatter, flow-head/tail prose,
# alias vocabulary, fences) stays identity-enforced; the masked region's
# behavior is pinned forever by the current extraction in
# tests/set-model-command_test.sh (set-model-cmd-01..12, setmodel-01..04).
# Trailing-newline fidelity matches dequote_description above: rendered files
# end WITHOUT a newline, so the awk-added ORS is stripped again.
mask_set_model_script() {
  # $1 = path to a rendered /antz-set-model command file.
  out=$(awk '
    /^```sh$/ && !masked { print; masked = 1; insh = 1; print "<<embedded set-model script (masked for the 04-setmodel edit)>>"; next }
    insh && /^```$/ { insh = 0; print; next }
    insh { next }
    { print }
  ' "$1")
  printf '%s' "$out"
}

# Strips every fenced block (``` or ```sh openers/closers and their bodies)
# from a prompt file, leaving only the prose. The prompt carries no other
# triple-backtick usage, so this is exact.
strip_fences() {
  awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$1"
}

# Sets PROMPT_PROSE_DISTINCT to 1 when the working orchestrator.prompt's
# prose differs from the base copy's (a later sub-spec's legitimate additive
# edit, e.g. sub-spec 04's session guards), 0 when the only prompt change vs
# the base is the fence->marker conversion. Gates the base-render byte-
# identity assertions (see the header note).
prompt_prose_distinct() {
  work=$(mktemp)
  basep=$(mktemp)
  strip_fences "$SCRIPT_DIR/agents/prompts/orchestrator.prompt" > "$work"
  strip_fences "$BASE_TREE_DIR/agents/prompts/orchestrator.prompt" > "$basep"
  if cmp -s "$work" "$basep"; then
    printf '0'
  else
    printf '1'
  fi
  rm -f "$work" "$basep"
}

# Prints 1 when a role's prompt prose (the file minus its fenced blocks)
# differs working vs base -- a later sub-spec's legitimate prose edit to
# that role's prompt -- else 0. Gates renderinject-05's per-file byte-
# identity assertions for the role's rendered copies (the orchestrator's
# copies are handled by if_base_identity_active / renderinject-01..03).
role_prompt_prose_distinct() {
  work=$(mktemp)
  basep=$(mktemp)
  strip_fences "$SCRIPT_DIR/agents/prompts/$1.prompt" > "$work"
  strip_fences "$BASE_TREE_DIR/agents/prompts/$1.prompt" > "$basep"
  if cmp -s "$work" "$basep"; then
    printf '0'
  else
    printf '1'
  fi
  rm -f "$work" "$basep"
}

# Prints 1 when any injected scripts/orchestration/ file differs working vs
# base — this change's (flow-script-guards) legitimate script edit retires
# the pre-change render byte-identity the same way a prose edit does: a
# script-only sub-spec changes the rendered orchestrator body by contract.
# Compares the union of the two dirs' *.sh listings, so an added or removed
# script counts as a difference too. Prints 0 when every injected file is
# byte-identical in both trees (see the header note).
scripts_distinct() {
  work="$SCRIPT_DIR/scripts/orchestration"
  base="$BASE_TREE_DIR/scripts/orchestration"
  for f in "$work"/*.sh; do
    [ -e "$f" ] || continue
    b="$base/$(basename "$f")"
    [ -e "$b" ] || { printf '1'; return 0; }
    cmp -s "$f" "$b" || { printf '1'; return 0; }
  done
  for f in "$base"/*.sh; do
    [ -e "$f" ] || continue
    [ -e "$work/$(basename "$f")" ] || { printf '1'; return 0; }
  done
  printf '0'
}

# The gate for the base-derived byte-identity assertions: active only while
# the base install.sh is distinct AND neither the prompt's prose nor any
# injected scripts/orchestration/ file has moved vs the base; prints a loud
# retirement note per changed source when they have (not a failure — a
# change touching both sources retires the assertion once, never twice).
if_base_identity_active() {
  if [ "$BASE_DISTINCT" -ne 1 ]; then
    return 1
  fi
  if [ "$SCRIPTS_DISTINCT" -eq 1 ]; then
    echo "  note: an injected scripts/orchestration/ file changed vs the base (this change's script edit); the pre-change byte-identity assertion is vacuously retired, structural assertions still enforced"
  fi
  if [ "$PROMPT_PROSE_DISTINCT" -eq 1 ]; then
    echo "  note: orchestrator.prompt prose changed vs the base (a later sub-spec's additive edit); the pre-change byte-identity assertion is vacuously retired, structural assertions still enforced"
  fi
  if [ "$SCRIPTS_DISTINCT" -eq 1 ] || [ "$PROMPT_PROSE_DISTINCT" -eq 1 ]; then
    return 1
  fi
  return 0
}

# LOUD NOTE (change deembed-orchestration-scripts, testsuite-05): the
# marker-substitution reconstruction helper (reconstruct_expected_body) is
# retired here -- the de-embedded prompt carries no '# antz-include:' markers
# to reconstruct from, and install.sh's injection machinery is gone (this
# file greps for its absence). The new-era body identity (prompt + concrete
# resolved libdir substitution) is asserted directly in renderinject_01.

# Materializes the working tree's render inputs (install.sh, agents/,
# scripts/, VERSION, CHANGELOG.md) to $1 so renders can be made to fail or
# behave differently without touching the real checkout.
copy_render_inputs() {
  dst="$1"
  mkdir -p "$dst"
  cp "$SCRIPT_DIR/install.sh" "$dst/"
  cp -r "$SCRIPT_DIR/agents" "$dst/"
  cp -r "$SCRIPT_DIR/scripts" "$dst/"
  cp "$SCRIPT_DIR/VERSION" "$SCRIPT_DIR/CHANGELOG.md" "$dst/"
}

# (assert_no_marker_in_tree retired with the markers: assert_no_embed_survivor,
# defined above renderinject_01, is its de-embedded successor.)

# ---- ensure-20 (change flow-script-guards, sub-spec 01) ----------------------
# The base-render byte-identity gate, previously keyed on the prompt's prose
# alone, must ALSO retire when an injected scripts/orchestration/ file
# differs from the base tree: a script-only sub-spec (antz-flow.sh edited,
# prompt prose untouched) legitimately changes the rendered orchestrator
# body. The reconstruction and structural assertions of renderinject-01..03
# stay enforced either way; the gate is pinned here at its decision function
# and its helper against synthetic gating states and fixture trees (the
# working tree itself may or may not differ from the base — a vacuously
# retired gate still passes the suites, so pinning the logic, not the
# moment, is what survives).
ensure_20_helper_on_fixtures() {
  ok=0
  d=$(new_tmp_dir)
  mkdir -p "$d/w/scripts/orchestration" "$d/b/scripts/orchestration"
  for s in antz-flow antz-probe antz-skills; do
    printf 'content-%s\n' "$s" > "$d/w/scripts/orchestration/$s.sh"
    cp "$d/w/scripts/orchestration/$s.sh" "$d/b/scripts/orchestration/$s.sh"
  done
  got=$( SCRIPT_DIR="$d/w" BASE_TREE_DIR="$d/b"; scripts_distinct )
  [ "$got" = "0" ] || { echo "  identical script dirs reported distinct ($got)"; ok=1; }
  printf 'edited\n' > "$d/w/scripts/orchestration/antz-flow.sh"
  got=$( SCRIPT_DIR="$d/w" BASE_TREE_DIR="$d/b"; scripts_distinct )
  [ "$got" = "1" ] || { echo "  an edited injected script not reported distinct ($got)"; ok=1; }
  rm "$d/w/scripts/orchestration/antz-flow.sh"
  cp "$d/b/scripts/orchestration/antz-flow.sh" "$d/w/scripts/orchestration/antz-flow.sh"
  printf 'new\n' > "$d/w/scripts/orchestration/antz-extra.sh"
  got=$( SCRIPT_DIR="$d/w" BASE_TREE_DIR="$d/b"; scripts_distinct )
  [ "$got" = "1" ] || { echo "  an extra injected script not reported distinct ($got)"; ok=1; }
  rm "$d/w/scripts/orchestration/antz-extra.sh"
  rm "$d/b/scripts/orchestration/antz-skills.sh"
  got=$( SCRIPT_DIR="$d/w" BASE_TREE_DIR="$d/b"; scripts_distinct )
  [ "$got" = "1" ] || { echo "  a missing base script not reported distinct ($got)"; ok=1; }
  return $ok
}

ensure_20_gate_decision() {
  ok=0
  # The active case is unchanged: base distinct, prose and scripts intact.
  out=$( BASE_DISTINCT=1 PROMPT_PROSE_DISTINCT=0 SCRIPTS_DISTINCT=0 if_base_identity_active ); rc=$?
  [ "$rc" -eq 0 ] || { echo "  gate went inactive with nothing changed vs base"; ok=1; }
  # Scripts distinct alone retires the gate, with a loud note.
  out=$( BASE_DISTINCT=1 PROMPT_PROSE_DISTINCT=0 SCRIPTS_DISTINCT=1 if_base_identity_active ); rc=$?
  [ "$rc" -ne 0 ] || { echo "  gate stayed active with an injected script differing from the base"; ok=1; }
  printf '%s' "$out" | grep -qF 'scripts/orchestration/' \
    || { echo "  the script-distinct retirement printed no loud note: $out"; ok=1; }
  # Prose distinct still retires, as before.
  out=$( BASE_DISTINCT=1 PROMPT_PROSE_DISTINCT=1 SCRIPTS_DISTINCT=0 if_base_identity_active ); rc=$?
  [ "$rc" -ne 0 ] || { echo "  gate stayed active with the prompt prose changed"; ok=1; }
  # Both distinct (sub-spec 02's prose edit landing on top of this script
  # edit): one retirement, no double failure.
  out=$( BASE_DISTINCT=1 PROMPT_PROSE_DISTINCT=1 SCRIPTS_DISTINCT=1 if_base_identity_active ); rc=$?
  [ "$rc" -ne 0 ] || { echo "  gate did not retire with both sources changed"; ok=1; }
  # The degenerate post-merge tree still retires silently as before.
  out=$( BASE_DISTINCT=0 PROMPT_PROSE_DISTINCT=0 SCRIPTS_DISTINCT=0 if_base_identity_active ); rc=$?
  [ "$rc" -ne 0 ] || { echo "  gate stayed active on a base-identical tree"; ok=1; }
  return $ok
}

# ---- shared fixtures (rendered once, shared by the identity tests) ----------

BASE_TREE_DIR=""
BASE_DISTINCT=""
PROMPT_PROSE_DISTINCT=""
SCRIPTS_DISTINCT=""
HOME_A=""
HOME_B=""

setup_fixtures() {
  base=$(new_tmp_dir)/base-tree
  BASE_TREE_DIR="$base"
  BASE_DISTINCT=$(prep_base_tree "$base" "$INSTALL_SH") || {
    echo "FATAL: could not materialize the base tree" >&2
    return 1
  }
  HOME_A=$(new_tmp_dir)/home-base
  HOME_B=$(new_tmp_dir)/home-new
  alog=$(new_tmp_dir)/render-a.log
  blog=$(new_tmp_dir)/render-b.log
  render_tree "$base" "$HOME_A" "$alog" || {
    echo "FATAL: base render failed: $(cat "$alog")" >&2
    return 1
  }
  render_tree "$SCRIPT_DIR" "$HOME_B" "$blog" || {
    echo "FATAL: working-tree render failed: $(cat "$blog")" >&2
    return 1
  }
  PROMPT_PROSE_DISTINCT=$(prompt_prose_distinct)
  SCRIPTS_DISTINCT=$(scripts_distinct)
  return 0
}

if ! setup_fixtures; then
  echo "FATAL: fixture setup failed; suite cannot run" >&2
  exit 1
fi

# ---- renderinject-01 ---------------------------------------------------------
# Re-scoped by change deembed-orchestration-scripts (testsuite-05): the
# marker-substitution reconstruction retires with a loud note (no markers
# exist to reconstruct). The rendered Claude Code orchestrator body is now
# exactly the source prompt with the concrete resolved libdir substituted
# for __ANTZ_SCRIPTS_DIR__, with no marker and no script-content fence
# surviving anywhere in the install tree.

# Assert the de-embedded no-survivor rule on one installed tree: no
# '# antz-include:' marker AND no script-content fence in any rendered file
# (the only fences left are the prompt's own template blocks, never a ```sh
# opener), no script body line ever appears, and no placeholder token
# survives.
assert_no_embed_survivor() {
  # $1 = HOME tree.
  home="$1"
  hits=$(grep -rl '# antz-include:' "$home" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "marker line survived the render in: $hits"
    return 1
  fi
  hits=$(grep -rl '```sh' "$home/.claude/agents" "$home/.config/opencode/agents" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "a script-content fence survived the render in: $hits"
    return 1
  fi
  hits=$(grep -rl '__ANTZ_SCRIPTS_DIR__' "$home" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "the __ANTZ_SCRIPTS_DIR__ placeholder survived the render in: $hits"
    return 1
  fi
  local script first
  for script in antz-flow antz-probe antz-skills; do
    # A script's distinctive body line (its second line, skipping shebangs)
    # must never appear in any rendered agent body -- the scripts are
    # installed separately, not embedded.
    first=$(sed -n '2p' "$SCRIPT_DIR/scripts/orchestration/$script.sh")
    if [ -n "$first" ] && grep -rlF "$first" "$home/.claude/agents" "$home/.config/opencode/agents" >/dev/null 2>&1; then
      echo "rendered agent bodies carry $script.sh content"
      return 1
    fi
  done
  return 0
}

renderinject_01() {
  f="$HOME_B/.claude/agents/antz-orchestrator.md"
  [ -f "$f" ] || { echo "missing rendered file: $f"; return 1; }
  assert_no_embed_survivor "$HOME_B" || return 1
  # Byte-identity against the pre-change render (same version marker, masked)
  # -- gated per the header note on the prompt prose being unchanged vs base,
  # and re-scoped quoting-aware (dequote_description) per the header's
  # 02-quoting note.
  if if_base_identity_active; then
    d=$(new_tmp_dir)
    norm_render "$f" "$d/new.masked"
    norm_render "$HOME_A/.claude/agents/antz-orchestrator.md" "$d/base.masked"
    if ! cmp -s "$d/new.masked" "$d/base.masked"; then
      echo "rendered Claude Code orchestrator body drifted from the pre-change render (modulo the era-neutral quoting + version normalization)"
      diff "$d/base.masked" "$d/new.masked" | head -10
      return 1
    fi
  fi
  # LOUD NOTE (testsuite-05): the marker-substitution reconstruction
  # (reconstruct_expected_body) retires here -- the de-embedded prompt has
  # no markers to reconstruct from. The new-era structural identity takes
  # its place: the rendered body is exactly the prompt with the concrete
  # resolved libdir substituted for __ANTZ_SCRIPTS_DIR__.
  d=$(new_tmp_dir)
  sed "s|__ANTZ_SCRIPTS_DIR__|$HOME_B/.config/antz/scripts|g" \
    "$SCRIPT_DIR/agents/prompts/orchestrator.prompt" > "$d/expected.body"
  strip_frontmatter "$f" > "$d/actual.body"
  if ! cmp -s "$d/expected.body" "$d/actual.body"; then
    echo "rendered body is not the source prompt with the concrete resolved libdir substituted"
    diff "$d/expected.body" "$d/actual.body" | head -10
    return 1
  fi
  # Oracle-free guard for the indent-prefixed-blank-line failure class: the
  # pre-change render (and the prompt) contain no whitespace-only lines, so
  # the rendered body must never grow one.
  ws=$(grep -cE '^[[:space:]]+$' "$f")
  [ "$ws" -eq 0 ] || { echo "rendered body has $ws whitespace-only line(s) (blank lines must stay empty)"; return 1; }
  # LOUD NOTE: the '  done' under-fence-indent glitch pin and the ```sh
  # probe-opener pin retire with the embed -- the skills snippet's glitch
  # line and the probe fence belonged to the injected script content, which
  # no longer renders (assert_no_embed_survivor proves its absence above).
  return 0
}

# ---- renderinject-02 ---------------------------------------------------------

renderinject_02() {
  f="$HOME_B/.config/opencode/agents/antz-orchestrator.md"
  [ -f "$f" ] || { echo "missing rendered file: $f"; return 1; }
  assert_no_embed_survivor "$HOME_B" || return 1
  # Byte-identity against the pre-change render -- same gate as -01, and the
  # same era-neutral normalization (norm_render: quoting + version mask on
  # BOTH sides; see the header's testsuite-05 note).
  if if_base_identity_active; then
    d=$(new_tmp_dir)
    norm_render "$f" "$d/new.masked"
    norm_render "$HOME_A/.config/opencode/agents/antz-orchestrator.md" "$d/base.masked"
    if ! cmp -s "$d/new.masked" "$d/base.masked"; then
      echo "rendered OpenCode orchestrator body drifted from the pre-change render (modulo the era-neutral quoting + version normalization)"
      diff "$d/base.masked" "$d/new.masked" | head -10
      return 1
    fi
  fi
  # Frontmatter keeps its pre-change shape: mode: primary, edit: deny, and the
  # deny-by-default task allowlist (the body's only difference from the
  # pre-change render is the de-embed itself).
  grep -q '^mode: primary$' "$f" || { echo "frontmatter lost 'mode: primary'"; return 1; }
  grep -q '^  edit: deny$' "$f" || { echo "frontmatter lost 'edit: deny'"; return 1; }
  # The deny-by-default task object: a bare "task:" key (the scalar slot left
  # empty) whose object opens with the deny-all glob.
  grep -q '^  task: *$' "$f" || { echo "frontmatter lost the bare task: key"; return 1; }
  for role in specifier coder verifier; do
    grep -q "^    antz-$role: allow$" "$f" || {
      echo "frontmatter lost the task allowlist entry for antz-$role"; return 1
    }
  done
  grep -q '^    "\*": deny$' "$f" || { echo "frontmatter lost the task deny-all glob"; return 1; }
  # Re-keyed (testsuite-05) from "same verbatim script contents at the same
  # fences": the OpenCode copy carries the same de-embedded shape as the
  # Claude copy -- the body is the prompt with the concrete resolved libdir
  # substituted (the render shares one substituted body across clients), and
  # the three scripts are referenced by their installed paths.
  d=$(new_tmp_dir)
  sed "s|__ANTZ_SCRIPTS_DIR__|$HOME_B/.config/antz/scripts|g" \
    "$SCRIPT_DIR/agents/prompts/orchestrator.prompt" > "$d/expected.body"
  strip_frontmatter "$f" > "$d/actual.body"
  if ! cmp -s "$d/expected.body" "$d/actual.body"; then
    echo "rendered OpenCode body is not the source prompt with the concrete resolved libdir substituted"
    diff "$d/expected.body" "$d/actual.body" | head -10
    return 1
  fi
  for script in antz-flow antz-probe antz-skills; do
    grep -qF "$HOME_B/.config/antz/scripts/$script.sh" "$f" || {
      echo "OpenCode body does not reference the installed $script.sh by path"; return 1
    }
  done
  return 0
}

# ---- renderinject-03 ---------------------------------------------------------

renderinject_03() {
  # Re-keyed (testsuite-05) from the embedded-script runtime contract to the
  # invocation contract: both clients' rendered bodies carry the flow/skills/
  # probe invocations with the concrete resolved libdir substituted (the
  # subcommand vocabulary and the skills argument shape survive verbatim),
  # and the temp-file instruction is gone -- what remains is its negation
  # ("never a temp-file copy").
  for client in .claude .config/opencode; do
    f="$HOME_B/$client/agents/antz-orchestrator.md"
    [ -f "$f" ] || { echo "missing rendered file: $f"; return 1; }
    s="$HOME_B/.config/antz/scripts"
    grep -qF "sh \"$s/antz-flow.sh\" discover" "$f" || {
      echo "$client body lost the flow discover invocation"; return 1
    }
    grep -qF "sh \"$s/antz-flow.sh\" ensure <slug>" "$f" || {
      echo "$client body lost the flow ensure invocation"; return 1
    }
    grep -qF "sh \"$s/antz-flow.sh\" state <slug> \"$s/antz-probe.sh\"" "$f" || {
      echo "$client body lost the flow state invocation naming the probe by path"; return 1
    }
    grep -qF "sh \"$s/antz-flow.sh\" release <slug>" "$f" || {
      echo "$client body lost the flow release invocation"; return 1
    }
    grep -qF "sh \"$s/antz-skills.sh\" <working-root> <match keyword>" "$f" || {
      echo "$client body lost the skills invocation line"; return 1
    }
    grep -qF 'never a temp-file copy' "$f" || {
      echo "$client body lost the never-a-temp-file wording"; return 1
    }
    if grep -qF 'Save the script below to a temp file' "$f"; then
      echo "$client body still carries the retired temp-file save instruction"; return 1
    fi
    # LOUD NOTE: the 'CHANGE_DIR=... sh "$probe"' pin retired with the
    # embed -- that line is inside the flow script now (byte-identical), and
    # its behavior is pinned by tests/antz-flow_test.sh (ensure-14) and the
    # probe suites; the rendered body names the probe by path above.
  done
  # The install set grew by design (change deembed-orchestration-scripts,
  # sub-spec 01): the four agent files plus /antz and /antz-set-model per
  # client (12) plus the four orchestration scripts installed as files to
  # the resolved libdir -- under these renders' masked environment that is
  # $HOME/.config/antz/scripts (the XDG fallback inside the temp home).
  for f in \
    .claude/agents/antz-specifier.md .config/opencode/agents/antz-specifier.md \
    .claude/agents/antz-coder.md .config/opencode/agents/antz-coder.md \
    .claude/agents/antz-verifier.md .config/opencode/agents/antz-verifier.md \
    .claude/agents/antz-orchestrator.md .config/opencode/agents/antz-orchestrator.md \
    .claude/commands/antz.md .config/opencode/commands/antz.md \
    .claude/commands/antz-set-model.md .config/opencode/commands/antz-set-model.md \
    .config/antz/scripts/antz-flow.sh .config/antz/scripts/antz-probe.sh \
    .config/antz/scripts/antz-skills.sh .config/antz/scripts/antz-set-model.sh; do
    [ -f "$HOME_B/$f" ] || { echo "missing installed file: $f"; return 1; }
  done
  extra=$(find "$HOME_B" -type f | wc -l)
  [ "$extra" -eq 16 ] || {
    echo "unexpected installed-file count: $extra (expected 16)"; return 1
  }
  # And (while the base is still distinct AND the prompt prose is unchanged
  # vs base -- see the header note) nothing anywhere differs at all; the
  # tree comparison is normalized era-neutrally on BOTH trees (norm_render's
  # dequote + version mask applied file-by-file to each side, testsuite-05
  # fixed the one-sided application) and with the /antz-set-model embedded-
  # script fence body masked on BOTH trees per the header's 04-setmodel note.
  # The non-orchestrator renders' identity is asserted separately in -05.
  if if_base_identity_active; then
    d=$(new_tmp_dir)
    cp -R "$HOME_A" "$d/oldnorm"
    cp -R "$HOME_B" "$d/newnorm"
    for t in oldnorm newnorm; do
      find "$d/$t" -type f | while IFS= read -r f; do
        dequote_description "$f" > "$f.dq" && mv "$f.dq" "$f"
      done
    done
    # Version-marker note applied: mask each rendered file's version=X.Y.Z
    # marker value on BOTH trees before the tree diff, same convention as
    # the mask_version comparisons in -01/-02/-05 -- a later legitimate
    # bump (this suite's header records it: 06-bump470 bumps VERSION to
    # 4.7.0) makes the base render embed 4.6.0 and the working render 4.7.0;
    # the pin asserts body identity, not version equality.
    for t in oldnorm newnorm; do
      find "$d/$t" -type f | while IFS= read -r f; do
        mask_version "$f" > "$f.vm" && mv "$f.vm" "$f"
      done
    done
    for f in .claude/commands/antz-set-model.md .config/opencode/commands/antz-set-model.md; do
      mask_set_model_script "$d/oldnorm/$f" > "$d/m.tmp" && mv "$d/m.tmp" "$d/oldnorm/$f"
      mask_set_model_script "$d/newnorm/$f" > "$d/m.tmp" && mv "$d/m.tmp" "$d/newnorm/$f"
    done
    diff -r "$d/oldnorm" "$d/newnorm" > "$d/treediff.txt" 2>&1 || {
      echo "installed tree drifted from the pre-change tree (modulo the 02-quoting description normalization and the 04-setmodel embedded-script masking)"
      head -10 "$d/treediff.txt"
      return 1
    }
  fi
  return 0
}

# ---- renderinject-04 ---------------------------------------------------------

fetch_failure_case() {
  # $1 = script name whose file is removed before rendering; the install must
  # fail loudly naming the file and write no agent body at all (sub-spec 01's
  # atomic fetch-abort: the scripts are read before any file is installed).
  missing="$1"
  src=$(new_tmp_dir)/src
  copy_render_inputs "$src"
  rm -f "$src/scripts/orchestration/$missing.sh"
  home=$(new_tmp_dir)/home
  log=$(new_tmp_dir)/render.log
  rc=0
  render_tree "$src" "$home" "$log" || rc=$?
  [ "$rc" -ne 0 ] || { echo "render unexpectedly succeeded with $missing.sh missing"; return 1; }
  grep -qF "scripts/orchestration/$missing.sh" "$log" || {
    echo "failure output does not name the missing file (log head: $(head -5 "$log"))"
    return 1
  }
  assert_no_embed_survivor "$home" || return 1
  [ ! -f "$home/.claude/agents/antz-orchestrator.md" ] || {
    echo "a Claude Code orchestrator body was written despite the missing script"; return 1
  }
  [ ! -f "$home/.config/opencode/agents/antz-orchestrator.md" ] || {
    echo "an OpenCode orchestrator body was written despite the missing script"; return 1
  }
  return 0
}

renderinject_04_flow()   { fetch_failure_case "antz-flow"; }
renderinject_04_probe()  { fetch_failure_case "antz-probe"; }
renderinject_04_skills() { fetch_failure_case "antz-skills"; }

renderinject_04_shared_fetch_path() {
  # Both source paths (local-checkout read and curl | sh fetch) route through
  # the one fetch_file helper. Re-keyed (testsuite-05) from the injection's
  # include-file fetch to the libdir install's script fetches: each of the
  # three orchestration scripts is read through fetch_file, and install.sh's
  # executable code carries a single curl invocation (inside fetch_file;
  # comment lines excluded).
  for script in antz-flow antz-probe antz-skills; do
    grep -qF "fetch_file \"scripts/orchestration/$script.sh\"" "$INSTALL_SH" || {
      echo "the libdir install does not fetch $script.sh through fetch_file"; return 1
    }
  done
  n=$(grep -v '^#' "$INSTALL_SH" | grep -c 'curl -fsSL')
  [ "$n" -eq 1 ] || {
    echo "expected exactly one executable curl invocation (inside fetch_file), got: $n"; return 1
  }
  return 0
}

# ---- renderinject-05 ---------------------------------------------------------

renderinject_05() {
  # Every rendered file except the two orchestrator copies and the two
  # /antz-set-model command copies is byte-identical to its pre-change
  # render -- gated per file on the sourced prompt's prose being unchanged
  # vs base (a later sub-spec's legitimate prose edit to a role's prompt
  # retires that role's byte-identity assertion with a loud note; the /antz
  # command has no prompt source and stays enforced) -- with the same
  # era-neutral normalization (norm_render: quoting + version mask on both
  # sides) as -01/-02/-03.
  # LOUD NOTE (testsuite-05): the /antz-set-model byte-identity masks retire
  # -- sub-spec 03 (setmodeldeembed) legitimately changed those command
  # bodies outright (embedded fence gone, installed-path invocation, client
  # first argument); the masked-fence comparison fitted the era where only
  # the fenced script's body could move. Those renders' contract is pinned
  # forever by tests/set-model-command_test.sh and
  # tests/setmodeldeembed_test.sh; here only the installed-path reference
  # survives as a re-keyed assertion.
  for f in \
    .claude/agents/antz-specifier.md .config/opencode/agents/antz-specifier.md \
    .claude/agents/antz-coder.md .config/opencode/agents/antz-coder.md \
    .claude/agents/antz-verifier.md .config/opencode/agents/antz-verifier.md \
    .claude/commands/antz.md .config/opencode/commands/antz.md; do
    [ -f "$HOME_B/$f" ] || { echo "missing installed file: $f"; return 1; }
    if [ "$BASE_DISTINCT" -eq 1 ]; then
      role=""
      case "$f" in
        */agents/antz-specifier.md) role=specifier ;;
        */agents/antz-coder.md) role=coder ;;
        */agents/antz-verifier.md) role=verifier ;;
      esac
      if [ -n "$role" ] && [ "$(role_prompt_prose_distinct "$role")" -eq 1 ]; then
        echo "  note: agents/prompts/$role.prompt prose changed vs the base (a later sub-spec's additive edit); the pre-change byte-identity assertion for its render is vacuously retired"
      else
        d=$(new_tmp_dir)
        norm_render "$HOME_B/$f" "$d/new.masked"
        norm_render "$HOME_A/$f" "$d/base.masked"
        cmp -s "$d/new.masked" "$d/base.masked" || {
          echo "non-orchestrator render drifted from the pre-change render (modulo the era-neutral quoting + version normalization): $f"
          return 1
        }
      fi
    fi
  done
  # Re-keyed set-model assertion: the command renders reference the installed
  # script by its resolved libdir path (placeholder substituted).
  for f in .claude/commands/antz-set-model.md .config/opencode/commands/antz-set-model.md; do
    grep -qF "$HOME_B/.config/antz/scripts/antz-set-model.sh" "$HOME_B/$f" || {
      echo "$f lost the installed antz-set-model.sh path reference"; return 1
    }
  done
  # Re-keyed (testsuite-05) from "only the orchestrator prompt carries
  # markers ... substitution keyed behaviorally": the injection machinery is
  # GONE. No prompt carries an include marker or a script-content (```sh)
  # fence, and install.sh carries no substitution machinery at all -- a
  # marker line anywhere in any body is inert verbatim text, so the old
  # keyed-substitution fixture re-keys to a marker-inertness fixture below.
  n=$(grep -c '# antz-include:' "$SCRIPT_DIR/agents/prompts/orchestrator.prompt")
  [ "$n" -eq 0 ] || { echo "orchestrator.prompt carries $n markers (expected 0)"; return 1; }
  n=$(grep -c '^   ```sh\|^```sh' "$SCRIPT_DIR/agents/prompts/orchestrator.prompt")
  [ "$n" -eq 0 ] || { echo "orchestrator.prompt carries $n script-content fences (expected 0)"; return 1; }
  for role in specifier coder verifier orchestrator; do
    [ "$(grep -c '# antz-include:' "$SCRIPT_DIR/agents/prompts/$role.prompt")" -eq 0 ] || {
      echo "agents/prompts/$role.prompt unexpectedly carries an include marker"; return 1
    }
  done
  for needle in inject_includes 'antz-include' '__ANTZ_INCLUDE'; do
    if grep -q "$needle" "$INSTALL_SH"; then
      echo "install.sh still carries injection machinery ($needle)"; return 1
    fi
  done
  # Marker inertness: a marker line appended to a NON-orchestrator prompt
  # renders verbatim (nothing substituted anything before; nothing does now).
  src=$(new_tmp_dir)/src
  copy_render_inputs "$src"
  printf '# antz-include: scripts/orchestration/antz-flow.sh\n' >> "$src/agents/prompts/coder.prompt"
  home=$(new_tmp_dir)/home
  log=$(new_tmp_dir)/render.log
  render_tree "$src" "$home" "$log" || { echo "inert-marker render failed: $(cat "$log")"; return 1; }
  grep -qF '# antz-include: scripts/orchestration/antz-flow.sh' "$home/.claude/agents/antz-coder.md" || {
    echo "a marker line in a non-orchestrator prompt was not rendered verbatim"
    return 1
  }
  assert_no_embed_survivor "$HOME_B" || return 1
  # --check report re-keyed (testsuite-05): sub-spec 01's legitimate
  # extension appends one artifact line per libdir script after the
  # per-client lines. The base report stays intact underneath: masked of
  # version values and of exactly the four appended script lines, the
  # working report must equal the base report; the four script lines must
  # name the libdir artifacts; and --check must still write nothing.
  if [ "$BASE_DISTINCT" -eq 1 ]; then
    d=$(new_tmp_dir)
    (cd "$BASE_TREE_DIR" && env -u XDG_CONFIG_HOME HOME="$d/home-ca" sh ./install.sh --check > "$d/check-a.log" 2>&1) || {
      echo "base --check failed"; return 1
    }
    (cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$d/home-cb" sh ./install.sh --check > "$d/check-b.log" 2>&1) || {
      echo "working-tree --check failed"; return 1
    }
    mask_check_version() { sed 's/antz [0-9][0-9.]*/antz VERSIONMASKED/g' "$1"; }
    mask_check_version "$d/check-a.log" > "$d/check-a.masked"
    mask_check_version "$d/check-b.log" > "$d/check-b.masked"
    n=$(grep -c '^antz-[a-z-]*\.sh: ' "$d/check-b.masked")
    [ "$n" -eq 4 ] || {
      echo "expected exactly 4 libdir-script lines in the working --check report, got: $n"; return 1
    }
    [ "$(grep -c '^antz-[a-z-]*\.sh: ' "$d/check-a.masked")" -eq 0 ] || {
      echo "the base --check report unexpectedly already names libdir scripts"; return 1
    }
    grep -v '^antz-[a-z-]*\.sh: ' "$d/check-b.masked" > "$d/check-b.noscripts"
    cmp -s "$d/check-a.masked" "$d/check-b.noscripts" || {
      echo "--check report drifted from the pre-change report beyond the four legitimately appended script lines"
      diff "$d/check-a.masked" "$d/check-b.noscripts" | head -5
      return 1
    }
    mkdir -p "$d/home-cb"
    before=$(ls -A "$d/home-cb" 2>/dev/null)
    (cd "$SCRIPT_DIR" && env -u XDG_CONFIG_HOME HOME="$d/home-cb" sh ./install.sh --check > "$d/check-b2.log" 2>&1) || {
      echo "working-tree --check (second run) failed"; return 1
    }
    [ "$before" = "$(ls -A "$d/home-cb" 2>/dev/null)" ] || {
      echo "--check wrote files under HOME"; return 1
    }
  fi
  return 0
}

# ---- renderinject-06 ---------------------------------------------------------

print_header_of() {
  # $1 = install.sh path; prints its header comment (everything before the
  # 'set -eu' line, exclusive).
  sed '/^set -eu$/q' "$1" | sed '$d'
}

renderinject_06() {
  d=$(new_tmp_dir)
  print_header_of "$INSTALL_SH" > "$d/header.txt"
  n=$(grep -c 'VERSION + CHANGELOG.md track changes to' "$d/header.txt")
  [ "$n" -eq 1 ] || { echo "expected exactly 1 tracked-set header line, got: $n"; return 1; }
  line=$(grep 'VERSION + CHANGELOG.md track changes to' "$d/header.txt")
  for token in 'agents/prompts/' 'agents/meta/' 'install.sh'; do
    case "$line" in
      *" $token"*) ;;
      *) echo "tracked-set header line does not name $token: $line"; return 1 ;;
    esac
  done
  if grep -qF 'track changes to agents/prompts/ and agents/meta/.' "$d/header.txt"; then
    echo "the stale two-item tracked-set sentence is still present"
    return 1
  fi
  # "No other header line changes" window: every header line except the
  # tracked-set one used to be pinned byte-identical to the base's. That
  # byte-identity window is retired by change hardening-installsh (sub-spec
  # 01-marker), this change's first header-editing sub-spec: its header
  # edits (the .bak policy statement and header completion in 01, the
  # ANTZ_REF usage docs and tagged-URL example in 03) are legitimate by
  # contract, so the window can no longer pin the header to the base.
  # Retired per the repo's loud-note convention (a note when the header has
  # in fact moved vs the base, like the other retirement gates -- never a
  # failure, never silence): the tracked-set sentence assertion above stays
  # enforced either way.
  if [ "$BASE_DISTINCT" -eq 1 ]; then
    print_header_of "$BASE_TREE_DIR/install.sh" > "$d/base-header.txt"
    grep -v 'VERSION + CHANGELOG.md track changes to' "$d/header.txt" > "$d/h.new"
    grep -v 'VERSION + CHANGELOG.md track changes to' "$d/base-header.txt" > "$d/h.base"
    if ! cmp -s "$d/h.new" "$d/h.base"; then
      echo "  note: install.sh's header comment changed vs the base; the header byte-identity window is vacuously retired by change hardening-installsh (01-marker/03-refpin's legitimate header edits), the tracked-set sentence assertion stays enforced"
    fi
  fi
  return 0
}

# ---- renderinject-07 ---------------------------------------------------------

branch_bullet() {
  grep '^- \*\*Branch-marked flow' "$1"
}

  probe_bullet_head() {
  # The probe gotcha bullet, up to (not including) the sentence that
  # legitimately differs between the two docs: everything before "It
  # deliberately stops short ...", i.e. the sourcing/convention statement.
  grep -E '^- `orchestrator\.prompt`' "$1" | sed 's/It deliberately.*$//'
}

renderinject_07() {
  for doc in "$SCRIPT_DIR/AGENTS.md" "$SCRIPT_DIR/CLAUDE.md"; do
    [ -f "$doc" ] || { echo "missing doc: $doc"; return 1; }
  done
  d=$(new_tmp_dir)
  # The two files state the gotcha bullets identically (byte-identical).
  branch_bullet "$SCRIPT_DIR/AGENTS.md" > "$d/b.agents"
  branch_bullet "$SCRIPT_DIR/CLAUDE.md" > "$d/b.claude"
  [ "$(grep -c '^- \*\*Branch-marked flow' "$SCRIPT_DIR/AGENTS.md")" -eq 1 ] || {
    echo "AGENTS.md: expected exactly 1 branch-marker gotcha bullet"; return 1
  }
  cmp -s "$d/b.agents" "$d/b.claude" || {
    echo "the branch-marker gotcha bullet differs between AGENTS.md and CLAUDE.md"
    diff "$d/b.agents" "$d/b.claude" | head -5
    return 1
  }
  probe_bullet_head "$SCRIPT_DIR/AGENTS.md" > "$d/p.agents"
  probe_bullet_head "$SCRIPT_DIR/CLAUDE.md" > "$d/p.claude"
  [ -s "$d/p.agents" ] || { echo "probe gotcha bullet not found in AGENTS.md"; return 1; }
  cmp -s "$d/p.agents" "$d/p.claude" || {
    echo "the probe gotcha bullet's sourcing statement differs between AGENTS.md and CLAUDE.md"
    diff "$d/p.agents" "$d/p.claude" | head -5
    return 1
  }
  # Content: source of truth named, the move to installed libdir files
  # stated, runtime wording re-keyed (testsuite-05) to sub-spec 04's
  # installed-library wording, nothing standalone; the stale injection and
  # temp-file sourcings are gone.
  for doc in "$SCRIPT_DIR/AGENTS.md" "$SCRIPT_DIR/CLAUDE.md"; do
    bb=$(branch_bullet "$doc")
    case "$bb" in
      *'scripts/orchestration/<name>.sh'*) ;;
      *) echo "$doc: branch-marker bullet does not name the scripts/orchestration/ source of truth"; return 1 ;;
    esac
    case "$bb" in
      *'installs these scripts as files to the resolved antz scripts libdir'*) ;;
      *) echo "$doc: branch-marker bullet does not state the install-to-libdir mechanics"; return 1 ;;
    esac
    case "$bb" in
      *'invokes them there by path'*) ;;
      *) echo "$doc: branch-marker bullet lost the invokes-them-by-path runtime wording"; return 1 ;;
    esac
    case "$bb" in
      *'instead of re-materializing any script into the rendered `antz-orchestrator` body or saving a temp file'*) ;;
      *) echo "$doc: branch-marker bullet lost the instead-of-re-materializing clause"; return 1 ;;
    esac
    case "$bb" in
      *'standalone CLI/hook/plugin'*) ;;
      *) echo "$doc: branch-marker bullet lost the nothing-standalone wording"; return 1 ;;
    esac
    case "$bb" in
      *'injects into the rendered `antz-orchestrator` body'*)
        echo "$doc: the stale install.sh-injection statement survives in the branch bullet"; return 1 ;;
    esac
    case "$bb" in
      *'sh <tempfile> ...'*)
        echo "$doc: the stale 'sh <tempfile> ...' runtime wording survives in the branch bullet"; return 1 ;;
    esac
    pb=$(probe_bullet_head "$doc")
    case "$pb" in
      *'scripts/orchestration/antz-probe.sh'*) ;;
      *) echo "$doc: probe bullet does not name scripts/orchestration/antz-probe.sh"; return 1 ;;
    esac
    case "$pb" in
      *'installed by `install.sh` as a file to the resolved antz scripts libdir'*) ;;
      *) echo "$doc: probe bullet does not state the installed-as-a-file sourcing"; return 1 ;;
    esac
    case "$pb" in
      *'runs it there by path'*) ;;
      *) echo "$doc: probe bullet lost the by-path runtime wording"; return 1 ;;
    esac
    case "$pb" in
      *'taking the probe'"'"'s path as its second argument'*) ;;
      *) echo "$doc: probe bullet lost the second-argument runtime wording"; return 1 ;;
    esac
    case "$pb" in
      *'no temp file and nothing re-materialized into the rendered `antz-orchestrator` body'*) ;;
      *) echo "$doc: probe bullet lost the no-temp-file negation"; return 1 ;;
    esac
    case "$pb" in
      *'saved to a temp file and run via `sh`'*)
        echo "$doc: the stale temp-file-run wording survives in the probe bullet"; return 1 ;;
    esac
    case "$pb" in
      *'rather than installed anywhere'*)
        echo "$doc: the stale rather-than-installed-anywhere wording survives in the probe bullet"; return 1 ;;
    esac
    case "$pb" in
      *'embeds a small POSIX `sh` probe script'*)
        echo "$doc: the stale 'orchestrator.prompt embeds ... probe script' sourcing survives"; return 1 ;;
    esac
  done
  return 0
}

# ---- run ---------------------------------------------------------------------

# testsuite-05 (change deembed-orchestration-scripts): pin the re-key itself.
# No retired injection helper is callable anymore (definition and call sites
# are gone; only loud-note comments name them), and every render/--check run
# in this suite masks the session's XDG_CONFIG_HOME so install.sh's libdir
# step resolves inside the temp home. The helper names are split below so
# this scan can never match its own lines.
testsuite_05_rekeyed_surface() {
  self="$SCRIPT_DIR/tests/renderinject_test.sh"
  for helper in 'reconstruct_expected_''body' 'assert_no_marker_''in_tree'; do
    n=$(grep -v '^[[:space:]]*#' "$self" | grep -c "$helper" || true)
    [ "$n" -eq 0 ] || {
      echo "the retired $helper still has $n non-comment mention(s)"; return 1
    }
  done
  # Hermeticity: both render entry points run masked (env -u XDG_CONFIG_HOME).
  n=$(grep -v '^[[:space:]]*#' "$self" | grep -c 'env -u XDG_CONFIG_HOME' || true)
  [ "$n" -ge 4 ] || {
    echo "expected at least 4 masked render/--check invocations, got: $n"; return 1
  }
  # The prompt surface itself: zero markers, zero script-content fences, and
  # the five installed-path invocation references.
  p="$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
  [ "$(grep -c '# antz-include:' "$p")" -eq 0 ] || {
    echo "orchestrator.prompt carries include markers"; return 1
  }
  [ "$(grep -c '```sh' "$p")" -eq 0 ] || {
    echo "orchestrator.prompt carries script-content fences"; return 1
  }
  for script in antz-flow antz-probe antz-skills; do
    grep -qF "__ANTZ_SCRIPTS_DIR__/$script.sh" "$p" || {
      echo "orchestrator.prompt lost the placeholder path reference to $script.sh"; return 1
    }
  done
  return 0
}

run_test "renderinject-01 Claude Code orchestrator render: the prompt with the concrete resolved libdir substituted, no marker or script-content fence survives" renderinject_01
run_test "renderinject-02 OpenCode orchestrator render: same de-embedded body with installed-path references, frontmatter shape unchanged" renderinject_02
run_test "renderinject-03 runtime contract is the invocation contract: path-based invocations in both renders, install set is 12 client files plus 4 libdir scripts" renderinject_03
run_test "renderinject-04 missing scripts/orchestration/antz-flow.sh fails the install loudly, nothing is written" renderinject_04_flow
run_test "renderinject-04 missing scripts/orchestration/antz-probe.sh fails the install loudly, nothing is written" renderinject_04_probe
run_test "renderinject-04 missing scripts/orchestration/antz-skills.sh fails the install loudly, nothing is written" renderinject_04_skills
run_test "renderinject-04 both source paths (local read, curl fetch) route through the one fetch_file helper" renderinject_04_shared_fetch_path
run_test "renderinject-05 injection machinery gone: other renders byte-identical, markers inert everywhere, --check = base report plus the 4 script lines" renderinject_05
run_test "renderinject-06 install.sh header comment names install.sh in the tracked set; header byte-identity window retired by hardening-installsh" renderinject_06
run_test "renderinject-07 AGENTS.md/CLAUDE.md gotcha bullets follow the move to installed libdir scripts, stated identically" renderinject_07
run_test "testsuite-05: the renderinject suite re-keyed -- retired injection helpers uncalled, renders hermetic, prompt surface invocation-only" testsuite_05_rekeyed_surface
run_test "ensure-20: the scripts_distinct helper detects edited/extra/missing injected scripts against fixture trees" ensure_20_helper_on_fixtures
run_test "ensure-20: the base-render identity gate retires (with a note) when an injected script differs, never double-failing with prose drift" ensure_20_gate_decision

# ---- e2e-only scenario: explicit SKIP stub -----------------------------------
# e2e-01 (spdd/changes/orchestrator-fast-path/07-e2e.feature) is the change's
# verifier-owned end-to-end QA suite: it drives ./install.sh --all against a
# real/temp HOME and judges the install at the user surface (installed
# markers, extracted-script behavior, the full install set) -- not this unit
# suite, whose installs run against isolated temp HOMEs. Explicit stub so
# the scenario id is accounted for (suite convention: see
# tests/versioning-rule_test.sh).
skip_test "e2e-01: a fresh ./install.sh --all renders both clients' antz-orchestrator with the three scripts byte-identical at their fences under the unchanged antz:generated version=4.3.0 marker, the extracted flow script's discover prints the same machine lines as the direct source run, and nothing is installed beyond the pre-change set" \
  "e2e-only: live install semantics, run by the verifier (07-e2e.feature)"

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
