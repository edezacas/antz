#!/usr/bin/env bash
# Unit tests for change deembed-orchestration-scripts sub-spec 03: the
# set-model script installs as the fourth libdir file with a REQUIRED first
# positional client argument (claude|opencode, resolved to its agents dir
# internally), and both /antz-set-model command bodies invoke it by its
# concrete resolved path instead of embedding it. Covers every scenario in
# spdd/changes/deembed-orchestration-scripts/03-setmodeldeembed.feature
# (setmodeldeembed-01..06).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system), same pattern as
# tests/libdirinstall_test.sh. Run directly:
#   ./tests/setmodeldeembed_test.sh
#
# Each reported test name embeds its scenario id (setmodeldeembed-01..06)
# from the feature file above, so a failure maps straight back to the
# scenario it covers. Every run gets an isolated HOME (fresh temp dirs,
# cleaned on exit) with XDG_CONFIG_HOME explicitly unset, so the shared
# libdir resolves inside the staged HOME and the real ~/.claude,
# ~/.config/opencode and ~/.config/antz are never touched.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

CURRENT_VERSION=$(tr -d ' \t\r\n' < "$SCRIPT_DIR/VERSION")

pass_count=0
fail_count=0
skip_count=0

# ---- tiny test runner -------------------------------------------------------

run_test() {
  # $1 = reported test name (must contain its scenario id), $2 = function name
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

cleanup() { [ "${#tmp_roots[@]}" -gt 0 ] && rm -rf "${tmp_roots[@]}"; }
trap cleanup EXIT

# ---- fixture helpers ---------------------------------------------------------

install_at() {
  # $1 = HOME, rest = install.sh flags: a hermetic --all-style run.
  home="$1"; shift
  env -u XDG_CONFIG_HOME HOME="$home" sh "$INSTALL_SH" "$@"
}

# One shared installed set-model script, rendered once for the invocation
# scenarios (install.sh's render is deterministic and $HOME-independent, so
# the editing tests reuse it and only vary the HOME they run against).
SET_MODEL=""

setup_installed_script() {
  d=$(new_tmp_dir)
  install_at "$d" --all > /dev/null 2>&1 || { echo "  setup install failed"; return 1; }
  SET_MODEL="$d/.config/antz/scripts/antz-set-model.sh"
}

write_claude_fixture() {
  # $1 = dest path, $2 = agent name, $3 = model value (optional; omit for none)
  dest="$1"; agent="$2"; model="${3:-}"
  mkdir -p "$(dirname "$dest")"
  {
    echo '---'
    echo '# antz:generated version=1.2.3 -- do not edit by hand; regenerate with install.sh'
    echo "name: antz-$agent"
    echo "description: Test description for $agent."
    [ -n "$model" ] && echo "model: $model"
    echo 'tools: Read, Grep, Glob, Bash'
    echo '---'
    echo ''
    echo "Body text for $agent."
  } > "$dest"
}

write_opencode_fixture() {
  # $1 = dest path, $2 = agent name, $3 = model value (optional; omit for none)
  dest="$1"; agent="$2"; model="${3:-}"
  mkdir -p "$(dirname "$dest")"
  {
    echo '---'
    echo '# antz:generated version=1.2.3 -- do not edit by hand; regenerate with install.sh'
    echo "description: Test description for $agent."
    [ -n "$model" ] && echo "model: $model"
    echo 'mode: subagent'
    echo 'permission:'
    echo '  edit: allow'
    echo '  task: deny'
    echo '---'
    echo ''
    echo "Body text for $agent."
  } > "$dest"
}

write_unmanaged_fixture() {
  # A same-named file that does NOT carry the line-start marker.
  dest="$1"; agent="$2"
  mkdir -p "$(dirname "$dest")"
  {
    echo '---'
    echo "name: antz-$agent"
    echo "description: A user's own hand-written agent, not antz-managed."
    echo 'tools: Read'
    echo '---'
    echo ''
    echo "Body text for $agent."
  } > "$dest"
}

# ---- setmodeldeembed-01 ------------------------------------------------------
# The installed script gains a required first positional client argument and
# keeps its entire behavior contract: internal agents-dir resolution, the
# unchanged editing contract at the fixed frontmatter position, byte-
# identical success/failure messages with the client name from the argument,
# and a missing/unknown client usage error naming both valid values that
# writes nothing.

setmodeldeembed_01_editing() {
  [ -f "$SET_MODEL" ] || { echo "  setmodeldeembed-01: the installed libdir file is missing: $SET_MODEL"; return 1; }
  [ "$(sed -n '1p' "$SET_MODEL")" = '#!/bin/sh' ] || { echo "  line 1 is not the shebang"; return 1; }
  [ "$(sed -n '2p' "$SET_MODEL")" = "# antz:generated version=$CURRENT_VERSION -- do not edit by hand; regenerate with install.sh" ] \
    || { echo "  line 2 is not the marker: $(sed -n '2p' "$SET_MODEL")"; return 1; }
  ok=0
  home=$(new_tmp_dir)

  # (a) claude: add at the fixed position (after "description:", before
  # "tools:"), byte-preserving everything else; success message byte-exact.
  # (variable names avoid dest/agent/model: the fixture helpers assign those
  # as globals, POSIX-shell style, like every sibling suite)
  cfile="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$cfile" coder
  cp "$cfile" "$cfile.orig"
  out=$(HOME="$home" sh "$SET_MODEL" claude --agent coder --model opus 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "  claude set exited $rc ($out)"; ok=1; }
  [ "$out" = "antz-coder (claude) now has model: opus ($cfile)" ] \
    || { echo "  success message not byte-identical: [$out]"; ok=1; }
  desc_line=$(grep -n '^description:' "$cfile.orig" | head -n1 | cut -d: -f1)
  expected=$(mktemp)
  sed "${desc_line}a\\
model: opus" "$cfile.orig" > "$expected"
  cmp -s "$expected" "$cfile" || { echo "  claude insert not at the fixed byte-preserving position"; ok=1; }
  rm -f "$expected"

  # (b) claude: replace in place, then --clear remove, with byte-exact replies.
  out=$(HOME="$home" sh "$SET_MODEL" claude --agent coder --model sonnet 2>&1); rc=$?
  [ "$rc" -eq 0 ] && grep -qxF 'model: sonnet' "$cfile" || { echo "  replace failed ($rc: $out)"; ok=1; }
  grep -qxF 'model: opus' "$cfile" && { echo "  old model line survived the replace"; ok=1; }
  out=$(HOME="$home" sh "$SET_MODEL" claude --agent coder --clear 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "  clear exited $rc ($out)"; ok=1; }
  [ "$out" = "Cleared the model for antz-coder (claude); $cfile no longer has a model: line." ] \
    || { echo "  clear message not byte-identical: [$out]"; ok=1; }
  grep -q '^model:' "$cfile" && { echo "  model: line survived --clear"; ok=1; }

  # (c) opencode: the argument resolves the opencode agents dir and its own
  # frontmatter position (after description, before mode).
  ofile="$home/.config/opencode/agents/antz-verifier.md"
  write_opencode_fixture "$ofile" verifier
  cp "$ofile" "$ofile.orig"
  out=$(HOME="$home" sh "$SET_MODEL" opencode --agent verifier --model anthropic/claude-opus-4-5 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "  opencode set exited $rc ($out)"; ok=1; }
  [ "$out" = "antz-verifier (opencode) now has model: anthropic/claude-opus-4-5 ($ofile)" ] \
    || { echo "  opencode success message not byte-identical: [$out]"; ok=1; }
  desc_line=$(grep -n '^description:' "$ofile.orig" | head -n1 | cut -d: -f1)
  expected=$(mktemp)
  sed "${desc_line}a\\
model: anthropic/claude-opus-4-5" "$ofile.orig" > "$expected"
  cmp -s "$expected" "$ofile" || { echo "  opencode insert not at the fixed byte-preserving position"; ok=1; }
  rm -f "$expected"
  # the claude file (back at its pre-edit bytes after the clear) was not
  # touched by the opencode run, and vice versa
  cmp -s "$cfile.orig" "$cfile" || { echo "  the opencode run touched the claude file"; ok=1; }
  rm -rf "$home"
  return $ok
}

setmodeldeembed_01_client_usage() {
  [ -f "$SET_MODEL" ] || { echo "  setmodeldeembed-01: the installed libdir file is missing"; return 1; }
  ok=0
  home=$(new_tmp_dir)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"

  # Missing client (the old flag-only invocation): usage error naming both
  # valid values, nothing written.
  out=$(HOME="$home" sh "$SET_MODEL" --agent coder --model opus 2>&1); rc=$?
  [ "$rc" -ne 0 ] || { echo "  a missing client argument exited 0"; ok=1; }
  case "$out" in *claude*opencode*|*opencode*claude*) ;; *) echo "  missing-client error names neither valid value: $out"; ok=1 ;; esac
  case "$out" in *Usage*) ;; *) echo "  missing-client refusal is not a usage error: $out"; ok=1 ;; esac
  cmp -s "$dest.orig" "$dest" || { echo "  the missing-client run wrote the target"; ok=1; }
  [ -z "$(find "$home" -newer "$dest.orig" -type f ! -name '*.orig' -print -quit 2>/dev/null)" ] \
    || { echo "  the missing-client run touched files under HOME"; ok=1; }

  # Unknown client: same usage error, nothing written.
  out=$(HOME="$home" sh "$SET_MODEL" bogus --agent coder --model opus 2>&1); rc=$?
  [ "$rc" -ne 0 ] || { echo "  an unknown client argument exited 0"; ok=1; }
  case "$out" in *claude*opencode*|*opencode*claude*) ;; *) echo "  unknown-client error names neither valid value: $out"; ok=1 ;; esac
  cmp -s "$dest.orig" "$dest" || { echo "  the unknown-client run wrote the target"; ok=1; }
  rm -rf "$home"
  return $ok
}

setmodeldeembed_01_failure_messages() {
  [ -f "$SET_MODEL" ] || { echo "  setmodeldeembed-01: the installed libdir file is missing"; return 1; }
  ok=0
  home=$(new_tmp_dir)

  # Not-installed refusal: byte-identical to today's, with the client name
  # now coming from the argument.
  out=$(HOME="$home" sh "$SET_MODEL" claude --agent coder --model opus 2>&1); rc=$?
  [ "$rc" -ne 0 ] || { echo "  not-installed run exited 0"; ok=1; }
  [ "$out" = "Error: antz-coder is not installed for claude yet (no file at $home/.claude/agents/antz-coder.md); install it first, e.g. ./install.sh --claude. No file was written." ] \
    || { echo "  not-installed message not byte-identical: [$out]"; ok=1; }

  # Unmanaged refusal and the nothing-to-clear no-op: byte-identical.
  dest="$home/.claude/agents/antz-specifier.md"
  write_unmanaged_fixture "$dest" specifier
  cp "$dest" "$dest.orig"
  out=$(HOME="$home" sh "$SET_MODEL" claude --agent specifier --model opus 2>&1); rc=$?
  [ "$rc" -ne 0 ] || { echo "  unmanaged run exited 0"; ok=1; }
  [ "$out" = "Error: $dest is not antz-managed (missing the 'antz:generated' marker); refusing to modify it. No file was written." ] \
    || { echo "  unmanaged message not byte-identical: [$out]"; ok=1; }
  cmp -s "$dest.orig" "$dest" || { echo "  the unmanaged refusal modified the file"; ok=1; }

  dest2="$home/.config/opencode/agents/antz-coder.md"
  write_opencode_fixture "$dest2" coder
  cp "$dest2" "$dest2.orig"
  out=$(HOME="$home" sh "$SET_MODEL" opencode --agent coder --clear 2>&1); rc=$?
  [ "$rc" -eq 0 ] || { echo "  nothing-to-clear exited $rc ($out)"; ok=1; }
  [ "$out" = "antz-coder (opencode) has no model configured; nothing to clear. $dest2 is unchanged." ] \
    || { echo "  nothing-to-clear message not byte-identical: [$out]"; ok=1; }
  cmp -s "$dest2.orig" "$dest2" || { echo "  the nothing-to-clear no-op changed the file"; ok=1; }
  rm -rf "$home"
  return $ok
}

# ---- setmodeldeembed-02 ------------------------------------------------------
# The command bodies embed no script: no ```sh fence, no temp-file
# instruction; the run instruction invokes the installed script by its
# concrete resolved path with the copy's own client first; "Arguments:
# $ARGUMENTS" stays the single injection point; no cross-client references.

setmodeldeembed_02_bodies() {
  d=$(new_tmp_dir); ok=0
  install_at "$d" --all > /dev/null 2>&1 || { echo "  install failed"; return 1; }
  lib="$d/.config/antz/scripts"
  claude_cmd="$d/.claude/commands/antz-set-model.md"
  opencode_cmd="$d/.config/opencode/commands/antz-set-model.md"

  # every installed file still runs by path with no temp-file dance
  [ -f "$lib/antz-set-model.sh" ] || { echo "  the installed script is missing"; return 1; }
  for f in "$claude_cmd" "$opencode_cmd"; do
    grep -q '^```sh$' "$f" && { echo "  $f still carries the \`\`\`sh script fence"; ok=1; }
    grep -qi 'temp file\|tempfile' "$f" && { echo "  $f still instructs a temp file:"; grep -ni 'temp file\|tempfile' "$f" | sed 's/^/    /'; ok=1; }
    grep -qi 'saving it below' "$f" && { echo "  $f still says the script is 'below'"; ok=1; }
    arg_lines=$(grep -c 'ARGUMENTS' "$f")
    [ "$arg_lines" -eq 1 ] || { echo "  $f carries $arg_lines ARGUMENTS occurrences, expected exactly 1"; ok=1; }
    grep -qxF 'Arguments: $ARGUMENTS' "$f" || { echo "  $f lost the single 'Arguments: \$ARGUMENTS' injection line"; ok=1; }
  done

  # the run instruction: concrete resolved path + the copy's own client as
  # first argument -- the invoker never supplies a client
  grep -qF "sh \"$lib/antz-set-model.sh\" claude" "$claude_cmd" \
    || { echo "  the claude copy does not invoke the installed script by concrete path passing 'claude' first"; ok=1; }
  grep -qF "sh \"$lib/antz-set-model.sh\" opencode" "$opencode_cmd" \
    || { echo "  the opencode copy does not invoke the installed script by concrete path passing 'opencode' first"; ok=1; }
  grep -F 'antz-set-model.sh"' "$claude_cmd" | grep -v 'claude' | grep . \
    && { echo "  the claude copy's run instruction passes something other than 'claude'"; ok=1; }
  grep -F 'antz-set-model.sh"' "$opencode_cmd" | grep -v 'opencode' | grep . \
    && { echo "  the opencode copy's run instruction passes something other than 'opencode'"; ok=1; }

  # each copy still never references the other client's directory or position
  grep -qi 'opencode' "$claude_cmd" && { echo "  the claude copy references OpenCode"; ok=1; }
  grep -qi 'claude code' "$opencode_cmd" && { echo "  the opencode copy references Claude Code"; ok=1; }
  grep -qF '.claude/agents' "$opencode_cmd" && { echo "  the opencode copy references Claude's agents dir"; ok=1; }
  rm -rf "$d"
  return $ok
}

# ---- setmodeldeembed-03 ------------------------------------------------------
# The emitter capture retires for the script only (plain redirection to the
# libdir file; the workaround comment retires with it), the pickers and the
# flow head keep their captures, and install.sh stays POSIX/bash-3.2-safe.

setmodeldeembed_03_internals() {
  ok=0
  # set_model_script() and its per-client substitution are gone
  grep -qE '^set_model_script\(\) \{$' "$INSTALL_SH" && { echo "  set_model_script() still exists"; ok=1; }
  grep -qF '__AGENTS_DIR__' "$INSTALL_SH" && { echo "  the __AGENTS_DIR__ substitution token survives"; ok=1; }
  grep -qF 'src_set_model=$(emit_set_model_script' "$INSTALL_SH" && { echo "  the emitter text is still captured through a command substitution"; ok=1; }
  # the script text is written straight to the libdir file (plain redirection)
  grep -qF 'emit_set_model_script > "$dest"' "$INSTALL_SH" \
    || { echo "  the script text is not redirected straight into the libdir file"; ok=1; }
  # the workaround comment lost its subject and retired with the capture:
  # only the pickers'/flow head's rationale block still states it
  n=$(grep -c "Capturing a function's stdout inside" "$INSTALL_SH")
  [ "$n" -eq 1 ] || { echo "  expected exactly one bash-3.2 capture-rationale block (the pickers'), found $n"; ok=1; }
  defln=$(grep -n '^emit_set_model_script() {$' "$INSTALL_SH" | head -n1 | cut -d: -f1)
  [ -n "$defln" ] || { echo "  emit_set_model_script() is no longer defined at top level"; ok=1; }
  if [ -n "$defln" ]; then
    from=$(( defln > 11 ? defln - 10 : 1 ))
    sed -n "${from},$((defln - 1))p" "$INSTALL_SH" | grep -qE '3\.2|posixsh-01' && {
      echo "  emit_set_model_script is still preceded by the retired workaround comment"; ok=1; }
  fi
  # the pickers and the flow head keep their command-substitution captures
  grep -qF 'picker=$(emit_picker_claude)' "$INSTALL_SH" || { echo "  emit_picker_claude's capture is gone"; ok=1; }
  grep -qF 'picker=$(emit_picker_opencode)' "$INSTALL_SH" || { echo "  emit_picker_opencode's capture is gone"; ok=1; }
  grep -qF 'flow_head=$(set_model_flow_head' "$INSTALL_SH" || { echo "  set_model_flow_head's capture is gone"; ok=1; }
  # still POSIX-parseable, and the posixsh-01 construct class stays absent
  err=$(new_tmp_dir)/sh-n.err
  sh -n "$INSTALL_SH" 2>"$err" || { echo "  sh -n failed: $(cat "$err")"; ok=1; }
  [ -s "$err" ] && { echo "  sh -n stderr not clean: $(cat "$err")"; ok=1; }
  grep -qF '$(cat <<' "$INSTALL_SH" && { echo "  a heredoc body sits inside a command substitution"; ok=1; }
  return $ok
}

setmodeldeembed_03_bash32() {
  # install.sh parses clean under the macOS-fidelity POSIX-mode parser
  # (bash 3.2), same instrument and skip discipline as posixsh-02.
  out=$(sh "$SCRIPT_DIR/tests/bash32-sh.sh" 2>/dev/null) || {
    B32_SKIP="bash32 provision failed: ${out:-no output from helper}"
    return 1
  }
  case "$out" in
    "<bash32="*">") B32=${out#<bash32=}; B32=${B32%>} ;;
    *) B32_SKIP="bash32 provision failed: unexpected helper output"; return 1 ;;
  esac
  [ -x "$B32" ] || { B32_SKIP="bash32 provision succeeded but the binary is not executable"; return 1; }
  err=$(new_tmp_dir)/err.txt
  "$B32" --posix -n "$INSTALL_SH" 2>"$err" || {
    echo "  install.sh failed bash3.2 --posix -n: $(cat "$err")"
    return 1
  }
  [ -s "$err" ] && { echo "  unexpected stderr on bash32 parse: $(cat "$err")"; return 1; }
  return 0
}

# ---- setmodeldeembed-04 ------------------------------------------------------
# Token-templating re-scoped: the bodies keep the dollar-digit-free single-
# $ARGUMENTS constraint; the installed file is standalone (positional
# parameters allowed, never templated), runs the same observable contract,
# and the exactly-one-of / fail-fast / picker / relay constraints are
# unchanged.

setmodeldeembed_04_tokens() {
  d=$(new_tmp_dir); ok=0
  install_at "$d" --all > /dev/null 2>&1 || { echo "  install failed"; return 1; }
  lib="$d/.config/antz/scripts"

  # the rendered bodies stay templatable-safe...
  for f in "$d/.claude/commands/antz-set-model.md" "$d/.config/opencode/commands/antz-set-model.md"; do
    if grep -qE '\$[0-9]' "$f"; then
      echo "  $f contains a dollar-digit token:"; grep -nE '\$[0-9]' "$f" | head -3 | sed 's/^/    /'; ok=1
    fi
    lines=$(grep -cF '$ARGUMENTS' "$f")
    [ "$lines" -eq 1 ] || { echo "  $f carries $lines \$ARGUMENTS occurrences, expected exactly 1"; ok=1; }
    grep -qxF 'Arguments: $ARGUMENTS' "$f" || { echo "  $f lost the injection line"; ok=1; }
  done
  # ...while the installed file is standalone and may use positional
  # parameters (the re-scoped prohibition): it consumes "$1" and parses
  # under plain sh.
  grep -qF '${1:-}' "$lib/antz-set-model.sh" \
    || { echo "  the installed file no longer reads its client from a positional parameter (standalone-file clause)"; ok=1; }
  grep -qF '$ARGUMENTS' "$lib/antz-set-model.sh" && { echo "  the installed file references \$ARGUMENTS (never templated)"; ok=1; }
  err=$(new_tmp_dir)/err.txt
  sh -n "$lib/antz-set-model.sh" 2>"$err" || { echo "  installed script fails sh -n: $(cat "$err")"; ok=1; }

  # the unchanged invocation contract, run through the installed file
  home=$(new_tmp_dir)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  out=$(HOME="$home" sh "$lib/antz-set-model.sh" claude --agent coder 2>&1); rc=$?
  [ "$rc" -ne 0 ] || { echo "  'neither --model nor --clear' was accepted"; ok=1; }
  case "$out" in *"exactly one of --model/--clear"*) ;; *) echo "  'neither' refusal changed: $out"; ok=1 ;; esac
  out=$(HOME="$home" sh "$lib/antz-set-model.sh" claude --agent coder --model opus --clear 2>&1); rc=$?
  [ "$rc" -ne 0 ] || { echo "  'both --model and --clear' was accepted"; ok=1; }
  case "$out" in *"mutually exclusive"*) ;; *) echo "  'both' refusal changed: $out"; ok=1 ;; esac
  cmp -s "$dest.orig" "$dest" || { echo "  a refused invocation wrote the target"; ok=1; }

  # the command bodies still state the fail-fast ordering, the picker flow
  # and the relay rule (unchanged clauses)
  for f in "$d/.claude/commands/antz-set-model.md" "$d/.config/opencode/commands/antz-set-model.md"; do
    grep -qF 'before asking any question' "$f" || { echo "  $f lost the fail-fast ordering"; ok=1; }
    grep -qF 'Never invoke the script without exactly one of' "$f" || { echo "  $f lost the exactly-one-of rule"; ok=1; }
    grep -qF 'exactly what the script printed' "$f" || { echo "  $f lost the relay rule"; ok=1; }
    grep -qF 'carries the `antz:generated` marker' "$f" || { echo "  $f lost the marker pre-flight"; ok=1; }
  done
  grep -qF 'AskUserQuestion' "$d/.claude/commands/antz-set-model.md" || { echo "  the claude picker block is gone"; ok=1; }
  grep -qF '`question` tool' "$d/.config/opencode/commands/antz-set-model.md" || { echo "  the opencode picker block is gone"; ok=1; }
  rm -rf "$d" "$home"
  return $ok
}

# ---- setmodeldeembed-05 ------------------------------------------------------
# The suites that pinned the embedded script re-scoped to the installed
# file: set-model-command_test.sh runs the installed libdir file with the
# same ids still passing, and posixsh-04 asserts 'for arg do' in the
# installed file with the four libdir files in the inventory. (The
# spdd/specs/posixsh.md e2e-qa-01 merge of the same clauses is verifier-
# owned -- reported as a boundary, not performed here.)

setmodeldeembed_05_suites() {
  ok=0
  sm="$SCRIPT_DIR/tests/set-model-command_test.sh"
  px="$SCRIPT_DIR/tests/installsh-posixsh_test.sh"

  # extraction replaced by running the installed libdir file...
  grep -qF 'extract_script()' "$sm" && { echo "  set-model-command_test.sh still extracts the embedded script"; ok=1; }
  grep -qF '.config/antz/scripts/antz-set-model.sh' "$sm" \
    || { echo "  set-model-command_test.sh does not run the installed libdir file"; ok=1; }
  # ...and posixsh-04 re-keyed to the installed file + 16-file inventory
  grep -qF "'^for arg do\$' \"\$new_home/.config/antz/scripts/antz-set-model.sh\"" "$px" \
    || { echo "  posixsh-04's 'for arg do' assertion is not re-keyed to the installed file"; ok=1; }
  for s in antz-flow.sh antz-probe.sh antz-skills.sh antz-set-model.sh; do
    grep -qF ".config/antz/scripts/$s" "$px" \
      || { echo "  posixsh-04's documented inventory does not name the libdir file $s"; ok=1; }
  done

  # both suites still pass with the same ids reported
  out=$(sh "$sm" 2>&1) || { echo "  set-model-command_test.sh failed:"; printf '%s\n' "$out" | grep -E '^(FAIL|pass=)' | head -5 | sed 's/^/    /'; ok=1; }
  printf '%s\n' "$out" | grep -q '^PASS: set-model-cmd-01' || { echo "  set-model-cmd-01 not reported passing"; ok=1; }
  printf '%s\n' "$out" | grep -q '^PASS: setmodel-01' || { echo "  setmodel-01 not reported passing"; ok=1; }
  out=$(sh "$px" 2>&1) || { echo "  installsh-posixsh_test.sh failed:"; printf '%s\n' "$out" | grep -E '^(FAIL|pass=)' | head -5 | sed 's/^/    /'; ok=1; }
  printf '%s\n' "$out" | grep -q '^PASS: posixsh-04' || { echo "  posixsh-04 not reported passing"; ok=1; }
  return $ok
}

# ---- setmodeldeembed-06 ------------------------------------------------------
# The command files' shape after the de-embed: unchanged frontmatter, all
# body sections intact, the script fence gone with the copy near half its
# pre-de-embed size, and an idempotent marker-based overwrite.

setmodeldeembed_06_shape() {
  d=$(new_tmp_dir); ok=0
  install_at "$d" --all > /dev/null 2>&1 || { echo "  install failed"; return 1; }
  claude_cmd="$d/.claude/commands/antz-set-model.md"
  opencode_cmd="$d/.config/opencode/commands/antz-set-model.md"

  # frontmatter unchanged (second clause): marker, quoted description,
  # argument-hint on Claude, no agent: field anywhere
  [ "$(sed -n '2p' "$claude_cmd")" = "# antz:generated version=$CURRENT_VERSION -- do not edit by hand; regenerate with install.sh" ] \
    || { echo "  claude copy lost its frontmatter marker"; ok=1; }
  [ "$(sed -n '2p' "$opencode_cmd")" = "# antz:generated version=$CURRENT_VERSION -- do not edit by hand; regenerate with install.sh" ] \
    || { echo "  opencode copy lost its frontmatter marker"; ok=1; }
  grep -qE '^description: "' "$claude_cmd" || { echo "  claude description is not a quoted scalar"; ok=1; }
  grep -qE '^description: "' "$opencode_cmd" || { echo "  opencode description is not a quoted scalar"; ok=1; }
  grep -qxF 'argument-hint: --agent <specifier|coder|verifier|orchestrator> [--model <value>|--clear]' "$claude_cmd" \
    || { echo "  claude copy lost its argument-hint line"; ok=1; }
  grep -qE '^agent:' "$claude_cmd" && { echo "  claude copy grew an agent: field"; ok=1; }
  grep -qE '^agent:' "$opencode_cmd" && { echo "  opencode copy grew an agent: field"; ok=1; }

  # each body keeps the intro, fail-fast steps, pre-flight, its picker
  # block, and the apply/relay tail
  for f in "$claude_cmd" "$opencode_cmd"; do
    grep -qF 'Configure or clear the model: line in an already-installed' "$f" || { echo "  $f lost the intro"; ok=1; }
    grep -qF 'Step 1 -- Validate the arguments, before asking any question' "$f" || { echo "  $f lost step 1"; ok=1; }
    grep -qF 'Step 3 -- Pre-flight' "$f" || { echo "  $f lost the pre-flight"; ok=1; }
    grep -qF 'Step 5 -- Apply the answer, then reply' "$f" || { echo "  $f lost the apply/relay tail"; ok=1; }
  done
  grep -qxF '1. `sonnet`' "$claude_cmd" || { echo "  the claude picker's alias options are gone"; ok=1; }
  grep -qF 'opusplan' "$claude_cmd" || { echo "  the claude picker's alias vocabulary is gone"; ok=1; }
  grep -qF 'opencode models' "$opencode_cmd" || { echo "  the opencode enumeration instruction is gone"; ok=1; }
  grep -qF 'Type another value' "$opencode_cmd" || { echo "  the opencode free-form option is gone"; ok=1; }

  # the script fence is dropped: each copy is at most half its measured
  # pre-de-embed size (192/186 lines), never vacuously small (the section
  # assertions above carry the floor, this bounds the ceiling)
  cl=$(wc -l < "$claude_cmd"); ol=$(wc -l < "$opencode_cmd")
  [ "$cl" -le 96 ] || { echo "  the claude copy still measures $cl lines (expected at most half of 192)"; ok=1; }
  [ "$ol" -le 93 ] || { echo "  the opencode copy still measures $ol lines (expected at most half of 186)"; ok=1; }
  grep -q '^```sh$' "$claude_cmd" && { echo "  the claude copy still carries the fence"; ok=1; }

  # re-running overwrites both copies in place with no backup
  csum_before=$(cksum "$claude_cmd" "$opencode_cmd")
  install_at "$d" --all > /dev/null 2>&1 || { echo "  re-install failed"; return 1; }
  [ "$csum_before" = "$(cksum "$claude_cmd" "$opencode_cmd")" ] || { echo "  the re-run rendered different bytes"; ok=1; }
  [ -z "$(find "$d/.claude/commands" "$d/.config/opencode/commands" -name 'antz-set-model.md.bak.*' -print -quit)" ] \
    || { echo "  the re-run backed up a managed command copy"; ok=1; }
  rm -rf "$d"
  return $ok
}

# ---- run ---------------------------------------------------------------------

setup_installed_script || { echo "FATAL: could not install the set-model script"; exit 1; }

run_test "setmodeldeembed-01: the installed libdir file takes claude|opencode as its required first argument, resolves the agents dir internally, and keeps the editing contract with byte-identical success messages" setmodeldeembed_01_editing
run_test "setmodeldeembed-01: a missing or unknown client argument is a usage error naming claude and opencode, and writes nothing" setmodeldeembed_01_client_usage
run_test "setmodeldeembed-01: not-installed, unmanaged-marker and nothing-to-clear failure/no-op messages are byte-identical to today's, with the client name from the argument" setmodeldeembed_01_failure_messages
run_test "setmodeldeembed-02: both command copies drop the \`\`\`sh fence and the temp-file instruction, invoke the installed script by concrete path with the copy's own client first, keep 'Arguments: \$ARGUMENTS' as the single injection point, and never reference the other client" setmodeldeembed_02_bodies
run_test "setmodeldeembed-03: set_model_script()'s capture and the __AGENTS_DIR__ substitution are retired for a plain-redirection libdir write with the workaround comment gone, the pickers' and flow head's captures survive, and install.sh stays sh -n- and posixsh-01-clean" setmodeldeembed_03_internals
run_test "setmodeldeembed-03: install.sh still parses under the bash 3.2 POSIX-mode check after the retirement" setmodeldeembed_03_bash32
run_test "setmodeldeembed-04: the bodies stay dollar-digit-free with one \$ARGUMENTS injection; the standalone installed file may use positional parameters, parses, runs the same exactly-one-of contract; the fail-fast ordering, picker flow and relay rule are unchanged" setmodeldeembed_04_tokens
run_test "setmodeldeembed-05: set-model-command_test.sh runs the installed libdir file and posixsh-04 re-keys 'for arg do' plus the 16-file inventory -- both suites pass with the same ids reported (the spdd/specs/posixsh.md merge itself is verifier-owned)" setmodeldeembed_05_suites
run_test "setmodeldeembed-06: rendered copies keep their frontmatter and every body section, drop the fence near half the measured 192/186 size, keep the picker vocabularies, and re-install overwrites in place with no backup" setmodeldeembed_06_shape

if [ -n "${B32_SKIP:-}" ]; then
  # provision failure: downgrade the FAIL just counted into an explicit SKIP
  # stub (environmental, same discipline as posixsh-02).
  fail_count=$((fail_count - 1))
  echo "SKIP: setmodeldeembed-03: install.sh parses under the bash 3.2 POSIX-mode check (${B32_SKIP})"
  skip_count=$((skip_count + 1))
fi

echo
echo "pass=$pass_count fail=$fail_count skip=$skip_count"
[ "$fail_count" -eq 0 ]
