# Domain: test-runner

## Goal
The repo's test suite: how it is run, what is hermetic, and what a red run
means. Tests are the enforcement behind every other spec and behind the role
prompts: they assert current-version product behavior, never history and never
prose.

## Shared contracts
- **Runner**: `sh tests/run_all.sh` — discovers and runs every
  `tests/*_test.sh`, reports per-suite pass/fail, and exits non-zero when any
  suite fails.
- **Hermetic and bounded**: the whole run takes no network, no external
  service, and no LLM call, and finishes well under 120 seconds.
- **One owner per behavior surface**: a behavior is asserted by exactly one
  suite; extend the owner instead of duplicating the assertion in a new suite.
- **No prose pinning**: no suite asserts a literal sentence of a role prompt
  or a doc, and none compares the working tree against git HEAD or pins a past
  version. The single declared exception is the Working-Root byte-identity
  check across the three role prompts, which `tests/hygiene_test.sh` honors by
  name.
- **Ownership**: `tests/harness.sh` provides the shared assertion helpers and
  suite lifecycle every suite uses.
- **A red run means a real regression or a law violation** — nothing else.

## Feature: Running the suite

  # ADD - testrunner-01: the runner is the single entry point
  Scenario: testrunner-01
    When "sh tests/run_all.sh" runs from the repo root
    Then every "tests/*_test.sh" is executed and its result reported
    And the exit status is non-zero when any suite failed, zero otherwise
    And no suite is executed twice

  # ADD - testrunner-02: the run is hermetic and bounded
  Scenario: testrunner-02
    When the runner runs with no network available
    Then it completes successfully
    And it makes no LLM or network call and writes only under temp space

  # ADD - testrunner-03: behavior has one owning suite
  Scenario: testrunner-03
    When a behavior surface is asserted
    Then exactly one suite owns that assertion
    And a new suite asserting an already-owned surface without extending the
      owner is a violation

  # ADD - testrunner-04: no suite pins prose or history
  Scenario: testrunner-04
    When the suite sources are scanned
    Then none asserts a literal prompt or doc sentence, compares the tree
      against git HEAD, or pins a past version
    And the Working-Root triplication check is the sole declared exception,
      named in "tests/hygiene_test.sh"
