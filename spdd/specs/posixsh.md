# Domain: posixsh

## Origin
- Specced and delivered from change `fix-install-sh-syntax` (merged
  2026-09-10). Before it, no governing spec in `spdd/specs/` covered
  `install.sh`'s shell syntax/portability surface (the domain held only
  `set-model.md`, `specifier-role.md`, and `versioning.md`). The user
  reported `curl | sh` on macOS yielding `sh: line 230: syntax error near
  unexpected token ';;'`: bash 3.2 (macOS `/bin/sh`, POSIX mode) mis-parses
  a heredoc whose body sits inside a command substitution, keeping the body
  as command text. `install.sh` held three instances of the trap
  (`script=$(cat <<'SCRIPT'` at line 204; the two `$(cat <<'PICKER'` sites
  in `render_set_model_command`'s case branches). The fix moved each
  heredoc into a top-level no-argument emitter function
  (`emit_set_model_script`, `emit_picker_claude`, `emit_picker_opencode`)
  captured via `script=$(emit_*)`, which every shell parses. The change's
  scenarios and e2e QA are preserved for history in
  `spdd/archive/fix-install-sh-syntax/`, not reproduced here.

## Goal
`install.sh` parses and runs under the documented `curl -fsSL
https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh`
invocation on every POSIX sh — including macOS's `/bin/sh` (bash 3.2 in
POSIX mode, the parser that chokes on heredoc-in-command-substitution) —
while changing no rendered output or documented behavior anywhere else.

## Shared contracts
- `tests/bash32-sh.sh` provisions-or-surfaces a cached GNU bash 3.2.57
  `bash` binary whose `--posix` parser reproduces macOS `/bin/sh`'s defect
  (heredoc body inside `$(...)`) — verified recipe: pristine bash-3.2.57
  tarball (sha256-pinned), `CC="gcc -std=gnu89"`,
  `CFLAGS="-O1 -std=gnu89 -Wno-implicit-function-declaration
  -Wno-implicit-int"`. Its cache is sanity-fixture-gated on every run: a
  file with the trap construct must fail to parse under the cached binary.
- `tests/installsh-posixsh_test.sh` is the unit suite, one test per
  scenario clause, each reported name carrying its `posixsh-<index>` id.

## Feature: install.sh parses and runs under POSIX sh on macOS (/bin/sh = bash 3.2)

  Background:
    Given install.sh from the repo tree
    And a mechanical scan that finds every construct whose heredoc body is
      captured inside a shell command substitution

  # ADD - posixsh-01
  Scenario: posixsh-01
    Given the mechanical scan over install.sh
    Then it must find exactly zero such constructs
    And every heredoc body in install.sh sits at top level or directly
      inside a function body, never inside a command substitution

  # ADD - posixsh-02
  Scenario: posixsh-02
    When the helper-driven `bash3.2-sh -n install.sh` parse check runs
    Then the parse succeeds with exit status 0 and no syntax-error output
      on stderr
    And the same check against a pre-fix install.sh reproduces the
      reported failure (`syntax error near unexpected token ';;'`) as
      proof the instrument reproduces the macOS failure

  # ADD - posixsh-03
  Scenario: posixsh-03
    When `sh -n install.sh` runs with whatever POSIX sh is on PATH
    Then the parse succeeds with exit status 0 and no output
    And `sh install.sh --check`-style full parse holds; a no-flag run with
      neither client detected exits with a failure status only after
      parsing the whole file, printing the "Neither Claude Code nor
      OpenCode detected." refusal to stderr and writing no file

  # ADD - posixsh-04
  Scenario: posixsh-04
    Given a pre-fix render and a post-fix render of install.sh --all into
      isolated HOME trees
    When the two HOME trees are compared recursively byte-for-byte
    Then every installed file is identical — the four agent files per
      client, both `antz.md` and both `antz-set-model.md` copies, the
      embedded set-model script text including its `for arg do` line, and
      every `antz:generated` marker with its embedded VERSION
    And the console report lines are identical except for the HOME path
      prefixes inside the "Installed <dest>" lines

### Invariants
- The fix is syntax-only: no rendered file, marker, path, flag behavior or
  version string changes (`posixsh-04` is a hard gate).
- The bash 3.2 helper's reproducibility on the pre-fix tree
  (`posixsh-02`'s negative control) is part of the contract, not an
  implementation detail.

### End-to-end QA

  Background:
    Given a local checkout of antz with the change applied
    And isolated HOME directories so QA never touches real "~/.claude" or
      "~/.config/opencode"

  # ADD - e2e-qa-01
  Scenario: e2e-qa-01
    When a user runs `sh install.sh --all` from the checkout with HOME set
      to an isolated empty directory
    Then the exit status is 0
    And the report lists all twelve installs (4 agents x 2 clients, plus
      2 antz.md and 2 antz-set-model.md commands) under the isolated HOME
    And every installed file carries an `antz:generated` marker whose
      embedded VERSION matches the repo's VERSION file
    And the rendered antz-set-model.md command bodies carry the embedded
      set-model script verbatim (including its `for arg do` line)

  # ADD - e2e-qa-02
  Scenario: e2e-qa-02
    When the user's exact macOS invocation is simulated — bash 3.2.57 in
      POSIX mode reading the script from stdin with install.sh piped in:
      `cat install.sh | bash32 --posix -s -- <flags>`
    Then the exit status is 0 and no `syntax error near unexpected token`
      line appears anywhere
    And the same twelve-file install set appears under the isolated HOME,
      byte-identical to the matching file installed by e2e-qa-01

  # ADD - e2e-qa-03
  Scenario: e2e-qa-03
    Given a HOME pre-seeded with the output of e2e-qa-01
    When `bash32 --posix install.sh --check` runs with the two clients'
      files visible through that HOME
    Then the exit status is 0 and no file in the HOME tree changes (no new
      backup copies, no rewrites)
    And the report states the installed antz is already up to date with
      the current VERSION
