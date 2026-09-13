# Change: fix-test-regression-precision-gaps — end-to-end QA suite (one file
# per change dir).
#
# Operates at the product's real UI for a tests-only change: the test
# suites a user runs directly (tests/*.sh) and their observable output --
# PASS/FAIL lines carrying scenario ids, the exit code, and the loud
# "note:" retirement lines of gated guards. Running a suite is the CLI
# affordance; no internal API calls (there are none).
#
# The suite runs against the committed master state (git HEAD carrying
# Change C's precision-gaps rewordings) with this change's test fixes in
# the working tree -- exactly the state where the regression was reported.
# Fully runnable: no live agent session is needed, the product surface here
# is the suites themselves.

Feature: a user sees the test regression fixed — the three suites pass on committed master, with the window guards retired loudly

  # ADD - e2e-regression-01: the committed-state pass a user sees when
  # running the three regression suites.
  Scenario: e2e-regression-01
    Given the committed master state (git HEAD carrying Change C's
      precision-gaps rewordings) with this change's test fixes in the
      working tree
    When the user runs tests/sluglimit_test.sh, tests/rolechecks_test.sh,
      and tests/conventions_test.sh
    Then all three suites exit 0 and print no "FAIL" line
    And every scenario id stays registered as a "PASS" line -- including
      sluglimit-02, rolechecks-01, rolechecks-05, and the conventions
      suite's nine tests, its six conventions-04 assertions among them
      (retired by gating, never deleted)
    And the retired window guards are loud, not silent: sluglimit-02 prints
      a "note:" naming "orchestrator.prompt", and rolechecks-01 and
      rolechecks-05 each print a "note:" naming their guarded artifact
    And the conventions suite's two "..._when_copy_differs" tests pass with
      the retirement path covered post-commit -- their fixture-built
      retirement notes are asserted by the tests themselves, never silently
      absent
