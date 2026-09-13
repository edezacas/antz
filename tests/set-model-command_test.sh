#!/usr/bin/env bash
# Unit tests for install.sh's /antz-set-model command (rendering/install
# side) and the self-contained script embedded in its body (invocation
# side), covering every scenario in
# spdd/changes/set-model-native-command/01-set-model-command.feature, the
# unit-testable (rendering-level) scenarios in
# spdd/changes/set-model-interactive-picker/01-interactive-picker.feature,
# and the embedded-script hardening scenarios setmodel-01..04 in
# spdd/changes/hardening-installsh/04-setmodel.feature (anchored
# line-start header-marker check + mktemp cleanup trap).
#
# Self-contained bash test harness (no external framework/dependency -- this
# repo has no package manager or build system). Run directly:
#   ./tests/set-model-command_test.sh
#
# Each reported test name embeds its scenario id (command-install-01..06,
# set-model-cmd-01..12, picker-render-01..05, setmodel-01..04) from the
# feature files above,
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

write_midbody_marker_fixture() {
  # setmodel-01 (hardening-installsh sub-spec 04): a same-named file that
  # mentions "antz:generated" ONLY mid-body -- never as a line-start
  # "# antz:generated " header comment -- so it is NOT antz-managed under the
  # change's shared header-marker contract. The unanchored marker check
  # accepted exactly this file; the anchored line-start check must refuse it
  # untouched. The indented variant probes that the anchor (not merely a
  # "# " prefix) is what does the work.
  dest="$1"; agent="$2"
  mkdir -p "$(dirname "$dest")"
  {
    echo '---'
    echo "name: antz-$agent"
    echo "description: A user's own hand-written agent that mentions the marker."
    echo 'tools: Read'
    echo '---'
    echo ''
    echo "Body text for $agent."
    echo 'Docs say generated files carry antz:generated markers; this mentions it mid-line.'
    echo '  # antz:generated version=0.0.0 -- indented mention, never a line-start header'
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
# command-install-06: the emitted command body must be free of client-
# substitutable tokens -- both clients template the command body at invocation
# time, replacing every dollar-digit token plus the ARGUMENTS placeholder
# (OpenCode rewrites /\$\d+/g matches and turns missing positionals into the
# literal string "undefined"; Claude Code rewrites $1/$2/.../$ARGUMENTS) --
# code fences included. The embedded script's original positional-param/awk
# form was corrupted exactly this way before it ever ran, so the emitted body
# may contain no dollar-digit token at all, and the ARGUMENTS placeholder
# only where it is the intended injection point (the flow head's
# "Arguments:" line).
# =============================================================================
test_command_install_06() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --all >/dev/null 2>&1 )

  for dest in "$home/.claude/commands/antz-set-model.md" "$home/.config/opencode/commands/antz-set-model.md"; do
    if grep -qE '\$[0-9]' "$dest"; then
      echo "  $dest contains a dollar-digit token the client would substitute at invocation time:"
      grep -nE '\$[0-9]' "$dest" | head -n5
      ok=1
    fi
    arg_lines=$(grep -c 'ARGUMENTS' "$dest")
    [ "$arg_lines" -eq 1 ] \
      || { echo "  $dest expected exactly the one intended ARGUMENTS placeholder line, found $arg_lines"; ok=1; }
    grep -q '^Arguments: \$ARGUMENTS$' "$dest" \
      || { echo "  $dest missing the intended 'Arguments: \$ARGUMENTS' injection line"; ok=1; }
  done

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

# =============================================================================
# setmodel-01 (hardening-installsh/04-setmodel.feature, MODIFY): the embedded
# script's managed-file check is anchored to the line-start header marker. A
# header-marked fixture behaves exactly as before (model line at the fixed
# position, success reply); a fixture that only mentions "antz:generated"
# mid-body is refused with the existing not-antz-managed error, exits
# non-zero, and is left byte-for-byte unchanged.
# =============================================================================
test_setmodel_01() {
  home=$(new_home)
  ok=0

  # (a) Header-marked fixture: accepted, model gained at the fixed position.
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?
  [ "$status" -eq 0 ] || { echo "  header-marked run exited $status ($out)"; ok=1; }
  grep -qxF 'model: opus' "$dest" || { echo "  header-marked file did not gain 'model: opus'"; ok=1; }
  desc_line=$(grep -n '^description:' "$dest" | head -n1 | cut -d: -f1)
  expected=$(mktemp)
  sed "${desc_line}a\\
model: opus" "$dest.orig" > "$expected"
  cmp -s "$expected" "$dest" || { echo "  header-marked file differs from expected (insert after description, before tools)"; ok=1; }
  rm -f "$expected"
  case "$out" in *"now has model: opus"*) ;; *) echo "  reply does not confirm success: $out"; ok=1 ;; esac

  # (b) Mid-body-mention-only fixture: refused as not antz-managed, untouched.
  mid="$home/.claude/agents/antz-specifier.md"
  write_midbody_marker_fixture "$mid" specifier
  cp "$mid" "$mid.orig"

  out=$(HOME="$home" "$CLAUDE_SCRIPT" --agent specifier --model opus 2>&1)
  status=$?
  [ "$status" -ne 0 ] || { echo "  mid-body-mention file was accepted (exit 0)"; ok=1; }
  case "$out" in *"not antz-managed"*) ;; *) echo "  refusal is not the existing not-antz-managed error: $out"; ok=1 ;; esac
  cmp -s "$mid.orig" "$mid" || { echo "  mid-body-mention file was modified"; ok=1; }

  rm -rf "$home"
  return $ok
}

# =============================================================================
# setmodel-02 (ADD): the mktemp scratch file is cleaned up on every normal
# exit path -- a successful set, a successful clear, and the nothing-to-clear
# no-op -- with each run exiting 0 and printing its documented reply, and no
# file left behind in the isolated TMPDIR.
# =============================================================================
test_setmodel_02() {
  home=$(new_home)
  tmpdir=$(mktemp -d)
  ok=0

  leftover() {
    if [ -n "$(find "$tmpdir" -mindepth 1 -print -quit)" ]; then
      echo "  $1: leftover scratch file(s) in TMPDIR: $(find "$tmpdir" -mindepth 1)"
      return 0
    fi
    return 1
  }

  # (1) Successful set.
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  out=$(HOME="$home" TMPDIR="$tmpdir" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?
  [ "$status" -eq 0 ] || { echo "  set run exited $status ($out)"; ok=1; }
  case "$out" in *"now has model: opus"*) ;; *) echo "  set reply not as documented: $out"; ok=1 ;; esac
  grep -qxF 'model: opus' "$dest" || { echo "  set run did not write the model line (trap removed the wrong file?)"; ok=1; }
  leftover "after the set run" && ok=1

  # (2) Successful clear on a configured file.
  out=$(HOME="$home" TMPDIR="$tmpdir" "$CLAUDE_SCRIPT" --agent coder --clear 2>&1)
  status=$?
  [ "$status" -eq 0 ] || { echo "  clear run exited $status ($out)"; ok=1; }
  case "$out" in *[Cc]leared*) ;; *) echo "  clear reply not as documented: $out"; ok=1 ;; esac
  grep -q '^model:' "$dest" && { echo "  clear run left the model line (trap removed the wrong file?)"; ok=1; }
  leftover "after the clear run" && ok=1

  # (3) Nothing-to-clear no-op on an unconfigured file (never creates one).
  dest2="$home/.claude/agents/antz-verifier.md"
  write_claude_fixture "$dest2" verifier
  cp "$dest2" "$dest2.orig"
  out=$(HOME="$home" TMPDIR="$tmpdir" "$CLAUDE_SCRIPT" --agent verifier --clear 2>&1)
  status=$?
  [ "$status" -eq 0 ] || { echo "  nothing-to-clear run exited $status ($out)"; ok=1; }
  case "$out" in *"nothing to clear"*) ;; *) echo "  no-op reply not as documented: $out"; ok=1 ;; esac
  cmp -s "$dest2.orig" "$dest2" || { echo "  no-op clear changed the file"; ok=1; }
  leftover "after the nothing-to-clear run" && ok=1

  rm -rf "$home" "$tmpdir"
  return $ok
}

# =============================================================================
# setmodel-03 (ADD): the cleanup holds on failure too -- a read-only target
# makes the rewrite die mid-run; the script exits non-zero, the target is
# byte-for-byte unchanged, and no scratch file survives in TMPDIR. The
# failure mechanism (permission bits) cannot bind for uid 0, so the test
# skips explicitly when run as root (environmental, same pattern as
# posixsh-02's provision-failure skip).
# =============================================================================
test_setmodel_03() {
  if [ "$(id -u)" -eq 0 ]; then
    SETMODEL_03_SKIP="running as uid 0: a read-only file does not block root's writes"
    echo "  $SETMODEL_03_SKIP"
    return 1
  fi
  home=$(new_home)
  tmpdir=$(mktemp -d)
  dest="$home/.claude/agents/antz-coder.md"
  write_claude_fixture "$dest" coder
  cp "$dest" "$dest.orig"
  chmod 555 "$dest"
  ok=0

  out=$(HOME="$home" TMPDIR="$tmpdir" "$CLAUDE_SCRIPT" --agent coder --model opus 2>&1)
  status=$?
  chmod 644 "$dest"

  [ "$status" -ne 0 ] || { echo "  expected non-zero exit when the rewrite write fails, got 0 ($out)"; ok=1; }
  cmp -s "$dest.orig" "$dest" || { echo "  target was modified by the failed run (trap must never remove/rewrite the target)"; ok=1; }
  if [ -n "$(find "$tmpdir" -mindepth 1 -print -quit)" ]; then
    echo "  leftover scratch file(s) in TMPDIR after the failed run: $(find "$tmpdir" -mindepth 1)"
    ok=1
  fi

  rm -rf "$home" "$tmpdir"
  return $ok
}

# =============================================================================
# setmodel-04 (ADD): the emitted script's token constraint survives the
# anchored check + trap changes -- the embedded script in each client's
# rendered command body carries no dollar-digit token and no $ARGUMENTS
# sequence (the corruption class command-install-06 guards against), the
# script still parses as POSIX sh, and each command body keeps exactly the
# one intended "Arguments: $ARGUMENTS" injection line.
# =============================================================================
test_setmodel_04() {
  home=$(new_home)
  ok=0

  ( cd "$SCRIPT_DIR" && HOME="$home" "$INSTALL_SH" --all >/dev/null 2>&1 )

  for cmd_file in "$home/.claude/commands/antz-set-model.md" "$home/.config/opencode/commands/antz-set-model.md"; do
    [ -f "$cmd_file" ] || { echo "  $cmd_file missing"; ok=1; continue; }
    embedded=$(mktemp)
    extract_script "$cmd_file" > "$embedded"
    if grep -qE '\$[0-9]' "$embedded"; then
      echo "  embedded script of $cmd_file contains a dollar-digit token:"
      grep -nE '\$[0-9]' "$embedded" | head -n5
      ok=1
    fi
    grep -qF '$ARGUMENTS' "$embedded" && { echo "  embedded script of $cmd_file contains a \$ARGUMENTS sequence"; ok=1; }
    sh -n "$embedded" || { echo "  embedded script of $cmd_file fails sh -n (not POSIX-parseable)"; ok=1; }
    rm -f "$embedded"
    arg_lines=$(grep -cF '$ARGUMENTS' "$cmd_file")
    [ "$arg_lines" -eq 1 ] \
      || { echo "  $cmd_file carries $arg_lines \$ARGUMENTS occurrences, expected exactly the one injection line"; ok=1; }
    grep -qxF 'Arguments: $ARGUMENTS' "$cmd_file" \
      || { echo "  $cmd_file missing the intended 'Arguments: \$ARGUMENTS' injection line"; ok=1; }
  done

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
run_test "command-install-06: emitted bodies carry no client-substitutable dollar-digit tokens; ARGUMENTS placeholder appears exactly once, as the injection point" test_command_install_06

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

# ---- hardening-installsh sub-spec 04: embedded-script scenarios ------------

run_test "setmodel-01: embedded script's managed check is anchored to the line-start header marker (header fixture accepted at the fixed position; mid-body-mention-only fixture refused as not antz-managed, exit non-zero, byte-for-byte unchanged)" test_setmodel_01
run_test "setmodel-02: no mktemp scratch left in TMPDIR after a successful set, a successful clear, or the nothing-to-clear no-op (each exits 0 with its documented reply)" test_setmodel_02
run_test "setmodel-03: mid-run rewrite failure (read-only target) exits non-zero, leaves the target byte-for-byte unchanged, and the cleanup trap removes the scratch file" test_setmodel_03
if [ -n "${SETMODEL_03_SKIP:-}" ]; then
  # The uid-0 case: downgrade the FAIL run_test just counted into an explicit
  # SKIP stub (environmental limitation of the failure mechanism, not a code
  # failure and not a BLOCKED refusal -- same pattern as posixsh-02's).
  fail_count=$((fail_count - 1))
  echo "SKIP: setmodel-03: mid-run rewrite failure leaves the target unchanged and no scratch behind (${SETMODEL_03_SKIP})"
  skip_count=$((skip_count + 1))
  unset SETMODEL_03_SKIP
fi
run_test "setmodel-04: emitted script survives the changes token-free (no dollar-digit, no \$ARGUMENTS in either embedded script, POSIX-parseable), each body keeps exactly the one 'Arguments: \$ARGUMENTS' injection line" test_setmodel_04

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
