Feature: install.sh parses and runs under POSIX sh on macOS (/bin/sh = bash 3.2)
  # Layer: repo install mechanics (install.sh itself). This is a NEW spec
  # domain: no governing spec in spdd/specs/ covers install.sh's shell
  # syntax/portability surface (spdd/specs/ holds set-model.md,
  # specifier-role.md, versioning.md; none specify parseability). From the
  # user's report ("curl | sh" on Mac yields
  # `sh: line 230: syntax error near unexpected token ';;'`), the reproduced
  # root cause (bash 3.2.57 -- my build parsed identically to macOS /bin/sh)
  # is: bash 3.2's parser mis-reads a heredoc whose body sits inside a
  # command substitution -- `script=$(cat <<'SCRIPT' ... SCRIPT)` -- and
  # keeps parsing the heredoc body as command text, so the first `;;` in
  # that body (install.sh line 230, the set-model argument loop) surfaces as
  # the reported error. Line 230 is text quoted inside a heredoc, never
  # code. install.sh contains three instances of the trap: line 204
  # (set_model_script's `script=$(cat <<'SCRIPT'`) and lines 424/448 (both
  # `$(cat <<'PICKER'` sites in render_set_model_command's two case
  # branches). Validated fix shape: move each heredoc into its own
  # top-level, no-argument emitter function and write
  # `script=$(emit_set_model_script)` etc. -- capturing a function's stdout
  # inside $(...) is plain POSIX and parses fine in bash 3.2.
  # Byte-identical rendered output was verified in this investigation.
  #
  # posixsh-01..04 are all ADD against the NEW domain file
  # spdd/specs/posixsh.md (created by the verifier at merge). The coder's
  # unit-level test suite tags every test name with its posixsh-<index> id.

  Background:
    Given install.sh from the working root of this change
    And a mechanical scan that finds every construct whose heredoc body is
      captured inside a shell command substitution, i.e. exactly the
      pattern "<var>=$(cat <<'DELIM'" ... "DELIM" ")" spanning lines

# ADD - posixsh-01: no heredoc inside a command substitution
# This construct class is what bash 3.2's parser breaks on; barring it
# mechanically keeps the fix durable without needing a macOS machine.
Scenario: posixsh-01
  Given the mechanical scan over install.sh
  Then it must find exactly zero constructs
  And every heredoc body in install.sh sits at top level or directly inside
    a function body, never inside a command substitution

# ADD - posixsh-02: parse clean under macOS-fidelity POSIX sh
# The helper tests/bash32-sh.sh (created by the coder) provisions or
# surfaces a cached bash 3.2.57 build whose --posix invocation reproduces
# macOS /bin/sh's parser defect; build recipe:
# GNU bash 3.2.57 sources, CC="gcc -std=gnu89",
# CFLAGS="-O1 -std=gnu89 -Wno-implicit-function-declaration".
Scenario: posixsh-02
  Given install.sh drifted-or-fixed by the working root's tree
  When the helper-driven `bash3.2-sh -n install.sh` parse check runs
  Then the parse succeeds with exit status 0 and no syntax-error output on
    stderr
  And running the same check against the base commit's install.sh reproduces
    the reported failure (syntax error near unexpected token `;;') as proof
    the instrument reproduces the macOS failure

# ADD - posixsh-03: parse and execute clean under plain POSIX sh on PATH
# Existing Linux behavior, asserted so it survives the fix.
Scenario: posixsh-03
  Given whatever POSIX sh is on PATH (Linux bash-as-sh or dash)
  When `sh -n install.sh` runs
  Then the parse succeeds with exit status 0 and no output
  And `sh install.sh --check` with no flags and neither client detected
    exits with a failure status only after parsing the whole file, printing
    the "Neither Claude Code nor OpenCode detected." refusal to stderr and
    writing no file

# ADD - posixsh-04: rendered output is byte-identical to the pre-fix render
# The fix is syntax-only: no rendered file, marker, path, flag behavior or
# version string may change as a side effect.
Scenario: posixsh-04
  Given a pre-fix render captured by running the base commit's install.sh
    with --all into an isolated HOME, and a post-fix render captured the
    same way into a second isolated HOME
  When the two HOME trees are compared recursively byte-for-byte
  Then every installed file is identical: the four agent files (antz
    specifier/coder/verifier/orchestrator) under "$HOME/.claude/agents" and
    "$HOME/.config/opencode/agents", "$HOME/.claude/commands/antz.md",
    "$HOME/.config/opencode/commands/antz.md", and both antz-set-model.md
    command copies -- including the heredoc-emitted set-model script text
    (its `for arg do` line stays) and every antz:generated marker with its
    embedded VERSION, all unchanged
  And the console report lines are identical except for the HOME path
    prefixes inside the "Installed <dest>" lines
