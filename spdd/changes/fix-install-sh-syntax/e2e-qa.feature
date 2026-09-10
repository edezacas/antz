Feature: End-to-end QA - install.sh installs for real under POSIX sh, both clients
  # Operates through the real product UI: install.sh's documented CLI
  # (`./install.sh`, `sh install.sh`, flags are UI affordances, same
  # convention as spdd/specs/set-model.md's e2e suite). No internal
  # function calls. All scenarios are ADD against the NEW domain file
  # spdd/specs/posixsh.md at merge; ids start at 01.
  #
  # e2e-qa-02 is the direct reproduction of the user's reported failure and
  # its fix: the user's exact invocation (`curl -fsSL ... | sh` on macOS,
  # i.e. bash 3.2 in POSIX mode reading the script from a pipe) must now
  # succeed.

  Background:
    Given a local checkout of antz with this change applied (install.sh
      carrying the fix and anything else at its pre-change state)
    And isolated HOME directories (for example under
      /tmp/fix-install-sh-syntax) so QA never touches real "~/.claude" or
      "~/.config/opencode"

# ADD - e2e-qa-01: full install under plain POSIX sh on PATH
# Linux behavior to preserve.
Scenario: e2e-qa-01
  Given HOME set to an isolated empty directory
  When a user runs `sh install.sh --all` from the checkout
  Then the exit status is 0
  And the report lines list all twelve installs (4 agents x 2 clients, plus
    2 antz.md and 2 antz-set-model.md commands) under the isolated HOME
  And every installed file carries an `antz:generated` marker whose
    embedded VERSION matches the repo's VERSION file
  And the rendered antz-set-model.md command bodies carry the embedded
    set-model script verbatim (including its `for arg do` line)

# ADD - e2e-qa-02: full install under macOS-fidelity POSIX sh (bash 3.2)
# The helper tests/bash32-sh.sh provisions bash 3.2.57 (recipe in
# posixsh-02); invoking the built binary under the name `sh` with --posix
# (run as `bash32 --posix install.sh` or `cat install.sh | bash32 --posix`)
# reproduces macOS /bin/sh, including reading from a pipe.
Scenario: e2e-qa-02
  Given HOME set to an isolated empty directory
  And the bash 3.2.57 helper binary from tests/bash32-sh.sh
  When the user's exact invocation is simulated -- the built bash 3.2
    binary runs under the name `sh` in POSIX mode reading the script from
    stdin, with install.sh fetched via `curl -fsSL
    https://raw.githubusercontent.com/edezacas/antz/master/install.sh` (or
    an identical local copy) piped in exactly as on macOS:
    `curl -fsSL ... | sh --all` -- concretely `cat install.sh | bash32
    --posix -s --all`
  Then the exit status is 0
  And no `syntax error near unexpected token` line appears anywhere
  And the same twelve-file install set appears under the isolated HOME
  And every installed file is byte-identical to the matching file installed
    by posix sh on PATH in e2e-qa-01

# ADD - e2e-qa-03: --check mode stays a no-writer report under macOS-fidelity sh
Scenario: e2e-qa-03
  Given HOME set to an isolated empty directory containing a pre-seeded
    installed agent tree (the output of e2e-qa-01), and the bash 3.2.57
    helper binary on call
  When `bash32 --posix install.sh --check` runs with the two clients' files
    visible through that HOME
  Then the exit status is 0, no file in the HOME tree changes (no new
    backup copies, no rewrites)
  And the report states the installed antz is already up to date with the
    current VERSION
