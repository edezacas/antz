# Sub-spec 02 — the documented one-command runner
# Destination domain: `test-runner` (new domain — the verifier creates
# `spdd/specs/test-runner.md`). Dependency order: 2 (builds on the harness
# library's output contract; the decoupling sub-specs make its exactly-once
# guarantee true end to end).

Feature: one documented runner executes every suite exactly once with an
  aggregate summary
  The test area has no canonical runner: the documented invocation is an
  ad-hoc glob loop buried in a planning doc, there is no whole-run verdict,
  and the "is the whole suite green" question is answered by suites
  glob-running each other. The runner is the single documented entry point
  that answers it.

  Background:
    Given the test area under "tests/" — every suite is a "tests/*_test.sh"
      file ("bash32-sh.sh" is a helper and matches no suite glob)
    And the harness output contract: every suite prints one
      "PASS: <name>" / "FAIL: <name>" / "SKIP: <name> (<reason>)" line per
      registered test, where <name> begins with the test's scenario id, and
      exits 0 exactly when no registered test failed
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

### Invariants
- The runner is sequential and needs no parallelism to meet the budget.
- The runner writes nothing outside what the suites' own hermetic helpers
  write; it performs no install.sh render of its own.
- The stale ad-hoc loop mention in docs/plan-revision-2026-09.md is
  accepted residue: docs/ edits are out of scope for this change.

## Out of scope
- Any runner feature beyond discovery, execution, status, summary, exit
  code, and usage text (no filtering flags, no sharding, no CI wiring).
- Re-running a failing suite automatically or retrying flaky tests.
