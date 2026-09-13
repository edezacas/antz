#!/usr/bin/env bash
# Unit tests for install.sh's quoted description rendering, covering every
# scenario in spdd/changes/hardening-installsh/02-quoting.feature
# (quoting-01..05). The change: every rendered `description:` value is a
# double-quoted single-line YAML scalar at all three render sites
# (render_claude, render_opencode, render_set_model_command's short_desc),
# with embedded `"` and `\` escaped per YAML double-quoted-scalar rules and
# the escaping value-preserving (unescaping reproduces the source byte for
# byte). The /antz command renderers (render_claude_command /
# render_opencode_command) stay unquoted -- out of the sub-spec's scope.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/skills-activation-render_test.sh. Run directly:
#   ./tests/description-quoting_test.sh
#
# Each reported test name embeds its scenario id (quoting-01..05) from the
# feature file above, so a failure maps straight back to the scenario it
# covers. Every test renders through install.sh's real --all path against
# isolated temp HOMEs, never the real ~/.claude or ~/.config/opencode.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
SELF_TEST="$(basename -- "$0")"

pass_count=0
fail_count=0
skip_count=0

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

# ---- fixtures ---------------------------------------------------------------

# stage_checkout <dest>: a staged checkout of the render inputs (install.sh,
# agents/, scripts/orchestration/, VERSION, CHANGELOG.md) copied from the
# working tree, so `sh <dest>/install.sh --all` renders from the staged tree
# and mutations never touch the real checkout.
stage_checkout() {
  dest="$1"
  mkdir -p "$dest"
  cp "$SCRIPT_DIR/install.sh" "$dest/install.sh"
  cp "$SCRIPT_DIR/VERSION" "$dest/VERSION"
  cp "$SCRIPT_DIR/CHANGELOG.md" "$dest/CHANGELOG.md"
  mkdir -p "$dest/agents/prompts" "$dest/agents/meta" "$dest/scripts/orchestration"
  cp "$SCRIPT_DIR"/agents/prompts/*.prompt "$dest/agents/prompts/"
  cp "$SCRIPT_DIR"/agents/meta/*.yaml "$dest/agents/meta/"
  cp "$SCRIPT_DIR"/scripts/orchestration/*.sh "$dest/scripts/orchestration/"
}

# render_all <home> <tree>: full --all render into the isolated HOME, logs to
# the caller's file $3.
render_all() {
  home="$1"; tree="$2"; log="$3"
  mkdir -p "$home"
  (cd "$tree" && HOME="$home" sh ./install.sh --all > "$log" 2>&1)
}

# agent_md <home> <client> <role>: rendered agent file path.
agent_md() {
  case "$2" in
    claude) printf '%s/.claude/agents/antz-%s.md' "$1" "$3" ;;
    opencode) printf '%s/.config/opencode/agents/antz-%s.md' "$1" "$3" ;;
  esac
}

# set_model_md <home> <client>: rendered /antz-set-model command file path.
set_model_md() {
  case "$2" in
    claude) printf '%s/.claude/commands/antz-set-model.md' "$1" ;;
    opencode) printf '%s/.config/opencode/commands/antz-set-model.md' "$1" ;;
  esac
}

# desc_line <file>: the file's first `description:` line (always its
# frontmatter's -- the render puts description above any body text).
desc_line() {
  grep -m1 '^description: ' "$1"
}

# meta_desc <role>: the source description in the working tree's meta file.
meta_desc() {
  sed -n 's/^description: //p' "$SCRIPT_DIR/agents/meta/$1.yaml" | head -n1
}

# unquote_desc_line <line>: the raw value inside a rendered
# `description: "<escaped>"` line, with the outer quotes stripped and the
# YAML double-quoted-scalar escapes undone (`\"` -> `"`, `\\` -> `\`,
# left-to-right). Independent of install.sh's sed-based quoting, so the pair
# cannot agree on a wrong transform. Prints nothing (rc 1 via caller check)
# for a line that is not a quoted scalar.
unquote_desc_line() {
  DESC_LINE="$1" awk '
    BEGIN { line = ENVIRON["DESC_LINE"] }
    END {
      if (line !~ /^description: "/) exit 1
      v = substr(line, length("description: ") + 2)
      if (substr(v, length(v), 1) != "\"") exit 1
      v = substr(v, 1, length(v) - 1)
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
      print out
    }
  '
}

# expected_short_desc <client>: the hardcoded short_desc source text from
# install.sh's own render_set_model_command case branch (evaluated from the
# assignment line, so the test can never drift from the source).
expected_short_desc() {
  line=$(awk -v want="$1" '
    /^render_set_model_command\(\) \{/ { inf = 1; next }
    inf && $0 ~ /^\}/ { inf = 0 }
    inf {
      t = $0
      sub(/^[ \t]+/, "", t)
      if (t == want ")") { br = 1; next }
      if (br && t ~ /^short_desc=/) { print t; exit }
    }
  ' "$INSTALL_SH")
  [ -n "$line" ] || { echo "  no short_desc assignment for $1 found in install.sh"; return 1; }
  ( eval "$line"; printf '%s' "$short_desc" )
}

# WORK render: the real tree, rendered once for quoting-01/02/04.
work_root=$(new_tmp_dir)
WORK_HOME="$work_root/home"
if ! render_all "$WORK_HOME" "$SCRIPT_DIR" "$work_root/render.log"; then
  echo "FATAL: working-tree render failed:"
  cat "$work_root/render.log"
  exit 1
fi

# =============================================================================
# quoting-01: the four role agents' rendered frontmatter quotes the
# description value, on both clients; the quoted value is the meta file's
# description, byte-preserved inside the quotes.
# =============================================================================
quoting_01() {
  ok=0
  for role in specifier coder verifier orchestrator; do
    raw=$(meta_desc "$role")
    for client in claude opencode; do
      f=$(agent_md "$WORK_HOME" "$client" "$role")
      [ -f "$f" ] || { echo "  missing rendered file: $f"; ok=1; continue; }
      line=$(desc_line "$f")
      # starts with `description: "` and ends with `"`, nothing after it
      case "$line" in
        'description: "'*'"') ;;
        *) echo "  $client/$role description line is not a quoted scalar: $line"; ok=1 ;;
      esac
      # value-preserving inside the quotes (no escape chars in the real
      # metas, so this is also the byte-for-byte between-the-quotes check)
      got=$(unquote_desc_line "$line") \
        || { echo "  $client/$role line cannot be unquoted: $line"; ok=1; continue; }
      [ "$got" = "$raw" ] \
        || { echo "  $client/$role unquoted value differs from agents/meta/$role.yaml: got [$got] want [$raw]"; ok=1; }
    done
  done
  return $ok
}

# =============================================================================
# quoting-02: the /antz-set-model command's rendered frontmatter quotes its
# description too (render_set_model_command's short_desc -- the third site).
# =============================================================================
quoting_02() {
  ok=0
  for client in claude opencode; do
    f=$(set_model_md "$WORK_HOME" "$client")
    [ -f "$f" ] || { echo "  missing rendered file: $f"; ok=1; continue; }
    line=$(desc_line "$f")
    case "$line" in
      'description: "'*'"') ;;
      *) echo "  $client antz-set-model description line is not a quoted scalar: $line"; ok=1 ;;
    esac
  done
  return $ok
}

# =============================================================================
# quoting-03 (Scenario Outline): real YAML quoting, not just wrapping -- an
# embedded `"` or `\` in the source is escaped, so the rendered line stays a
# valid single-line scalar. One test per Examples row; each row is staged
# into BOTH meta descriptions (render_claude/render_opencode) and both
# short_desc assignments (render_set_model_command), pinning all three
# quoting sites with the same raw/rendered pair.
# =============================================================================
quoting_03() {
  raw="$1"; rendered="$2"
  # guard: the staging helpers rely on the sample values below
  case "$raw" in *\'*) echo "  fixture limitation: raw contains a single quote"; return 1 ;; esac
  root=$(new_tmp_dir)
  tree="$root/tree"
  stage_checkout "$tree"
  # stage the raw into every meta description (single-line YAML, no sed on
  # the value: the file is rewritten around it)
  for role in specifier coder verifier orchestrator; do
    printf 'name: antz-%s\ndescription: %s\naccess: readwrite\n' "$role" "$raw" \
      > "$tree/agents/meta/$role.yaml"
  done
  # stage the raw into both hardcoded short_desc assignments (awk via the
  # environment: -v would eat backslashes)
  STAGE_RAW="$raw" awk '
    BEGIN { q = sprintf("%c", 39) }
    /^[ \t]*short_desc=/ { print "      short_desc=" q ENVIRON["STAGE_RAW"] q; next }
    { print }
  ' "$tree/install.sh" > "$root/install.sh" && mv "$root/install.sh" "$tree/install.sh"
  home="$root/home"
  render_all "$home" "$tree" "$root/render.log" \
    || { echo "  staged render failed:"; cat "$root/render.log"; return 1; }
  ok=0
  wantline="description: $rendered"
  for client in claude opencode; do
    for role in specifier coder verifier orchestrator; do
      line=$(desc_line "$(agent_md "$home" "$client" "$role")")
      [ "$line" = "$wantline" ] \
        || { echo "  $client/$role agent render: got [$line] want [$wantline]"; ok=1; }
    done
    line=$(desc_line "$(set_model_md "$home" "$client")")
    [ "$line" = "$wantline" ] \
      || { echo "  $client antz-set-model render: got [$line] want [$wantline]"; ok=1; }
  done
  return $ok
}

# =============================================================================
# quoting-04: quoting is value-preserving -- for every rendered description
# line (all agents, both /antz-set-model copies), stripping the outer quotes
# and YAML-unescape yields exactly the source description text. Also a
# staged round-trip with an escape-heavy and trailing-backslash value.
# =============================================================================
quoting_04() {
  ok=0
  for role in specifier coder verifier orchestrator; do
    raw=$(meta_desc "$role")
    for client in claude opencode; do
      line=$(desc_line "$(agent_md "$WORK_HOME" "$client" "$role")")
      got=$(unquote_desc_line "$line") \
        || { echo "  $client/$role: line is not a quoted scalar: $line"; ok=1; continue; }
      [ "$got" = "$raw" ] \
        || { echo "  $client/$role: unquote(render) != agents/meta/$role.yaml"; ok=1; }
    done
  done
  for client in claude opencode; do
    want=$(expected_short_desc "$client") || return 1
    line=$(desc_line "$(set_model_md "$WORK_HOME" "$client")")
    got=$(unquote_desc_line "$line") \
      || { echo "  $client antz-set-model: line is not a quoted scalar: $line"; ok=1; continue; }
    [ "$got" = "$want" ] \
      || { echo "  $client antz-set-model: unquote(render) != install.sh's short_desc source"; ok=1; }
  done
  # staged round-trip: quotes, backslashes (incl. a trailing one), an
  # apostrophe, and colon+space -- unescape must reproduce it byte-for-byte
  raw='it'"'"'s "x" \y\ :d'
  root=$(new_tmp_dir)
  tree="$root/tree"
  stage_checkout "$tree"
  printf 'name: antz-specifier\ndescription: %s\naccess: readwrite\n' "$raw" \
    > "$tree/agents/meta/specifier.yaml"
  home="$root/home"
  render_all "$home" "$tree" "$root/render.log" \
    || { echo "  staged round-trip render failed:"; cat "$root/render.log"; return 1; }
  for client in claude opencode; do
    line=$(desc_line "$(agent_md "$home" "$client" specifier)")
    got=$(unquote_desc_line "$line") \
      || { echo "  round-trip $client: line is not a quoted scalar: $line"; ok=1; continue; }
    [ "$got" = "$raw" ] \
      || { echo "  round-trip $client: got [$got] want [$raw]"; ok=1; }
  done
  return $ok
}

# =============================================================================
# quoting-05: the pre-change rendered byte-identity suites were updated
# within this change (loud notes), and the full unit suite passes with the
# quoted renders. Static half: the re-scope notes and kept structural
# assertions are present where the sub-spec names them. Dynamic half: run
# every other tests/*_test.sh and require zero failures.
# =============================================================================
quoting_05() {
  ok=0
  ri="$SCRIPT_DIR/tests/renderinject_test.sh"
  sa="$SCRIPT_DIR/tests/skills-activation-render_test.sh"
  # renderinject-01/02/05 (and -03's tree diff): re-scoped with a loud note,
  # quoting-aware via dequote_description normalization...
  grep -qF 'hardening-installsh (sub-spec 02' "$ri" \
    || { echo "  renderinject_test.sh carries no loud 02-quoting re-scope note"; ok=1; }
  grep -q 'dequote_description' "$ri" \
    || { echo "  renderinject_test.sh's byte-identity is not re-scoped quoting-aware (dequote_description missing)"; ok=1; }
  # ... and their structural assertions stay enforced:
  grep -qF 'reconstruct_expected_body "$d/expected.body"' "$ri" \
    || { echo "  renderinject's marker-substitution reconstruction assertion is gone"; ok=1; }
  grep -qF "frontmatter lost 'mode: primary'" "$ri" \
    || { echo "  renderinject-02's frontmatter-shape assertion is gone"; ok=1; }
  # skills-activation-render render-03/render-04-scoping: re-scoped to the
  # current renderer (their pre-change baseline is a controlled mutation of
  # the working install.sh, so both sides carry the quoting -- noted for
  # this change; no stale pre-quoting byte-identity).
  grep -qF '02-quoting' "$sa" \
    || { echo "  skills-activation-render_test.sh carries no 02-quoting re-scope note"; ok=1; }
  # Dynamic half: the repo's full unit suite runs clean (excluding this
  # file -- self-recursion; nothing else in tests/ glob-runs the suite).
  for t in "$SCRIPT_DIR"/tests/*_test.sh; do
    [ "$(basename -- "$t")" = "$SELF_TEST" ] && continue
    out=$(sh "$t" 2>&1) || {
      echo "  suite failed: ${t#"$SCRIPT_DIR"/}"
      printf '%s\n' "$out" | grep -E '^(FAIL|FATAL)' | head -5
      ok=1
    }
  done
  return $ok
}

# ---- run --------------------------------------------------------------------

run_test "quoting-01: all four agents' rendered descriptions are double-quoted YAML scalars on both clients, value byte-preserved from agents/meta" quoting_01
run_test "quoting-02: both /antz-set-model renders carry a double-quoted description line (third quoting site)" quoting_02
run_test "quoting-03 (Says \"hi\"): embedded quotes escape to \" on all three sites, rendered line is exactly description: \"Says \\\"hi\\\"\"" quoting_03 'Says "hi"' '"Says \"hi\""'
run_test "quoting-03 (back\\slash): embedded backslash escapes to \\\\ on all three sites, rendered line is exactly description: \"back\\\\slash\"" quoting_03 'back\slash' '"back\\slash"'
run_test "quoting-03 (a \"b\" \\ c): mixed quotes+backslash escape per YAML rules on all three sites, rendered line is exactly description: \"a \\\"b\\\" \\\\ c\"" quoting_03 'a "b" \ c' '"a \"b\" \\ c"'
run_test "quoting-04: unquoting every rendered description line reproduces its source byte-for-byte (all agents, both set-model renders, escape-heavy round-trip)" quoting_04
run_test "quoting-05: renderinject-01/02/05 byte-identity re-scoped quoting-aware with loud notes (structural assertions kept), render-03/render-04-scoping re-scoped to the current renderer, full unit suite green" quoting_05

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
