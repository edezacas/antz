#!/usr/bin/env bash
# Unit tests for install.sh's quoted description rendering (quoting-01, -03,
# -04). Every rendered `description:` value is a double-quoted single-line
# YAML scalar at all three render sites (render_claude, render_opencode,
# render_pi), with embedded `"` and `\` escaped per YAML double-quoted-scalar
# rules and the escaping value-preserving (unescaping reproduces the source
# byte for byte). The /antz command renderers (render_claude_command /
# render_opencode_command / render_pi_command) stay unquoted -- out of scope.
#
# Self-contained bash test area (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/skills-activation-render_test.sh. Run directly:
#   sh tests/description-quoting_test.sh
#
# Each reported test name embeds its scenario id (quoting-01, -03, -04), so a
# failure maps straight back to the scenario it covers. Every test renders
# through the harness library's render-once helper against isolated temp
# HOMEs, never the real ~/.claude or ~/.config/opencode.
#
# The shared harness library provides the plumbing helpers (run_test,
# skip_test, temp bookkeeping, cleanup, stage_checkout, and the install
# renderers); this suite defines none of them itself.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

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
# quoting-03 (Scenario Outline): real YAML quoting, not just wrapping -- an
# embedded `"` or `\` in the source is escaped, so the rendered line stays a
# valid single-line scalar. One test per Examples row; each row is staged
# into every meta description and rendered for all three clients, pinning
# the same raw/rendered pair on each render site.
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
  done
  return $ok
}

# =============================================================================
# quoting-04: quoting is value-preserving -- for every rendered description
# line (all agents, all three clients), stripping the outer quotes and
# YAML-unescape yields exactly the source description text. Also a staged
# round-trip with an escape-heavy and trailing-backslash value.
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
run_test "quoting-03 (Says \"hi\"): embedded quotes escape to \" on every client's agent render, rendered line is exactly description: \"Says \\\"hi\\\"\"" quoting_03 'Says "hi"' '"Says \"hi\""'
run_test "quoting-03 (back\\slash): embedded backslash escapes to \\\\ on every client's agent render, rendered line is exactly description: \"back\\\\slash\"" quoting_03 'back\slash' '"back\\slash"'
run_test "quoting-03 (a \"b\" \\ c): mixed quotes+backslash escape per YAML rules on every client's agent render" quoting_03 'a "b" \ c' '"a \"b\" \\ c"'
run_test "quoting-04: unquoting every rendered description line reproduces its source byte-for-byte (all four agents, all three clients, escape-heavy round-trip)" quoting_04


finish_suite
