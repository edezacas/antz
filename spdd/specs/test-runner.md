# Domain: test-runner

## Origin
- Specced and delivered from change `optimize-test-suite` (merged 2026-09-14).
  This is a **new standalone spec domain**: before this change, no governing
  spec covered the documented one-command runner (`tests/run_all.sh`).

## Goal
One documented runner (`tests/run_all.sh`) executes every
`tests/*_test.sh` suite exactly once with an aggregate summary. It is the
single documented entry point that answers "is the whole area green".

## Shared contracts
- **Harness output contract** (from the test-harness domain): per test one
  `PASS: <name>` / `FAIL: <name>` / `SKIP: <name> (<reason>)` line;
  final line `pass=<n> fail=<n> skip=<n>`; exit 0 exactly when no registered
  test failed.
- **Suite discovery** (harness-04, harness-05): a suite is any
  `tests/*_test.sh` file; `tests/bash32-sh.sh` and `tests/harness.sh` are
  helpers, not suites.
- **Permanent laws** (hygiene-01..04): no suite executes another suite; no
  suite asserts another suite's source content or output; no suite compares
  the real tree against git HEAD; no suite pins exact prose phrases of prompts
  or docs (Working-Root triplication exception in roles_test.sh).

## Feature: one documented runner executes every suite exactly once with an
  aggregate summary

  Background:
    Given the test area under "tests/" — every suite is a
      "tests/*_test.sh" file ("bash32-sh.sh" is a helper and matches no
      suite glob)
    And the harness output contract
    And the documented runner "tests/run_all.sh"

  # ADD - runner-01: every suite runs exactly once under the runner.
  Scenario: runner-01
    When the runner executes
    Then every "tests/*_test.sh" suite runs exactly once, in sorted
      filename order — none skipped, omitted, or run twice
    And the runner's suite discovery is mechanical (the tests/*_test.sh
      glob), so a suite added to or removed from "tests/" needs no runner
      edit

  # ADD - runner-02: per-suite status lines, aggregate summary, exit
  # contract.
  Scenario: runner-02
    When the runner executes a full pass in which every suite passes
    Then it prints one status line per suite naming the suite file with
      its pass/fail/skip counts
    And the final line is the aggregate summary: total suites, suites
      passed, suites failed, total tests failed, and elapsed seconds
    And the runner exits 0 exactly when every suite exited 0

  # ADD - runner-03: a failing suite is isolated and named, never fatal to
  # the run.
  Scenario: runner-03
    When the runner executes a full pass in which one suite has a failing
      registered test and the rest pass
    Then every other suite still runs to completion
    And the aggregate summary names each failing suite and lists its
      failing scenario ids
    And the runner exits non-zero

  # ADD - runner-04: the speed budget is printed and met.
  Scenario: runner-04
    When the runner executes a full pass
    Then the printed elapsed seconds are under 120
    And the budget is bought by the named mechanisms, each already specced:
      the render-once harness cache, the removed nested suite execution,
      and the dropped frozen-history suites (the measured pre-change
      sequential baseline was ~393s with ~3x nested re-execution)

  # ADD - runner-05: the runner documents itself and is not a suite.
  Scenario: runner-05
    When the reader opens "tests/run_all.sh" or runs it with -h/--help
    Then its header documents the one-command invocation
      ("sh tests/run_all.sh"), what it runs (every tests/*_test.sh once),
      the summary line, and the exit contract
    And the runner is not itself a suite: it matches no tests/*_test.sh
      glob and defines no harness helper

## Feature: four permanent laws hold over the whole test area, mechanically

  Background:
    Given "tests/hygiene_test.sh", itself a suite picked up by the
      runner's glob, whose scans are pure source scans over a scan root —
      the real "tests/" by default, pointable at a temp fixture copy
    And the discovery contract: a suite is any "tests/*_test.sh" file;
      "tests/bash32-sh.sh" and "tests/harness.sh" are helpers, not suites
    And the carve-outs, applied to every scan: only non-comment lines are
      read; a suite may read its own file; the hygiene suite's own source
      is exempt (it encodes the detection patterns); fixture strings
      naming suite files that do not exist on disk are not references; and
      git operations inside throwaway fixture repositories under temp
      space are not real-tree comparisons
    And no scan passes vacuously: with that scan's violation planted in a
      temp fixture copy of the scan root, the scan fails naming the
      planted file and line

  # ADD - hygiene-01: no suite executes another suite or asserts its
  # content or output.
  Scenario: hygiene-01
    When the suite sources are scanned
    Then no suite source executes another existing tests/*_test.sh file —
      no sh, bash, source, eval, or child-run invocation of it
    And no suite source asserts another existing suite's source content or
      output — no grep, require, or byte-compare against its file;
      "the whole area is green" is answered by the documented runner alone

  # ADD - hygiene-02: no suite compares the real tree against git HEAD.
  Scenario: hygiene-02
    When the suite sources are scanned
    Then no suite source compares the working tree against git HEAD — no
      `git merge-base`, no `show HEAD:`, no `diff --quiet HEAD`, no `cmp`
      against git-extracted content — and no suite byte-pins its own file
      against a git HEAD copy
    And every suite's expectations derive only from the current tree's
      behavior

  # ADD - hygiene-03: no suite pins exact prose phrases of prompts or
  # docs; the Working-Root triplication check is the sole exception.
  Scenario: hygiene-03
    When the suite sources are scanned
    Then no suite source pins an exact prose phrase of a role prompt
      (agents/prompts/) or a doc (docs/, AGENTS.md, CLAUDE.md) — no grep
      of an embedded literal against either, and no byte-compare of
      either's content against embedded expected text
    And a comparison of two live-read files against each other pins no
      phrase and is not a violation
    And the sole declared exception stays green: the Working-Root
      triplication consistency check in "tests/roles_test.sh" — the three
      role prompts' triplicated sections stay byte-identical to each other

  # ADD - hygiene-04: the laws are era-independent — green committed and
  # archived, with no test edit.
  Scenario: hygiene-04
    When the hygiene suite runs against a staged copy of the working tree
      under temp space in which this change is committed and its change
      directory is archived
    Then every scan passes unchanged, as it does in the working tree — no
      scan reads the working tree's spdd/changes/ content, queries its
      git state, or gates on any era
    And committing and archiving this change therefore requires no test
      edit for the suite to stay green
