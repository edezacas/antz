#!/usr/bin/env bash
# Unit tests for install.sh's /antz-set-model command (rendering/install
# side) and the self-contained script embedded in its body (invocation
# side), covering every scenario in
# spdd/changes/set-model-native-command/01-set-model-command.feature.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system). Run directly:
#   ./tests/set-model-command_test.sh
#
# Each reported test name embeds its scenario id (command-install-01..05,
# set-model-cmd-01..12) from the feature file above, so
# a failure maps straight back to the scenario it covers. Every test that
# touches the filesystem runs against an isolated $HOME (a fresh temp dir
# per test), so tests never touch the real ~/.claude or ~/.config/opencode
# directories and never interfere with each other.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

pass_count=0
fail_count=0

# ---- tiny test runner ------------------------------------------------------

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

new_home() {
  mktemp -d
}

# Restricted PATH that still resolves every POSIX utility install.sh/the
# embedded script need, but never resolves a "claude" or "opencode" binary --
# needed so client auto-detection tests are not accidentally influenced by
# either CLI happening to be installed on the machine running this suite.
NO_CLIENT_CLI_PATH="/usr/bin:/bin"

# ---- fixture helpers --------------------------------------------------------
# Mirror install.sh's render_claude/render_opencode frontmatter shape
# (marker/version comment, then name/description/tools or
# description/mode/permission, a blank line, then the prompt body) closely
# enough to exercise the embedded script's position/marker logic realistically.

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
  # A same-named file that does NOT carry the antz:generated marker.
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

# ---- extracting the embedded script from a rendered command file -----------

extract_script() {
  # $1 = path to an installed antz-set-model.md; prints just the fenced
  # ```sh ... ``` script embedded in its body.
  awk '/^```sh$/{flag=1; next} /^```$/{flag=0} flag' "$1"
}

# Extracted once (rendering is deterministic and $HOME-independent), reused
# by every set-model-cmd-* invocation test below so those tests don't each
# pay the cost of a full install.sh run just to get the script.
CLAUDE_SCRIPT=""
OPENCODE_SCRIPT=""

setup_extracted_scripts() {
  tmp_home=$(new_home)
  ( cd "$SCRIPT_DIR" && HOME="$tmp_home" "$INSTALL_SH" --all >/dev/null 2>&1 )
  CLAUDE_SCRIPT=$(mktemp)
  OPENCODE_SCRIPT=$(mktemp)
  extract_script "$tmp_home/.claude/commands/antz-set-model.md" > "$CLAUDE_SCRIPT"
  extract_script "$tmp_home/.config/opencode/commands/antz-set-model.md" > "$OPENCODE_SCRIPT"
  chmod +x "$CLAUDE_SCRIPT" "$OPENCODE_SCRIPT"
  rm -rf "$tmp_home"
}

# =============================================================================
# command-install-01: install.sh installs the Claude Code copy with the
# expected frontmatter shape, mirroring how it already installs /antz.
# =============================================================================
test_command_install_01() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --claude >/dev/null 2>&1 )
  dest="$home/.claude/commands/antz-set-model.md"

  [ -f "$dest" ] || { echo "  $dest was not created"; ok=1; }
  grep -q 'antz:generated version=' "$dest" || { echo "  missing antz:generated marker with version"; ok=1; }
  grep -q '^description:' "$dest" || { echo "  missing description: field"; ok=1; }
  grep -qxF 'argument-hint: --agent <specifier|coder|verifier|orchestrator> (--model <value>|--clear)' "$dest" \
    || { echo "  missing expected argument-hint line"; ok=1; }
  grep -qi 'opencode' "$dest" && { echo "  body/frontmatter references OpenCode"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# command-install-02: same for OpenCode, at OpenCode's own paths -- and,
# unlike /antz, with no "agent:" frontmatter field.
# =============================================================================
test_command_install_02() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --opencode >/dev/null 2>&1 )
  dest="$home/.config/opencode/commands/antz-set-model.md"

  [ -f "$dest" ] || { echo "  $dest was not created"; ok=1; }
  grep -q 'antz:generated version=' "$dest" || { echo "  missing antz:generated marker with version"; ok=1; }
  grep -q '^description:' "$dest" || { echo "  missing description: field"; ok=1; }
  grep -q '^agent:' "$dest" && { echo "  unexpected agent: field present"; ok=1; }
  grep -qi 'claude code' "$dest" && { echo "  body/frontmatter references Claude Code"; ok=1; }
  grep -qF '.claude/agents' "$dest" && { echo "  body references Claude Code's agent directory"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# command-install-03: re-running is idempotent, reusing install.sh's
# existing marker-based overwrite-in-place convention.
# =============================================================================
test_command_install_03() {
  home=$(new_home)
  ok=0
  dest="$home/.claude/commands/antz-set-model.md"

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --claude >/dev/null 2>&1 )
  [ -f "$dest" ] || { echo "  setup: file missing after first install"; ok=1; }

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --claude >/dev/null 2>&1 )
  [ -f "$dest" ] || { echo "  file missing after second install"; ok=1; }

  bak_count=$(find "$home/.claude/commands" -name 'antz-set-model.md.bak.*' 2>/dev/null | wc -l | tr -d ' ')
  [ "$bak_count" -eq 0 ] || { echo "  unexpected backup file(s) created on an idempotent re-run"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# command-install-04: a pre-existing, non-antz-managed file at the same path
# is backed up rather than clobbered.
# =============================================================================
test_command_install_04() {
  home=$(new_home)
  ok=0
  mkdir -p "$home/.claude/commands"
  dest="$home/.claude/commands/antz-set-model.md"
  printf 'a user-authored command, not antz-managed\n' > "$dest"

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --claude >/dev/null 2>&1 )

  bak=$(find "$home/.claude/commands" -name 'antz-set-model.md.bak.*' 2>/dev/null | head -n1)
  [ -n "$bak" ] || { echo "  pre-existing unmanaged file was not backed up"; ok=1; }
  [ -n "$bak" ] && { grep -q 'not antz-managed' "$bak" || { echo "  backup does not contain the original content"; ok=1; }; }
  grep -q 'antz:generated' "$dest" 2>/dev/null || { echo "  fresh managed file was not installed after backup"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# command-install-05: plain, flag-less install.sh auto-detects and installs
# this command for whichever client(s) are detected.
# =============================================================================
test_command_install_05() {
  home=$(new_home)
  ok=0
  mkdir -p "$home/.claude"

  ( cd "$SCRIPT_DIR" && HOME="$home" PATH="$NO_CLIENT_CLI_PATH" "$INSTALL_SH" >/dev/null 2>&1 )

  [ -f "$home/.claude/commands/antz-set-model.md" ] || { echo "  claude copy not installed via flag-less detection"; ok=1; }
  [ -f "$home/.config/opencode/commands/antz-set-model.md" ] && { echo "  opencode copy was unexpectedly installed"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-01: adding a model to a Claude Code agent file that has none
# yet, inserted at the fixed frontmatter position.
# =============================================================================
test_set_model_cmd_01() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  grep -qxF 'model: opus' "$dest" || { echo "  missing 'model: opus' line"; ok=1; }

  desc_line=$(grep -n '^description:' "$dest" | head -n1 | cut -d: -f1)
  expected=$(mktemp)
  sed "${desc_line}a\\
model: opus" "$dest.orig" > "$expected"
  cmp -s "$expected" "$dest" || { echo "  file differs from expected (insert after description, before tools)"; ok=1; }
  rm -f "$expected"

  case "$out" in *antz-coder*) ;; *) echo "  reply does not mention antz-coder: $out"; ok=1 ;; esac
  case "$out" in *"model: opus"*) ;; *) echo "  reply does not confirm model: opus: $out"; ok=1 ;; esac

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-02: same, for an OpenCode agent file, at OpenCode's fixed
# position.
# =============================================================================
test_set_model_cmd_02() {
  home=$(new_home)
  dest="$home/.config/opencode/agents/antz-verifier.md"
  write_opencode_fixture "$dest" verifier
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$OPENCODE_SCRIPT" --agent verifier --model anthropic/claude-opus-4-5 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  grep -qxF 'model: anthropic/claude-opus-4-5' "$dest" || { echo "  missing model line"; ok=1; }

  desc_line=$(grep -n '^description:' "$dest" | head -n1 | cut -d: -f1)
  expected=$(mktemp)
  sed "${desc_line}a\\
model: anthropic/claude-opus-4-5" "$dest.orig" > "$expected"
  cmp -s "$expected" "$dest" || { echo "  file differs from expected (insert after description, before mode)"; ok=1; }
  rm -f "$expected"

  case "$out" in *antz-verifier*) ;; *) echo "  reply does not mention antz-verifier: $out"; ok=1 ;; esac
  case "$out" in *"model: anthropic/claude-opus-4-5"*) ;; *) echo "  reply does not confirm the model value: $out"; ok=1 ;; esac

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-03: replacing an already-configured model with a different
# one.
# =============================================================================
test_set_model_cmd_03() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder opus
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model sonnet 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  grep -qxF 'model: sonnet' "$dest" || { echo "  missing 'model: sonnet'"; ok=1; }
  grep -qxF 'model: opus' "$dest" && { echo "  old 'model: opus' line still present"; ok=1; }

  old_line=$(grep -n '^model:' "$dest.orig" | head -n1 | cut -d: -f1)
  expected=$(mktemp)
  sed "${old_line}s/.*/model: sonnet/" "$dest.orig" > "$expected"
  cmp -s "$expected" "$dest" || { echo "  file differs from expected (replace in place, same position)"; ok=1; }
  rm -f "$expected"

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-04: clearing a configured model removes the line entirely.
# =============================================================================
test_set_model_cmd_04() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder opus
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --clear 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  grep -q '^model:' "$dest" && { echo "  'model:' line still present after clear"; ok=1; }

  old_line=$(grep -n '^model:' "$dest.orig" | head -n1 | cut -d: -f1)
  expected=$(mktemp)
  sed "${old_line}d" "$dest.orig" > "$expected"
  cmp -s "$expected" "$dest" || { echo "  file differs from expected (delete only)"; ok=1; }
  rm -f "$expected"

  case "$out" in *[Cc]leared*) ;; *) echo "  reply does not confirm the model was cleared: $out"; ok=1 ;; esac

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-05: clearing when nothing is configured is a harmless no-op.
# =============================================================================
test_set_model_cmd_05() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --clear 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  cmp -s "$dest.orig" "$dest" || { echo "  file changed on a no-op clear"; ok=1; }
  case "$out" in *"no model"*|*"nothing to clear"*) ;; *) echo "  reply does not confirm there was nothing to clear: $out"; ok=1 ;; esac

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-06: refuses to act on an agent that isn't installed yet for
# that client.
# =============================================================================
test_set_model_cmd_06() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?

  [ "$status" -ne 0 ] || { echo "  expected non-zero exit, got 0"; ok=1; }
  case "$out" in *coder*) ;; *) echo "  reply does not mention 'coder': $out"; ok=1 ;; esac
  case "$out" in *claude*) ;; *) echo "  reply does not mention 'claude': $out"; ok=1 ;; esac
  case "$out" in *install.sh*) ;; *) echo "  reply does not mention install.sh: $out"; ok=1 ;; esac
  [ ! -f "$dest" ] || { echo "  a file was created"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-07: refuses to touch a same-named file that isn't
# antz-managed.
# =============================================================================
test_set_model_cmd_07() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_unmanaged_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?

  [ "$status" -ne 0 ] || { echo "  expected non-zero exit, got 0"; ok=1; }
  case "$out" in *antz-managed*) ;; *) echo "  reply does not explain the file is not antz-managed: $out"; ok=1 ;; esac
  cmp -s "$dest.orig" "$dest" || { echo "  unmanaged file was modified"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-08: an unknown agent name is rejected before touching any
# file.
# =============================================================================
test_set_model_cmd_08() {
  home=$(new_home)
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent bogus --model opus 2>&1)
  status=$?

  [ "$status" -ne 0 ] || { echo "  expected non-zero exit, got 0"; ok=1; }
  case "$out" in *Usage*) ;; *) echo "  expected a usage error, got: $out"; ok=1 ;; esac
  for a in specifier coder verifier orchestrator; do
    case "$out" in *"$a"*) ;; *) echo "  reply does not name valid agent '$a': $out"; ok=1 ;; esac
  done
  [ ! -e "$home/.claude/agents/antz-bogus.md" ] || { echo "  a file was written for the bogus agent"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-09 (row: extra-args=""): neither --model nor --clear is a
# usage error, and leaves the target file untouched.
# =============================================================================
test_set_model_cmd_09_neither() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder 2>&1)
  status=$?

  [ "$status" -ne 0 ] || { echo "  expected non-zero exit, got 0"; ok=1; }
  case "$out" in *Usage*) ;; *) echo "  expected a usage error, got: $out"; ok=1 ;; esac
  cmp -s "$dest.orig" "$dest" || { echo "  file was written"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-09 (row: extra-args="--model opus --clear"): both --model
# and --clear together is a usage error, and leaves the target file
# untouched.
# =============================================================================
test_set_model_cmd_09_both() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus --clear 2>&1)
  status=$?

  [ "$status" -ne 0 ] || { echo "  expected non-zero exit, got 0"; ok=1; }
  case "$out" in *Usage*) ;; *) echo "  expected a usage error, got: $out"; ok=1 ;; esac
  cmp -s "$dest.orig" "$dest" || { echo "  file was written"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-10: invoking one client's copy never reads or writes the
# other client's installed file for the same agent -- a structural
# guarantee, since each copy is permanently scoped to its own client.
# =============================================================================
test_set_model_cmd_10() {
  home=$(new_home)
  claude_dest="$home/.claude/agents/antz-coder.md"
  opencode_dest="$home/.config/opencode/agents/antz-coder.md"
  write_claude_fixture "$claude_dest" coder
  write_opencode_fixture "$opencode_dest" coder
  cp "$opencode_dest" "$opencode_dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  grep -qxF 'model: opus' "$claude_dest" || { echo "  claude file did not gain 'model: opus'"; ok=1; }
  cmp -s "$opencode_dest.orig" "$opencode_dest" || { echo "  opencode file for the same agent was touched"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-11: invoking for one agent never touches another agent's
# installed file.
# =============================================================================
test_set_model_cmd_11() {
  home=$(new_home)
  coder_dest="$home/.claude/agents/antz-coder.md"
  specifier_dest="$home/.claude/agents/antz-specifier.md"
  write_claude_fixture "$coder_dest" coder
  write_claude_fixture "$specifier_dest" specifier
  cp "$specifier_dest" "$specifier_dest.orig"
  ok=0

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  grep -qxF 'model: opus' "$coder_dest" || { echo "  coder file did not gain 'model: opus'"; ok=1; }
  cmp -s "$specifier_dest.orig" "$specifier_dest" || { echo "  specifier file was touched"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# set-model-cmd-12: the supplied value is used verbatim -- never validated
# or translated against the target client's syntax.
# =============================================================================
test_set_model_cmd_12() {
  home=$(new_home)
  dest="$home/.config/opencode/agents/antz-coder.md"
  write_opencode_fixture "$dest" coder
  ok=0

  out=$(HOME="$home" "$OPENCODE_SCRIPT" --agent coder --model not-a-real-model 2>&1)
  status=$?

  [ "$status" -eq 0 ] || { echo "  expected exit 0, got $status ($out)"; ok=1; }
  grep -qxF 'model: not-a-real-model' "$dest" || { echo "  value was not written verbatim"; ok=1; }

  rm -rf "$home"
  return $ok
}

# ---- run everything ---------------------------------------------------------

setup_extracted_scripts

run_test "command-install-01: installs the Claude Code copy with expected frontmatter, scoped to claude only" test_command_install_01
run_test "command-install-02: installs the OpenCode copy with no agent: field, scoped to opencode only" test_command_install_02
run_test "command-install-03: re-running install.sh --claude is idempotent (no backup file)" test_command_install_03
run_test "command-install-04: a pre-existing non-antz-managed file at the same path is backed up" test_command_install_04
run_test "command-install-05: flag-less install.sh installs only for the detected client" test_command_install_05

run_test "set-model-cmd-01: adds model: line after description, before tools (Claude Code, no existing model)" test_set_model_cmd_01
run_test "set-model-cmd-02: adds model: line after description, before mode (OpenCode, no existing model)" test_set_model_cmd_02
run_test "set-model-cmd-03: replaces an already-configured model: line in place" test_set_model_cmd_03
run_test "set-model-cmd-04: --clear removes an existing model: line entirely" test_set_model_cmd_04
run_test "set-model-cmd-05: --clear with no existing model: line is a no-op" test_set_model_cmd_05
run_test "set-model-cmd-06: refuses when the agent isn't installed for that client yet" test_set_model_cmd_06
run_test "set-model-cmd-07: refuses to touch a same-named file without the antz:generated marker" test_set_model_cmd_07
run_test "set-model-cmd-08: rejects an unknown agent name, naming the four valid agents, before touching any file" test_set_model_cmd_08
run_test "set-model-cmd-09: usage error when neither --model nor --clear is given (extra-args=\"\")" test_set_model_cmd_09_neither
run_test "set-model-cmd-09: usage error when both --model and --clear are given (extra-args=\"--model opus --clear\")" test_set_model_cmd_09_both
run_test "set-model-cmd-10: invoking the claude copy never touches the opencode file for the same agent" test_set_model_cmd_10
run_test "set-model-cmd-11: invoking for one agent never touches another agent's file" test_set_model_cmd_11
run_test "set-model-cmd-12: the supplied model value is written verbatim, unvalidated" test_set_model_cmd_12

rm -f "$CLAUDE_SCRIPT" "$OPENCODE_SCRIPT"

echo ""
echo "$pass_count passed, $fail_count failed"
[ "$fail_count" -eq 0 ]
