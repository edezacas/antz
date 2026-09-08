#!/usr/bin/env bash
# Unit tests for install.sh's /antz-set-model command (rendering/install
# side) and the self-contained script embedded in its body (invocation
# side), covering every scenario in
# spdd/changes/set-model-native-command/01-set-model-command.feature and the
# unit-testable (rendering-level) scenarios in
# spdd/changes/set-model-interactive-picker/01-interactive-picker.feature.
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system). Run directly:
#   ./tests/set-model-command_test.sh
#
# Each reported test name embeds its scenario id (command-install-01..05,
# set-model-cmd-01..12, picker-render-01..05) from the feature files above,
# so a failure maps straight back to the scenario it covers. Every test that
# touches the filesystem runs against an isolated $HOME (a fresh temp dir
# per test), so tests never touch the real ~/.claude or ~/.config/opencode
# directories and never interfere with each other.
#
# The command-level interactive-picker scenarios (picker-cmd-01..13,
# picker-claude-01..03, picker-opencode-01..04) are observable only in a
# live client session (question-asking), so the sub-spec's Verification
# levels assign them to end-to-end verification (e2e-qa.feature, run by the
# verifier), not to this suite. They appear below as explicit SKIP stubs so
# no scenario id is silently unaccounted for.

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_SH="$SCRIPT_DIR/install.sh"

pass_count=0
fail_count=0
skip_count=0

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

skip_test() {
  # $1 = reported test name (must contain its scenario id), $2 = reason.
  # An explicit, accounted-for stub for a scenario that is out of scope for
  # unit-level TDD (never a silent omission).
  name="$1"; reason="$2"
  echo "SKIP: $name ($reason)"
  skip_count=$((skip_count + 1))
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
# command-install-01 (MODIFIED by set-model-interactive-picker): install.sh
# installs the Claude Code copy with the expected frontmatter shape -- the
# argument-hint now shows the --model/--clear group as optional (the no-flag
# form is the interactive picker), the description says so, and the body
# carries the pre-flight + interactive-picker instructions alongside the
# embedded script and the relay rule.
# =============================================================================
test_command_install_01() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --claude >/dev/null 2>&1 )
  dest="$home/.claude/commands/antz-set-model.md"

  [ -f "$dest" ] || { echo "  $dest was not created"; ok=1; }
  grep -q 'antz:generated version=' "$dest" || { echo "  missing antz:generated marker with version"; ok=1; }
  grep -q '^description:' "$dest" || { echo "  missing description: field"; ok=1; }
  grep -qi 'interactive model picker' "$dest" || { echo "  description does not mention the interactive picker"; ok=1; }
  grep -qxF 'argument-hint: --agent <specifier|coder|verifier|orchestrator> [--model <value>|--clear]' "$dest" \
    || { echo "  missing expected argument-hint line (--model/--clear group shown as optional)"; ok=1; }
  grep -q 'Pre-flight' "$dest" || { echo "  body missing the pre-flight instructions"; ok=1; }
  grep -q 'AskUserQuestion' "$dest" || { echo "  body missing the interactive-picker instructions (AskUserQuestion)"; ok=1; }
  grep -q '^```sh$' "$dest" || { echo "  body missing the embedded script fence"; ok=1; }
  grep -qF 'exactly what the script printed' "$dest" || { echo "  body missing the relay rule"; ok=1; }
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
# picker-render-01: the Claude Code copy embeds the full documented alias
# vocabulary at install time (refreshed only by re-running install.sh, never
# queried at runtime), and does not instruct any runtime enumeration.
# =============================================================================
test_picker_render_01() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --claude >/dev/null 2>&1 )
  dest="$home/.claude/commands/antz-set-model.md"

  for alias in 'best' 'fable' 'opus' 'sonnet' 'haiku' 'sonnet[1m]' 'opus[1m]' 'opusplan'; do
    grep -qF "$alias" "$dest" || { echo "  body missing embedded alias vocabulary value: $alias"; ok=1; }
  done
  grep -qF 'refreshed only by re-running install.sh' "$dest" || { echo "  body does not state the list is refreshed only by re-running install.sh"; ok=1; }
  grep -qF 'never queried at runtime' "$dest" || { echo "  body does not state the list is never queried at runtime"; ok=1; }
  if grep -qi 'opencode models' "$dest"; then echo "  body references OpenCode's enumeration command"; ok=1; fi
  if grep -qi 'enumerate' "$dest"; then echo "  body instructs (or mentions) runtime enumeration"; ok=1; fi

  rm -rf "$home"
  return $ok
}

# =============================================================================
# picker-render-02: the OpenCode copy embeds no model catalog; it instructs
# the session to enumerate models at invocation time via "opencode models"
# through the Bash tool.
# =============================================================================
test_picker_render_02() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --opencode >/dev/null 2>&1 )
  dest="$home/.config/opencode/commands/antz-set-model.md"

  grep -qF 'opencode models' "$dest" || { echo "  body does not instruct running 'opencode models'"; ok=1; }
  grep -qF 'Bash tool' "$dest" || { echo "  body does not run the enumeration via the Bash tool"; ok=1; }
  grep -qF 'provider/model' "$dest" || { echo "  body does not describe the enumerated provider/model ids"; ok=1; }
  # No embedded, hardcoded model list: none of the Claude Code vocabulary may leak in.
  for alias in 'fable' 'opusplan' 'sonnet[1m]' 'haiku'; do
    if grep -qF "$alias" "$dest"; then echo "  body embeds hardcoded model vocabulary: $alias"; ok=1; fi
  done

  rm -rf "$home"
  return $ok
}

# =============================================================================
# picker-render-03: each copy instructs its own client's native question
# mechanism, and the never-delegate rule is preserved verbatim in both.
# =============================================================================
test_picker_render_03() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --all >/dev/null 2>&1 )
  claude_dest="$home/.claude/commands/antz-set-model.md"
  opencode_dest="$home/.config/opencode/commands/antz-set-model.md"

  grep -qF 'AskUserQuestion' "$claude_dest" || { echo "  claude body does not instruct asking via AskUserQuestion"; ok=1; }
  grep -qF 'in this session' "$claude_dest" || { echo "  claude body does not ask in this session"; ok=1; }
  grep -qF '`question` tool' "$opencode_dest" || { echo "  opencode body does not instruct asking via the session's question tool"; ok=1; }
  for dest in "$claude_dest" "$opencode_dest"; do
    grep -qF 'does not delegate to any of the four antz-* subagents' "$dest" \
      || { echo "  $dest lost the never-delegate rule"; ok=1; }
  done

  rm -rf "$home"
  return $ok
}

# =============================================================================
# picker-render-04: the embedded script's exactly-one contract survives
# untouched (backstop for direct invocation), and the body instructs the
# session to invoke the script only with one of --model/--clear.
# =============================================================================
test_picker_render_04() {
  home=$(new_home)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  ok=0

  # The embedded script from the installed claude copy still refuses the
  # script-level "neither" and "both" invocations with a usage message.
  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder 2>&1)
  status=$?
  [ "$status" -ne 0 ] || { echo "  script accepted neither --model nor --clear"; ok=1; }
  case "$out" in *Usage*) ;; *) echo "  'neither' refusal is not a usage message: $out"; ok=1 ;; esac

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus --clear 2>&1)
  status=$?
  [ "$status" -ne 0 ] || { echo "  script accepted both --model and --clear"; ok=1; }
  case "$out" in *Usage*) ;; *) echo "  'both' refusal is not a usage message: $out"; ok=1 ;; esac
  cmp -s "$dest.orig" "$dest" || { echo "  file was written by a refused invocation"; ok=1; }

  # The body instructs the session to invoke the script only with exactly one
  # of the two flags.
  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --claude >/dev/null 2>&1 )
  command_dest="$home/.claude/commands/antz-set-model.md"
  grep -qF 'Never invoke the script without exactly one of' "$command_dest" \
    || { echo "  body missing the exactly-one invocation rule"; ok=1; }
  grep -qFe '--agent <agent> --model <chosen>' "$command_dest" \
    || { echo "  body missing the '--agent <agent> --model <chosen>' invocation form"; ok=1; }
  grep -qFe '--agent <agent> --clear' "$command_dest" \
    || { echo "  body missing the '--agent <agent> --clear' invocation form"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# picker-render-05: each client's body states the fail-fast ordering --
# validate arguments, confirm the target file exists and carries the marker,
# read the current model: line -- all before any question, with refusal and
# no question when validation or the pre-flight fails.
# =============================================================================
test_picker_render_05() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --all >/dev/null 2>&1 )

  for dest in "$home/.claude/commands/antz-set-model.md" "$home/.config/opencode/commands/antz-set-model.md"; do
    grep -qF 'before asking any question' "$dest" || { echo "  $dest missing the before-asking ordering"; ok=1; }
    grep -qF 'usage error' "$dest" || { echo "  $dest missing the argument validation list"; ok=1; }
    grep -qF 'unknown options' "$dest" || { echo "  $dest missing unknown options among the usage errors"; ok=1; }
    grep -qF 'carries the `antz:generated` marker' "$dest" || { echo "  $dest missing the marker pre-flight check"; ok=1; }
    grep -qF 'current frontmatter `model:` line' "$dest" || { echo "  $dest missing the current-model read"; ok=1; }
    grep -qF 'without asking any question' "$dest" || { echo "  $dest missing the refuse-without-asking rule"; ok=1; }
  done

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

run_test "command-install-01: installs the Claude Code copy with expected frontmatter (optional --model/--clear group, picker body), scoped to claude only" test_command_install_01
run_test "command-install-02: installs the OpenCode copy with no agent: field, scoped to opencode only" test_command_install_02
run_test "command-install-03: re-running install.sh --claude is idempotent (no backup file)" test_command_install_03
run_test "command-install-04: a pre-existing non-antz-managed file at the same path is backed up" test_command_install_04
run_test "command-install-05: flag-less install.sh installs only for the detected client" test_command_install_05

run_test "picker-render-01: claude body embeds the full documented alias vocabulary, refreshed only by re-running install.sh" test_picker_render_01
run_test "picker-render-02: opencode body enumerates via 'opencode models' through the Bash tool, with no embedded catalog" test_picker_render_02
run_test "picker-render-03: each body instructs its own native question mechanism; never-delegate rule preserved in both" test_picker_render_03
run_test "picker-render-04: embedded script's exactly-one contract unchanged; body invokes the script only with --model or --clear" test_picker_render_04
run_test "picker-render-05: both bodies state the fail-fast ordering (validate, marker pre-flight, read current model) before any question" test_picker_render_05

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

# ---- command-level interactive-picker scenarios: e2e-only -------------------
# Observable only in a live client session (question-asking); the sub-spec's
# Verification levels assign them to the verifier's end-to-end QA suite
# (spdd/changes/set-model-interactive-picker/e2e-qa.feature), not to this
# unit suite. Explicit SKIP stubs so every scenario id is accounted for.

E2E_REASON="e2e-only: observable only in a live client session (verifier's e2e-qa.feature)"

skip_test "picker-cmd-01: interactive request for a not-installed agent is refused before any question" "$E2E_REASON"
skip_test "picker-cmd-02: interactive request targeting a non-antz-managed file is refused before any question" "$E2E_REASON"
skip_test "picker-cmd-03: unknown agent name is a usage error before any question" "$E2E_REASON"
skip_test "picker-cmd-04: malformed arguments are usage errors before any question (4 example rows: empty, --bogus, dangling --model, dangling --agent)" "$E2E_REASON"
skip_test "picker-cmd-05: both --model and --clear is a usage error before any question" "$E2E_REASON"
skip_test "picker-cmd-06: explicit --model bypasses the picker, script runs with the given value" "$E2E_REASON"
skip_test "picker-cmd-07: explicit --clear bypasses the picker" "$E2E_REASON"
skip_test "picker-cmd-08: picker question states the currently configured model and marks the matching option" "$E2E_REASON"
skip_test "picker-cmd-09: picker question states when no model is configured, marks no option" "$E2E_REASON"
skip_test "picker-cmd-10: chosen listed option feeds the same embedded script as --model, reply relayed verbatim" "$E2E_REASON"
skip_test "picker-cmd-11: 'revert to default (clear)' option maps to the script's --clear" "$E2E_REASON"
skip_test "picker-cmd-12: free-form answer passed to the script verbatim, unvalidated" "$E2E_REASON"
skip_test "picker-cmd-13: dismissed/empty answer cancels; nothing written, reply states nothing changed" "$E2E_REASON"
skip_test "picker-claude-01: question asked via AskUserQuestion in the invoking main session; no antz-* subagent" "$E2E_REASON"
skip_test "picker-claude-02: exactly four explicit options (sonnet, opus, haiku, clear) in order; remaining vocabulary named for free-form entry" "$E2E_REASON"
skip_test "picker-claude-03: clear option maps to the script's --clear, removing the model: line" "$E2E_REASON"
skip_test "picker-opencode-01: models enumerated at invocation time via 'opencode models'; question via the question tool" "$E2E_REASON"
skip_test "picker-opencode-02: large catalog may be filtered/grouped, free-form and clear options always remain offered" "$E2E_REASON"
skip_test "picker-opencode-03: explicit 'type another value' free-form option alongside the clear option" "$E2E_REASON"
skip_test "picker-opencode-04: enumeration failure degrades to free-form + clear, question states no models could be enumerated" "$E2E_REASON"

rm -f "$CLAUDE_SCRIPT" "$OPENCODE_SCRIPT"

echo ""
echo "$pass_count passed, $fail_count failed, $skip_count skipped (e2e-only, see e2e-qa.feature)"
[ "$fail_count" -eq 0 ]
