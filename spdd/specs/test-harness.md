# Domain: test-harness

## Origin
- Specced and delivered from change `optimize-test-suite` (merged 2026-09-14).
  This is a **new standalone spec domain**: before this change, no governing
  spec covered the shared test harness library (`tests/harness.sh`) that
  replaced the per-suite helper copies.

## Goal
One sourced harness library (`tests/harness.sh`) replaces the per-suite
helper copies. The library provides: run_test, skip_test, require, refuse,
the extract_* readers, new_tmp_dir, cleanup, stage_checkout, and the
install-render helpers. Suites source it and keep only their scenario logic.

## Shared contracts
- **Harness output contract** (consumed by every suite and the runner):
  per test one `PASS: <name>` / `FAIL: <name>` / `SKIP: <name> (<reason>)`
  line, `<name>` beginning with the scenario id; final line
  `pass=<n> fail=<n> skip=<n>`; exit 0 exactly when no registered test
  failed.
- **Render-once cache** (harness-03): repeated renders of one staged tree
  execute install.sh once and reuse the installed tree; a different staged
  tree performs its own render.
- **Hermeticity** (harness-02): temp space under `${TMPDIR:-/tmp}`, never
  under the repo working tree or real user config; HOME/XDG sandboxed.

## Feature: one sourced harness library replaces the per-suite helper copies

  Background:
    Given the test area under "tests/" — suites plus the `bash32-sh.sh`
      helper, which is not a suite
    And the harness library file "tests/harness.sh" providing the helpers
      the suites use: run_test, skip_test, require, refuse, the extract_*
      readers, new_tmp_dir, cleanup, stage_checkout, and the install-render
      helpers
    And the harness output contract

  # ADD - harness-01: sourcing the library replaces the per-suite copies;
  # the helpers' observable behavior is unchanged.
  Scenario: harness-01
    When a suite sources "tests/harness.sh" and registers tests with
      run_test/skip_test
    Then the helpers behave as the copy-pasted versions did: pass/fail
      accounting, the PASS/FAIL/SKIP line shapes, the id-carrying reported
      names, the skip reason (including the "BLOCKED:" refusal convention),
      and the exit status are all preserved
    And each suite's final output line is the aggregate
      "pass=<n> fail=<n> skip=<n>"
    And a suite that sources the library defines none of the helpers itself

  # ADD - harness-02: hermeticity is a library guarantee, not per-suite
  # discipline.
  Scenario: harness-02
    When the harness helpers create temp space or render, with HOME set to
      an empty canary directory and XDG_CONFIG_HOME set to another
    Then new_tmp_dir creates directories under "${TMPDIR:-/tmp}" and never
      under the repo working tree or the real user config
    And every install render the library performs runs with HOME pointed at
      a sandbox directory and XDG_CONFIG_HOME cleared, so install.sh can
      only write inside the sandbox
    And no helper and no suite run writes into the repo working tree or the
      real "~/.claude" / "~/.config/opencode"

  # ADD - harness-03: one render per staged tree — repeated renders reuse
  # the first (the render-count drop that buys the speed target).
  Scenario: harness-03
    When a suite stages a checkout and renders it more than once through
      the library's render helper within one suite run
    Then the underlying install.sh render executes once and the installed
      tree is reused: a later render call leaves the installed files'
      contents and mtimes unchanged while still returning the complete
      installed tree
    And a render of a different staged tree performs its own render

  # ADD - harness-04: the library is the single install.sh invocation point.
  Scenario: harness-04
    When the test sources are scanned for install.sh invocations
    Then only "tests/harness.sh" invokes install.sh; no suite source
      contains an install.sh invocation of its own

  # ADD - harness-05: the copy-paste era ends — helper definitions live
  # only in the library.
  Scenario: harness-05
    When the test sources are scanned for definitions of the harness
      helpers (run_test, skip_test, new_tmp_dir, cleanup, stage_checkout,
      the render helpers)
    Then every definition lives in "tests/harness.sh" and no suite file
      defines any of them
    And the suites' behavior is otherwise unchanged: each suite still
      registers the same scenario ids it registered before the refactor

  # ADD - harness-06: temp lifecycle and staged checkouts keep their
  # meaning.
  Scenario: harness-06
    When a suite acquires temp directories through new_tmp_dir and exits
      through cleanup
    Then cleanup removes every directory new_tmp_dir created for that run
      (also on early failure), leaving nothing under "${TMPDIR:-/tmp}"
    And stage_checkout copies the working tree's product files (install.sh,
      VERSION, CHANGELOG.md, agents/, scripts/orchestration/) into a fresh
      temp tree, as the copied helpers did, so suites always exercise the
      working tree's current state
