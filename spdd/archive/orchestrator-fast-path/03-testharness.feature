# Change: orchestrator-fast-path — sub-spec 03 (test layer, no behavior change)
#
# The three orchestrator script test suites currently extract their scripts
# from agents/prompts/orchestrator.prompt by fence shape (awk over the
# 3-space fences / marker comments). With sub-spec 01 the scripts are real
# files under scripts/orchestration/, so the suites read the files directly
# — no more extraction-from-prompt, and a prompt fence can no longer drift
# from the tested code. The suites' assertion coverage is unchanged.
# One new guard pins the render side: the rendered orchestrator body must
# embed the current file contents byte-for-byte (catches file/render drift).

Feature: testharness — the script tests read scripts/orchestration/ files directly

  Background:
    Given "scripts/orchestration/" holds antz-flow.sh, antz-probe.sh, and
      antz-skills.sh (sub-spec 01)
    And tests/antz-flow_test.sh, tests/orchestrator-status-probe_test.sh,
      and tests/orchestrator-skills-block_test.sh currently extract their
      scripts from "agents/prompts/orchestrator.prompt" by fence shape

  # MODIFY - testharness-01: the flow suite reads the file (against
  # flow-branch's invariant that "both test files extract it mechanically" —
  # superseded).
  Scenario: testharness-01
    When tests/antz-flow_test.sh is run
    Then it loads "scripts/orchestration/antz-flow.sh" as a file, with no
      extraction step reading "agents/prompts/orchestrator.prompt"
    And every pre-existing flow assertion (positioning, refusal, never-
      commits, no-destruction, preflight, discover/state/release shapes)
      keeps passing unchanged against the file

  # MODIFY - testharness-02: the probe suite reads the file.
  Scenario: testharness-02
    When tests/orchestrator-status-probe_test.sh is run
    Then it runs "scripts/orchestration/antz-probe.sh" directly (no
      extraction from the prompt), with CHANGE_DIR pointed at fixture
      change directories as before
    And every pre-existing probe assertion keeps passing unchanged

  # MODIFY - testharness-03: the skills-block suite reads the file and its
  # prompt additive-vs-HEAD guard is re-scoped to the include-marker scheme
  # (against skills-activation's descmatch-05 guard wording — superseded).
  Scenario: testharness-03
    When tests/orchestrator-skills-block_test.sh is run
    Then it runs "scripts/orchestration/antz-skills.sh" directly, with every
      pre-existing block/derivation/matching/none-matched/constraint and
      body-never-read assertion passing unchanged
    And its orchestrator.prompt additive-vs-HEAD guard is re-scoped: it
      verifies each of the three script fences contains exactly its
      "# antz-include:" marker line naming an existing file, and that no
      line of the prompt outside those three fenced bodies was removed
      (any removal outside them still fails the guard)
    And the snippet still parses as POSIX sh ("sh -n") in the constraint
      test

  # ADD - testharness-04: a render-consistency guard — the rendered body
  # must always embed the current file contents, so file and render cannot
  # drift apart silently.
  Scenario: testharness-04
    Given a temp HOME and install.sh run for both clients (its CLI used as
      the test affordance)
    When the installed "~/.claude/agents/antz-orchestrator.md" and
      "~/.config/opencode/agents/antz-orchestrator.md" bodies are compared
      against the current "scripts/orchestration/" files at their three
      fences
    Then each fence's content is byte-identical to the corresponding file
      (indentation included, per sub-spec 02's render contract)
    And the guard fails if a file changes without a matching re-render
      (drift is caught by the suite, not by a stale installed agent)

### Invariants
- Assertion coverage is unchanged: every pre-existing scenario id reported
  by the three suites keeps being reported and passing; only the source of
  the script under test changes.
- No test extracts from the prompt anymore: the prompt fences carry only
  include markers (sub-spec 01), so the extraction helpers are gone.
- The suites stay self-contained (no external framework), mirroring the
  repo's existing harness style.

## Out of scope
- New behavior coverage (session guards and receipts get their own tests
  with their delivering sub-specs, 04 and 05).
- The end-to-end QA suite (sub-spec 07-e2e).

## Relevant files
- "tests/antz-flow_test.sh" — file-loading replaces extract_flow and the
  probe extraction.
- "tests/orchestrator-status-probe_test.sh" — file-loading replaces
  extract_script.
- "tests/orchestrator-skills-block_test.sh" — file-loading replaces the
  marker-to-fence extraction; additive-vs-HEAD guard re-scoped.
- one new or evolved test file for the render-consistency guard
  (testharness-04).
