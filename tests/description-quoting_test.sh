#!/usr/bin/env bash
# Unit tests for install.sh's quoted description rendering, covering every
# scenario in spdd/changes/hardening-installsh/02-quoting.feature
# (quoting-01..04; quoting-05 removed whole by change optimize-test-suite,
# sub-spec 04-crosssuites). The change: every rendered `description:` value is a
# double-quoted single-line YAML scalar at all three render sites
# (render_claude, render_opencode, render_set_model_command's short_desc),
# with embedded `"` and `\` escaped per YAML double-quoted-scalar rules and
# the escaping value-preserving (unescaping reproduces the source byte for
# byte). The /antz command renderers (render_claude_command /
# render_opencode_command) stay unquoted -- out of the sub-spec's scope.
#
# Self-contained bash test area (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/skills-activation-render_test.sh. Run directly:
#   sh tests/description-quoting_test.sh
#
# Each reported test name embeds its scenario id (quoting-01..04,
# crosssuites-01) from the feature files above, so a failure maps straight
# back to the scenario it covers. Every test renders through the harness
# library's render-once helper against isolated temp HOMEs, never the real
# ~/.claude or ~/.config/opencode.
#
# Decoupled by change optimize-test-suite (sub-spec 04-crosssuites): the
# quoting-05 site glob-ran every other suite and grepped the renderinject
# and skills-activation-render suite sources to vouch "the whole suite is
# green" -- that verdict belongs to the documented runner tests/run_all.sh,
# not to a suite. The decoupling law: no suite executes another suite and no
# suite asserts another test file's source content or output (a suite may
# read its own file); crosssuites-01 below pins this suite's decoupled shape.
#
# The shared harness library provides the plumbing helpers (run_test,
# skip_test, temp bookkeeping, cleanup, stage_checkout, and the install
# renderers); this suite defines none of them itself.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

# This suite's own source with comment lines stripped: the crosssuites-01
# self-check scans non-comment lines only (the hygiene scan convention). The
# needles inside that test are quote-split so the scan can never match the
# checking code itself.
QUOTING_TEST_SELF="$SCRIPT_DIR/tests/description-quoting_test.sh"
QUOTING_NONCOMMENTS="$(new_tmp_dir)/noncomments"
grep -v '^[[:space:]]*#' "$QUOTING_TEST_SELF" > "$QUOTING_NONCOMMENTS"

# ---- fixtures ---------------------------------------------------------------

# The staged-checkout copy is the harness library's stage_checkout: install.sh,
# VERSION, CHANGELOG.md, agents/, scripts/orchestration/ from the working
# tree, so `render_tree` renders from the staged tree and mutations never
# touch the real checkout.

# agent_md <home> <client> <role>: rendered agent file path.
agent_md() {
  case "$2" in
    claude) printf '%s/.claude/agents/antz-%s.md' "$1" "$3" ;;
    opencode) printf '%s/.config/opencode/agents/antz-%s.md' "$1" "$3" ;;
    pi) printf '%s/.pi/agent/agents/antz-%s.md' "$1" "$3" ;;
  esac
}

# set_model_md <home> <client>: rendered /antz-set-model command file path.
set_model_md() {
  case "$2" in
    claude) printf '%s/.claude/commands/antz-set-model.md' "$1" ;;
    opencode) printf '%s/.config/opencode/commands/antz-set-model.md' "$1" ;;
    pi) printf '%s/.pi/agent/prompts/antz-set-model.md' "$1" ;;
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

# WORK render: the working tree staged and rendered once through the harness
# library for quoting-01/02/04 (the library's render cache keeps it hermetic
# and single).
WORK_ROOT=$(new_tmp_dir)
WORK_TREE="$WORK_ROOT/tree"
stage_checkout "$WORK_TREE"
if ! WORK_HOME=$(render_tree "$WORK_TREE"); then
  echo "FATAL: working-tree staged render failed"
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
    for client in claude opencode pi; do
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
  for client in claude opencode pi; do
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
  home=$(render_tree "$tree") \
    || { echo "  staged render failed"; return 1; }
  ok=0
  wantline="description: $rendered"
  for client in claude opencode pi; do
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
    for client in claude opencode pi; do
      line=$(desc_line "$(agent_md "$WORK_HOME" "$client" "$role")")
      got=$(unquote_desc_line "$line") \
        || { echo "  $client/$role: line is not a quoted scalar: $line"; ok=1; continue; }
      [ "$got" = "$raw" ] \
        || { echo "  $client/$role: unquote(render) != agents/meta/$role.yaml"; ok=1; }
    done
  done
  for client in claude opencode pi; do
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
  home=$(render_tree "$tree") \
    || { echo "  staged round-trip render failed"; return 1; }
  for client in claude opencode pi; do
    line=$(desc_line "$(agent_md "$home" "$client" specifier)")
    got=$(unquote_desc_line "$line") \
      || { echo "  round-trip $client: line is not a quoted scalar: $line"; ok=1; continue; }
    [ "$got" = "$raw" ] \
      || { echo "  round-trip $client: got [$got] want [$raw]"; ok=1; }
  done
  return $ok
}

# ---- run --------------------------------------------------------------------

run_test "quoting-01: all four agents' rendered descriptions are double-quoted YAML scalars on all three clients, value byte-preserved from agents/meta" quoting_01
run_test "quoting-02: all three /antz-set-model renders carry a double-quoted description line (third quoting site)" quoting_02
run_test "quoting-03 (Says \"hi\"): embedded quotes escape to \" on all three sites, rendered line is exactly description: \"Says \\\"hi\\\"\"" quoting_03 'Says "hi"' '"Says \"hi\""'
run_test "quoting-03 (back\\slash): embedded backslash escapes to \\\\ on all three sites, rendered line is exactly description: \"back\\\\slash\"" quoting_03 'back\slash' '"back\\slash"'
run_test "quoting-03 (a \"b\" \\ c): mixed quotes+backslash escape per YAML rules on all three sites, rendered line is exactly description: \"a \\\"b\\\" \\\\ c\"" quoting_03 'a "b" \ c' '"a \"b\" \\ c"'
run_test "quoting-04: unquoting every rendered description line reproduces its source byte-for-byte (all agents, all three set-model renders, escape-heavy round-trip)" quoting_04

# =============================================================================
# crosssuites-01 (change optimize-test-suite, sub-spec 04): quoting-05 is
# removed whole -- no registration, no function, no glob over the suite
# files, no recursion-guard skip, and no reference to or grep of the
# renderinject or skills-activation-render suite sources. quoting-01..04
# stay registered exactly as before (and green: their own registrations ran
# in this suite before this test).
# =============================================================================
test_crosssuites_01() {
  ok=0
  refuse "$QUOTING_NONCOMMENTS" 'run_test "quoting-0''5' || ok=1
  Q5=$(mktemp)
  extract_fn "$QUOTING_NONCOMMENTS" 'quoting_0''5' "$Q5"
  [ ! -s "$Q5" ] || { echo "  the quoting-05 test function still exists"; ok=1; }
  rm -f "$Q5"
  refuse "$QUOTING_NONCOMMENTS" 'tests/*_te''st.sh' || ok=1
  refuse "$QUOTING_NONCOMMENTS" 'SELF_TE''ST' || ok=1
  refuse "$QUOTING_NONCOMMENTS" 'renderinject_te''st.sh' || ok=1
  refuse "$QUOTING_NONCOMMENTS" 'skills-activation-render_te''st.sh' || ok=1
  refuse "$QUOTING_NONCOMMENTS" 'dequote_descrip''tion' || ok=1
  refuse "$QUOTING_NONCOMMENTS" 'norm_re''nder' || ok=1
  # quoting-01..04 stay registered, unchanged (counts are the pre-refactor
  # shape: quoting-03 is a Scenario Outline with one registration per row).
  for spec in "quoting-01:1" "quoting-02:1" "quoting-03:3" "quoting-04:1"; do
    id=${spec%:*} want=${spec#*:}
    n=$(grep -c "^run_test \"$id" "$QUOTING_NONCOMMENTS")
    [ "$n" -eq "$want" ] || { echo "  $id is registered $n times, expected exactly $want"; ok=1; }
  done
  return $ok
}

run_test "crosssuites-01: quoting-05 is no longer registered -- no glob over the suite files, no grep of the renderinject or skills-activation-render suite sources, no recursion-guard flag -- and quoting-01..04 stay registered" test_crosssuites_01

finish_suite
