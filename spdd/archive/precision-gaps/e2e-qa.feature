# Change: precision-gaps — end-to-end QA suite (one file per change dir —
# the archived practice this change itself pins at specifier.prompt level).
#
# Operates at the product's real UI: the artifacts a user can open and read
# (spdd/changes/<slug>/ files, role prompts, VERSION/CHANGELOG.md), the
# probe's CLI affordance (scripts/orchestration/antz-probe.sh via
# CHANGE_DIR, the same file the orchestrator's flow `state` subcommand runs),
# and install.sh's CLI. No internal API calls — there are none.
#
# The live-session halves (a real specifier/coder/verifier invocation) are
# observable only by driving a real client session, which no role can spawn:
# per the repo's established e2e convention their unit-level halves ship as
# explicit SKIP stubs (id-accounted) and the verifier exercises them live
# during Integration Verification, judging the mechanism they exercise.
# e2e-probealign-01 and e2e-version-01 are fully runnable.

Feature: a user sees the precision-gap fixes through the roles' artifacts, the probe, and the 4.6.0 install surface

  # ADD - e2e-conventions-01: the specifier's new conventions are observable
  # in the artifacts of a real invocation (live-session; judged by mechanism).
  Scenario: e2e-conventions-01
    Given a fresh change request on a clean working tree
    When the user invokes the specifier for that change
    Then each produced sub-spec's scenario ids are two zero-padded digits
      sequential from 01 within the sub-spec (the first is "<feature>-01")
    And the change directory holds exactly one "e2e-qa.feature" — not one per
      feature
    And "spdd/changes/<slug>/README.md" carries one section per sub-spec,
      each stating that sub-spec's relevant files and its declared
      destination domain (kebab-case)

  # ADD - e2e-rolechecks-01: a coder session's threshold flag and greppable
  # test ids (live-session; judged by mechanism).
  Scenario: e2e-rolechecks-01
    Given a sub-spec whose implementation plan would exceed 8 steps
    When the user invokes the coder for that sub-spec
    Then the session marks the change for splitting (flagging that the
      specifier should split it further) instead of silently proceeding with
      the oversized plan
    And for a sub-spec within the threshold, the session's finished unit
      tests are named with their scenario ids, so a literal grep of each id
      in the project's test files finds them

  # ADD - e2e-verifiergates-01: whole-change verification gates mechanically
  # on the code-present criterion (live-session; judged by mechanism).
  Scenario: e2e-verifiergates-01
    Given a change directory holding one sub-spec with ids present in the
      project's test files and another with neither ids in the test files
      nor a receipt file
    When the user invokes the verifier in whole-change form
    Then the first sub-spec is verified and the second is flagged as
      unimplemented in the report without stopping the verification outright

  # ADD - e2e-probealign-01: the aligned id extraction a user sees through
  # the probe's CLI affordance (runnable).
  Scenario: e2e-probealign-01
    Given a fixture change directory with one sub-spec tagged
      "userprofile-1" (convention-shaped) and another tagged
      "user-profile-1" (hyphenated feature, a violation)
    When the user runs the probe with CHANGE_DIR at that directory (directly
      or via the flow script's "state" subcommand)
    Then the first sub-spec's line reports "ids=userprofile-1" whole
    And the second sub-spec's line reports only "ids=profile-1" — the
      hyphenated feature name is no longer tolerated as a declared id
    And a receipt for the second sub-spec naming "user-profile-1" reads as a
      foreign id: covered may read N/N while complete=no — the violation
      surfaces instead of classifying done

  # ADD - e2e-version-01: the version surface a user sees through install.sh
  # against pre-change installed copies (runnable).
  Scenario: e2e-version-01
    Given installed antz agent and command files stamped
      "antz:generated version=4.5.0" in the user's client directories
    When the user runs "./install.sh --check"
    Then it reports the drift to 4.6.0 for both clients, prints the
      intervening "[4.6.0]" CHANGELOG entry, and writes nothing
    When the user runs "./install.sh --all"
    Then every installed file is restamped "antz:generated version=4.6.0"
      with the updated role-prompt content and the probe script rendered
      verbatim, and a fresh "--check" reports already up to date
      (antz 4.6.0) for both clients
