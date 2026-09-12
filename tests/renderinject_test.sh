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
# isolated HOME $2, logging stdout+stderr to $3.
render_tree() {
  src="$1"; home="$2"; log="$3"
  mkdir -p "$home"
  (cd "$src" && HOME="$home" sh ./install.sh --all > "$log" 2>&1)
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

# Writes the orchestrator body that the injection contract requires to $1:
# the working tree's orchestrator.prompt with each "# antz-include: <relpath>"
# marker line replaced by the verbatim content of the named file, every
# non-empty line prefixed with the marker's own three-space fence indentation
# (blank lines stay empty, exactly as the embedded snippet rendered before).
# Shares the one pinned carve-out with install.sh (see the comment there): the
# antz-skills snippet's pre-existing under-fence-indent "  done" line renders
# verbatim. The base-render byte-identity cmp is the independent guard for
# that decision while the base tree is still distinct.
reconstruct_expected_body() {
  out="$1"
  : > "$out"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'# antz-include: '*)
        rel=${line##*'# antz-include: '}
        case "$rel" in
          */antz-skills.sh)
            sed -e "/./s/^/   /" -e 's/^     done$/  done/' "$SCRIPT_DIR/$rel" >> "$out"
            ;;
          *)
            sed "/./s/^/   /" "$SCRIPT_DIR/$rel" >> "$out"
            ;;
        esac
        ;;
      *)
        printf '%s\n' "$line" >> "$out"
        ;;
    esac
  done < "$SCRIPT_DIR/agents/prompts/orchestrator.prompt"
}

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

assert_no_marker_in_tree() {
  # $1 = HOME tree; fails when any installed file still carries a marker line.
  home="$1"
  hits=$(grep -rl '# antz-include:' "$home" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "marker line survived the render in: $hits"
    return 1
  fi
  return 0
}

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

renderinject_01() {
  f="$HOME_B/.claude/agents/antz-orchestrator.md"
  [ -f "$f" ] || { echo "missing rendered file: $f"; return 1; }
  assert_no_marker_in_tree "$HOME_B" || return 1
  # Byte-identity against the pre-change render (same version marker, masked)
  # -- gated per the header note on the prompt prose being unchanged vs base.
  if if_base_identity_active; then
    d=$(new_tmp_dir)
    mask_version "$f" > "$d/new.masked"
    mask_version "$HOME_A/.claude/agents/antz-orchestrator.md" > "$d/base.masked"
    if ! cmp -s "$d/new.masked" "$d/base.masked"; then
      echo "rendered Claude Code orchestrator body drifted from the pre-change render"
      diff "$d/base.masked" "$d/new.masked" | head -10
      return 1
    fi
  fi
  # The body must equal the contract's reconstruction: the prompt with each
  # marker line replaced by the verbatim, three-space-indented script content.
  d=$(new_tmp_dir)
  reconstruct_expected_body "$d/expected.body"
  strip_frontmatter "$f" > "$d/actual.body"
  if ! cmp -s "$d/expected.body" "$d/actual.body"; then
    echo "rendered body does not match the marker-substitution reconstruction"
    diff "$d/expected.body" "$d/actual.body" | head -10
    return 1
  fi
  # The probe fence keeps its ```sh opener at the fence's indentation.
  grep -q '^   ```sh$' "$f" || { echo "the probe fence lost its \`\`\`sh opener"; return 1; }
  # Oracle-free guard for the indent-prefixed-blank-line failure class: the
  # pre-change render (and the prompt) contain no whitespace-only lines, so
  # the injected script content must never grow one (blank fence lines stay
  # empty), and this holds with no base render needed (survives post-merge).
  ws=$(grep -cE '^[[:space:]]+$' "$f")
  [ "$ws" -eq 0 ] || { echo "rendered body has $ws whitespace-only line(s) (blank lines must stay empty)"; return 1; }
  # The skills snippet's pre-existing under-fence-indent glitch line renders
  # verbatim: exactly one two-space "  done" in the body (the flow fence's
  # loop closers sit at five spaces, the probe has none). A re-indent that
  # shifted the glitch line would drop this count to 0.
  n=$(grep -c '^  done$' "$f")
  [ "$n" -eq 1 ] || {
    echo "expected exactly 1 under-fence-indent '  done' glitch line, got: $n"
    return 1
  }
  return 0
}

# ---- renderinject-02 ---------------------------------------------------------

renderinject_02() {
  f="$HOME_B/.config/opencode/agents/antz-orchestrator.md"
  [ -f "$f" ] || { echo "missing rendered file: $f"; return 1; }
  assert_no_marker_in_tree "$HOME_B" || return 1
  # Byte-identity against the pre-change render -- same gate as -01.
  if if_base_identity_active; then
    d=$(new_tmp_dir)
    mask_version "$f" > "$d/new.masked"
    mask_version "$HOME_A/.config/opencode/agents/antz-orchestrator.md" > "$d/base.masked"
    if ! cmp -s "$d/new.masked" "$d/base.masked"; then
      echo "rendered OpenCode orchestrator body drifted from the pre-change render"
      diff "$d/base.masked" "$d/new.masked" | head -10
      return 1
    fi
  fi
  # Frontmatter keeps its pre-change shape: mode: primary, edit: deny, and the
  # deny-by-default task allowlist (only the body's script-fence lines differ
  # from the pre-change render, and only by their source).
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
  # Same three verbatim script contents at the same fences as the Claude copy:
  # each script's first line appears injected (three-space indented).
  for script in antz-flow antz-probe antz-skills; do
    first=$(sed -n '1p' "$SCRIPT_DIR/scripts/orchestration/$script.sh")
    grep -qF "   $first" "$f" || {
      echo "OpenCode body missing the injected start of $script.sh"; return 1
    }
  done
  return 0
}

# ---- renderinject-03 ---------------------------------------------------------

renderinject_03() {
  for client in .claude .config/opencode; do
    f="$HOME_B/$client/agents/antz-orchestrator.md"
    [ -f "$f" ] || { echo "missing rendered file: $f"; return 1; }
    # The runtime contract is untouched: temp file + sh, with the flow's
    # subcommand vocabulary, the skills invocation shape, and the probe run
    # by the flow's state subcommand with CHANGE_DIR at the change directory.
    grep -qF 'sh <tempfile> discover | ensure <slug> | state <slug> <probe-path> | release <slug>' "$f" || {
      echo "$client body lost the flow subcommand line"; return 1
    }
    grep -qF 'sh <tempfile> <working-root> <match keyword>' "$f" || {
      echo "$client body lost the skills invocation line"; return 1
    }
    grep -qF 'CHANGE_DIR="$root/spdd/changes/$slug" sh "$probe"' "$f" || {
      echo "$client body lost the probe-run line (CHANGE_DIR at the change directory)"; return 1
    }
    grep -qF 'temp file' "$f" || { echo "$client body lost the temp-file instruction"; return 1; }
  done
  # The install writes no file beyond its pre-change set: exactly the four
  # agent files plus /antz and /antz-set-model per client.
  for f in \
    .claude/agents/antz-specifier.md .config/opencode/agents/antz-specifier.md \
    .claude/agents/antz-coder.md .config/opencode/agents/antz-coder.md \
    .claude/agents/antz-verifier.md .config/opencode/agents/antz-verifier.md \
    .claude/agents/antz-orchestrator.md .config/opencode/agents/antz-orchestrator.md \
    .claude/commands/antz.md .config/opencode/commands/antz.md \
    .claude/commands/antz-set-model.md .config/opencode/commands/antz-set-model.md; do
    [ -f "$HOME_B/$f" ] || { echo "missing installed file: $f"; return 1; }
  done
  extra=$(find "$HOME_B" -type f | wc -l)
  [ "$extra" -eq 12 ] || {
    echo "unexpected installed-file count: $extra (expected 12)"; return 1
  }
  # And (while the base is still distinct AND the prompt prose is unchanged
  # vs base -- see the header note) nothing anywhere differs at all; the
  # non-orchestrator renders' identity is asserted separately in -05.
  if if_base_identity_active; then
    d=$(new_tmp_dir)
    diff -r "$HOME_A" "$HOME_B" > "$d/treediff.txt" 2>&1 || {
      echo "installed tree drifted from the pre-change tree"
      head -10 "$d/treediff.txt"
      return 1
    }
  fi
  return 0
}

# ---- renderinject-04 ---------------------------------------------------------

fetch_failure_case() {
  # $1 = script name whose file is removed before rendering; the render must
  # fail loudly naming the file, writing no orchestrator body, and leaving no
  # marker fallback anywhere.
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
  assert_no_marker_in_tree "$home" || return 1
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
  # the one fetch_file helper: the injection fetches include files with it,
  # and install.sh's executable code carries a single curl invocation (inside
  # fetch_file; comment lines excluded).
  grep -qF 'fetch_file "$rel"' "$INSTALL_SH" || {
    echo "the injection does not fetch include files through fetch_file"; return 1
  }
  n=$(grep -v '^#' "$INSTALL_SH" | grep -c 'curl -fsSL')
  [ "$n" -eq 1 ] || {
    echo "expected exactly one executable curl invocation (inside fetch_file), got: $n"; return 1
  }
  return 0
}

# ---- renderinject-05 ---------------------------------------------------------

renderinject_05() {
  # Every rendered file except the two orchestrator copies is byte-identical
  # to its pre-change render (same version marker) -- gated per file on the
  # sourced prompt's prose being unchanged vs base (a later sub-spec's
  # legitimate prose edit to a role's prompt retires that role's byte-
  # identity assertion with a loud note; commands have no prompt source and
  # stay enforced).
  for f in \
    .claude/agents/antz-specifier.md .config/opencode/agents/antz-specifier.md \
    .claude/agents/antz-coder.md .config/opencode/agents/antz-coder.md \
    .claude/agents/antz-verifier.md .config/opencode/agents/antz-verifier.md \
    .claude/commands/antz.md .config/opencode/commands/antz.md \
    .claude/commands/antz-set-model.md .config/opencode/commands/antz-set-model.md; do
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
        mask_version "$HOME_B/$f" > "$d/new.masked"
        mask_version "$HOME_A/$f" > "$d/base.masked"
        cmp -s "$d/new.masked" "$d/base.masked" || {
          echo "non-orchestrator render drifted from the pre-change render: $f"
          return 1
        }
      fi
    fi
  done
  # Only the orchestrator prompt carries markers ...
  n=$(grep -c '# antz-include:' "$SCRIPT_DIR/agents/prompts/orchestrator.prompt")
  [ "$n" -eq 3 ] || { echo "orchestrator.prompt carries $n markers (expected 3)"; return 1; }
  for role in specifier coder verifier; do
    [ "$(grep -c '# antz-include:' "$SCRIPT_DIR/agents/prompts/$role.prompt")" -eq 0 ] || {
      echo "agents/prompts/$role.prompt unexpectedly carries an include marker"; return 1
    }
  done
  # ... and substitution is keyed behaviorally: a marker appended to a
  # NON-orchestrator prompt is rendered verbatim, never substituted.
  src=$(new_tmp_dir)/src
  copy_render_inputs "$src"
  printf '# antz-include: scripts/orchestration/antz-flow.sh\n' >> "$src/agents/prompts/coder.prompt"
  home=$(new_tmp_dir)/home
  log=$(new_tmp_dir)/render.log
  render_tree "$src" "$home" "$log" || { echo "keyed render failed: $(cat "$log")"; return 1; }
  grep -qF '# antz-include: scripts/orchestration/antz-flow.sh' "$home/.claude/agents/antz-coder.md" || {
    echo "a non-orchestrator prompt's marker line was not rendered verbatim (substitution leaked outside the orchestrator)"
    return 1
  }
  # --check adds no new report line: stdout identical between base and working
  # tree, and --check writes nothing. The comparison masks the reported antz
  # version value in both logs: change 06-closingblock legitimately bumps
  # VERSION (4.2.1 -> 4.3.0), so --check's reported version legitimately
  # differs -- the pin asserts report shape (no new/removed/reordered lines),
  # not version equality, same convention as the rendered-file mask_version
  # comparisons above.
  if [ "$BASE_DISTINCT" -eq 1 ]; then
    d=$(new_tmp_dir)
    (cd "$BASE_TREE_DIR" && HOME="$d/home-ca" sh ./install.sh --check > "$d/check-a.log" 2>&1) || {
      echo "base --check failed"; return 1
    }
    (cd "$SCRIPT_DIR" && HOME="$d/home-cb" sh ./install.sh --check > "$d/check-b.log" 2>&1) || {
      echo "working-tree --check failed"; return 1
    }
    mask_check_version() { sed 's/antz [0-9][0-9.]*/antz VERSIONMASKED/g' "$1"; }
    mask_check_version "$d/check-a.log" > "$d/check-a.masked"
    mask_check_version "$d/check-b.log" > "$d/check-b.masked"
    cmp -s "$d/check-a.masked" "$d/check-b.masked" || {
      echo "--check report drifted from the pre-change report (beyond the masked version value)"
      diff "$d/check-a.masked" "$d/check-b.masked" | head -5
      return 1
    }
    mkdir -p "$d/home-cb"
    before=$(ls -A "$d/home-cb")
    (cd "$SCRIPT_DIR" && HOME="$d/home-cb" sh ./install.sh --check > "$d/check-b2.log" 2>&1) || {
      echo "working-tree --check (second run) failed"; return 1
    }
    [ "$before" = "$(ls -A "$d/home-cb")" ] || {
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
  # No other header line changes meaning: every header line except the
  # tracked-set one is byte-identical to the base's.
  if [ "$BASE_DISTINCT" -eq 1 ]; then
    print_header_of "$BASE_TREE_DIR/install.sh" > "$d/base-header.txt"
    grep -v 'VERSION + CHANGELOG.md track changes to' "$d/header.txt" > "$d/h.new"
    grep -v 'VERSION + CHANGELOG.md track changes to' "$d/base-header.txt" > "$d/h.base"
    cmp -s "$d/h.new" "$d/h.base" || {
      echo "a header line other than the tracked-set sentence changed"
      diff "$d/h.base" "$d/h.new" | head -10
      return 1
    }
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
  # Content: source of truth named, injection stated, runtime wording kept,
  # nothing standalone; the stale "embedded" sourcing is gone.
  for doc in "$SCRIPT_DIR/AGENTS.md" "$SCRIPT_DIR/CLAUDE.md"; do
    bb=$(branch_bullet "$doc")
    case "$bb" in
      *'scripts/orchestration/antz-flow.sh'*) ;;
      *) echo "$doc: branch-marker bullet does not name scripts/orchestration/antz-flow.sh"; return 1 ;;
    esac
    case "$bb" in
      *'injects into the rendered `antz-orchestrator` body for both clients'*) ;;
      *) echo "$doc: branch-marker bullet does not state the install.sh injection into the rendered body for both clients"; return 1 ;;
    esac
    case "$bb" in
      *'sh <tempfile> ...'*) ;;
      *) echo "$doc: branch-marker bullet lost the runtime wording (sh <tempfile> ...)"; return 1 ;;
    esac
    case "$bb" in
      *'standalone CLI/hook/plugin'*) ;;
      *) echo "$doc: branch-marker bullet lost the nothing-standalone wording"; return 1 ;;
    esac
    case "$bb" in
      *"the orchestrator's embedded \`antz-flow.sh\`"*)
        echo "$doc: the stale 'embedded antz-flow.sh' sourcing survives"; return 1 ;;
    esac
    pb=$(probe_bullet_head "$doc")
    case "$pb" in
      *'scripts/orchestration/antz-probe.sh'*) ;;
      *) echo "$doc: probe bullet does not name scripts/orchestration/antz-probe.sh"; return 1 ;;
    esac
    case "$pb" in
      *'injects into the rendered `antz-orchestrator` body for both clients'*) ;;
      *) echo "$doc: probe bullet does not state the install.sh injection into the rendered body for both clients"; return 1 ;;
    esac
    case "$pb" in
      *'saved to a temp file and run via `sh`'*) ;;
      *) echo "$doc: probe bullet lost the runtime wording (saved to a temp file and run via sh)"; return 1 ;;
    esac
    case "$pb" in
      *'rather than installed anywhere'*) ;;
      *) echo "$doc: probe bullet lost the rather-than-installed-anywhere wording"; return 1 ;;
    esac
    case "$pb" in
      *'embeds a small POSIX `sh` probe script'*)
        echo "$doc: the stale 'orchestrator.prompt embeds ... probe script' sourcing survives"; return 1 ;;
    esac
  done
  return 0
}

# ---- run ---------------------------------------------------------------------

run_test "renderinject-01 Claude Code orchestrator render: three scripts verbatim at their fences, byte-identical to the pre-change render, no marker survives" renderinject_01
run_test "renderinject-02 OpenCode orchestrator render: same injected content, frontmatter shape unchanged" renderinject_02
run_test "renderinject-03 runtime contract unchanged: temp file + sh wording, no file beyond the pre-change install set" renderinject_03
run_test "renderinject-04 missing scripts/orchestration/antz-flow.sh fails the render loudly, no marker fallback" renderinject_04_flow
run_test "renderinject-04 missing scripts/orchestration/antz-probe.sh fails the render loudly, no marker fallback" renderinject_04_probe
run_test "renderinject-04 missing scripts/orchestration/antz-skills.sh fails the render loudly, no marker fallback" renderinject_04_skills
run_test "renderinject-04 both source paths (local read, curl fetch) route through the one fetch_file helper" renderinject_04_shared_fetch_path
run_test "renderinject-05 injection keyed to the orchestrator only: other renders byte-identical, markers substituted nowhere else, --check unchanged" renderinject_05
run_test "renderinject-06 install.sh header comment names install.sh in the tracked set; no other header line changes" renderinject_06
run_test "renderinject-07 AGENTS.md/CLAUDE.md gotcha bullets follow the move to scripts/orchestration/, stated identically" renderinject_07
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
