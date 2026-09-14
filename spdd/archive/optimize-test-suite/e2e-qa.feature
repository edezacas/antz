# End-to-end QA suite — change `optimize-test-suite`
# Verifier-owned. Operates at the user-visible surface: the developer's
# terminal workflow around the documented runner ("sh tests/run_all.sh" is
# the UI affordance, same convention as the versioning domain's e2e suite
# using install.sh's CLI). Revised to the owner's scope: full-run budget
# under 60 seconds, hermetic into temp space, green in the committed-and-
# archived era, area tests only current-version behavior (the history/
# prose-calibration suites this change deletes stay gone — see README.md
# "Deleted"). All scenarios ADD; no prior e2e series exists for the
# test-runner domain, so ids start at 01.

Feature: the developer runs the whole test area with one command and gets
  a fast, hermetic, honest verdict
  The pre-change area had no runner, re-executed suites ~3x via nested
  globs, took ~393s sequential, shipped RED from two stale-state root
  failures, and was one archived change away from breaking again.

  Background:
    Given a checkout of the antz repository carrying this change's
      end-state test area (the change touched only tests/)
    And the documented runner invocation "sh tests/run_all.sh"
    And the developer's normal environment (their real HOME and
      XDG_CONFIG_HOME)

  # ADD - e2e-qa-01: one command, every current-version suite once, green
  # verdict.
  Scenario: e2e-qa-01
    When the developer runs "sh tests/run_all.sh"
    Then every tests/*_test.sh file present in the checkout appears exactly
      once in the output, each with its own one-line pass/fail status, and
      no other suite is named
    And no deleted history/prose-calibration suite appears in the run —
      every registered suite tests current-version behavior only
    And the final line is the aggregate summary naming total suites,
      passed, failed, tests failed, and elapsed seconds
    And the runner exits 0

  # ADD - e2e-qa-02: the run is fast — the visible budget is under 60
  # seconds, and the ~3x nested re-execution of the pre-change area is gone.
  Scenario: e2e-qa-02
    When the developer runs "sh tests/run_all.sh" and reads the printed
      elapsed seconds
    Then the full run completes in under 60 seconds
    And each suite's status line appears exactly once — no suite executed
      another suite, so no suite's output recurs

  # ADD - e2e-qa-03: the run is hermetic — suites execute in isolated temp
  # HOME/XDG space; the developer's real machine is untouched.
  Scenario: e2e-qa-03
    When the developer notes the contents of "~/.claude",
      "~/.config/opencode", and the resolved antz scripts libdir, runs
      "sh tests/run_all.sh", and compares afterwards
    Then nothing in those locations changed — no new, removed, or modified
      file (the run's writes stayed inside its own temp space)
    And "git status" taken immediately before and after the run shows the
      same working tree — the run itself added, removed, or modified
      nothing

  # ADD - e2e-qa-04: failures are honest and isolated.
  Scenario: e2e-qa-04
    When the developer temporarily breaks one suite (a one-line edit making
      one registered test fail) and runs "sh tests/run_all.sh"
    Then the other suites still run to completion
    And the aggregate summary names the broken suite and lists its failing
      scenario id
    And the runner exits non-zero
    When the developer reverts the edit and runs "sh tests/run_all.sh"
      again
    Then the runner exits 0 with the same summary shape as before

  # ADD - e2e-qa-05: the verdict survives the human's follow-up — the
  # committed-and-archived era stays green with no test edit (no suite
  # compares the tree against git HEAD, pins prose, or depends on the
  # in-flight change directory or a deleted suite).
  Scenario: e2e-qa-05
    When the developer reviews, commits the change's files, and the
      change's directory is archived out of "spdd/changes/" (the human's
      normal post-approval follow-up; no role commits)
    And the developer runs "sh tests/run_all.sh" on the resulting checkout
    Then the runner exits 0 with the same summary shape as before the
      commit — no suite depended on the in-flight change directory, on
      anything being uncommitted versus HEAD, on any deleted suite, or on
      another suite's existence
