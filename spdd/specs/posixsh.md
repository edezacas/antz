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
- Extended by change `optimize-test-suite` (merged 2026-09-14): adds four
  posixshfix scenarios (ADD `posixshfix-01..04`) verifying that posixsh-04
  is re-keyed to a direct inventory of the current install.sh's console
  report (no base-vs-working diff, no git-HEAD comparison), the base-
  extraction machinery is removed, and the retained suite is free of
  history/evolution calibration and prose pins. The change's scenarios and
  end-to-end QA are preserved for history in
  `spdd/archive/optimize-test-suite/`, not reproduced here.

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
  # Re-scoped by change `deembed-orchestration-scripts` (setmodeldeembed-05):
  # the "for arg do" assertion moves from command bodies to the installed
  # libdir file; the inventory gains the four libdir files.
  # Re-keyed by change `optimize-test-suite` (posixshfix-01): the console
  # half now asserts the fresh render against the documented line inventory
  # and order, from the current install.sh alone, with no base-vs-working
  # diff and no comparison-derived line count.
  Scenario: posixsh-04
    Given a fresh hermetic --all render of the current install.sh into an
      isolated HOME tree
    When the console report is read
    Then it matches the documented line inventory in order: two client
      status lines, four script-artifact report lines, twelve client
      "Installed" lines, and four libdir "Installed" lines
    And every installed file is identical — the four agent files per
      client, both `antz.md` and both `antz-set-model.md` copies, the
      installed `antz-set-model.sh` file including its `for arg do` line,
      and every `antz:generated` marker with its embedded VERSION

  ## Feature: the posixsh suite tests only the current version; posixsh-04
  # re-keys to direct inventories (from optimize-test-suite)

  Background:
    Given install.sh's fresh hermetic --all console report
    And a fresh render's HOME tree, which is exactly the sixteen documented
      files (twelve client files plus the four libdir scripts)
    And that the suite's renders go through the harness library's render
      helper

  # ADD - posixshfix-01: the console half asserts the report inventory
  # directly.
  Scenario: posixshfix-01
    When posixsh-04's console half runs
    Then it asserts the fresh render's report against the documented line
      inventory and order
    And its expectation derives only from the current install.sh and that
      inventory — no second render of any other source, no base-vs-working
      diff
    And the empty-diff count bug cannot recur: no diff-derived line count
      remains anywhere in the suite

  # ADD - posixshfix-02: the base machinery and the tree-identity
  # registration retire.
  Scenario: posixshfix-02
    When the posixsh suite runs
    Then the tree-identity registration is gone: it byte-compared two
      renders of install.sh, an assertion about a second version the
      current-version-only suite no longer has; its real coverage — the
      sixteen-file tree — is pinned by the render and libdir suites
    And every render in the suite renders the current install.sh, and the
      base-extraction helpers (base_install_sh, prep_base_if_distinct,
      base_install_file) are gone from the suite
    And with them the base-derived clauses retire: posixsh-01's scan keeps
      its synthetic-fixture pin and drops the historical-fidelity clause,
      and posixsh-02's negative control is carried by the synthetic trap
      fixture alone
    And posixsh-01..03 keep their ids and registrations, green, otherwise
      unchanged

  # ADD - posixshfix-03: the suite is green with the retained id.
  Scenario: posixshfix-03
    When the posixsh suite runs
    Then it exits 0 with every registered id green
    And the retained posixsh-04 id keeps its name, now with the single
      console-inventory registration

  # ADD - posixshfix-04: the retained suite is free of git-HEAD and prose
  # pins.
  Scenario: posixshfix-04
    When the retained suite's source is scanned
    Then it contains no real-tree-vs-git-HEAD comparison — no
      `git merge-base`, no `show HEAD:`, no `diff --quiet HEAD`, no `cmp`
      against git-extracted content — and no byte-pin against HEAD
    And it contains no exact-phrase prose assertion of prompts or docs;
      assertions on install.sh itself and on installed product files are
      not prose pins

  ### Invariants
  - This is a re-key, not a deletion-to-hide: the console report's shape is
    now pinned more strongly (a complete ordered inventory) than the old diff
    allowed, and the tree coverage lives in its owning suites.
  - The suite keeps its parse halves (posixsh-01..03) with their ids; only
    the base-derived clauses inside them retire, the synthetic-fixture
    instruments carrying the negative proof.
  - Current-version law for this suite: zero git-HEAD comparisons or
    byte-pins vs HEAD, zero exact-phrase prose pins of prompts/docs (the
    Working-Root triplication exception belongs to roles_test.sh, not here).

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
  # Re-scoped by change `deembed-orchestration-scripts` (setmodeldeembed-05):
  # twelve-installs becomes sixteen-installs (four libdir scripts added);
  # embedded set-model script clause becomes installed-file clause.
  Scenario: e2e-qa-01
    When a user runs `sh install.sh --all` from the checkout with HOME set
      to an isolated empty directory
    Then the exit status is 0
    And the report lists all sixteen installs (4 agents x 2 clients, plus
      2 antz.md and 2 antz-set-model.md commands, plus 4 libdir scripts)
      under the isolated HOME
    And every installed file carries an `antz:generated` marker whose
      embedded VERSION matches the repo's VERSION file
    And the installed `antz-set-model.sh` under the resolved libdir carries
      the `for arg do` line (the set-model script is a standalone installed
      file, not embedded in the command bodies)

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
