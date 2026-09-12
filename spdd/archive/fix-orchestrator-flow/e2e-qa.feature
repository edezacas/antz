# Change: fix-orchestrator-flow — end-to-end QA suite (one file per change
# dir, one series per user-visible surface, the archived practice).
#
# Operates at the product's real UI: invoking the installed agents (/antz and
# the role agents), running install.sh's CLI, and reading the docs. No internal
# API calls — there are none; the "surfaces" are the orchestrator's visible
# routing decisions, the disk state a user can inspect with git status and ls,
# and install.sh's report.
#
# The live-session scenarios (e2e-delegation-01, e2e-approval-01) are
# observable only by driving a real client session end to end, which no role
# can spawn: per the repo's established e2e convention their unit-level halves
# ship as explicit SKIP stubs (id-accounted) and the verifier exercises them
# live during Integration Verification, judging the mechanism they exercise.
# e2e-version-01 is fully runnable.

Feature: a user sees the flow reach the specifier on a fresh change, see approval decided from disk, and see the 4.4.0 surface through install.sh

  # ADD - e2e-delegation-01: the happy path a user of a brand-new change now
  # gets — the flow reaches the specifier instead of dying at
  # change_dir=missing (live-session; judged by mechanism).
  Scenario: e2e-delegation-01
    Given a clean checkout of the repository with at least one commit, on any
      branch, with neither "spdd/changes/<slug>/" nor "spdd/archive/<slug>/"
      existing for the requested change
    When the user invokes /antz with a request for one new change
    Then the flow positions the session on "antz/<slug>", and instead of
      stopping at "change_dir=missing" the orchestrator delegates the change
      to the specifier
    And the specifier session starts from the delegation message carrying the
      working root, the change slug, and the "## Skills to load before work"
      block, and authors "spdd/changes/<slug>/" with the change's README and
      numbered sub-spec files
    And the orchestrator's report for that invocation ends with a closing
      block reading "status=delegated-specifier"
    And a follow-up /antz invocation for the same change resumes from disk —
      the probe lists the sub-specs with their receipt fields — and routes
      into implementation without delegating the specifier again
    And nothing was committed at any point: "git status" shows the new files
      as uncommitted work on "antz/<slug>"

  # ADD - e2e-approval-01: approval is decided from disk, so the user sees
  # the same observable outcome whether the verifier said approved or
  # approved-with-warnings, and gets the human follow-ups (live-session;
  # judged by mechanism).
  Scenario: e2e-approval-01
    Given a change whose sub-specs all classify done from their receipts, and
      a verifier session that approves it (with or without warnings)
    When the verifier finishes its Merge & Archive
    Then "spdd/changes/<slug>/" is gone from the working tree and
      "spdd/archive/<slug>/" holds the change's files unmodified — moved with
      a plain "mv", since nothing was ever committed to move with "git mv"
    And the orchestrator, re-probing after the verifier delegation, finds the
      change dir absent, runs the release gate, gets a green
      "released branch=antz/<slug>", and reports the change as done
    And the orchestrator's report ends with a closing block reading
      "status=released" and prints the human follow-ups: review and commit
      selectively, merge with a placeholder target, optional branch deletion
      — all for the user to run, none run by the orchestrator
    And the session sits on "antz/<slug>" with the finished work uncommitted
      and visible via "git status"
    And when instead the verifier appends a rejection, the user sees the
      orchestrator route by the fresh "REJECTED.md" entry count — one
      attributable entry relayed and retried once, two entries stopped for
      good — never by the verifier's prose verdict

  # ADD - e2e-version-01: the version/docs surface a user sees through
  # install.sh against pre-change installed copies (runnable).
  Scenario: e2e-version-01
    Given installed antz agent and command files stamped
      "antz:generated version=4.3.0" in the user's client directories
    When the user runs "./install.sh --check"
    Then it reports the drift to 4.4.0 for both clients, prints the
      intervening "[4.4.0]" CHANGELOG entry, and writes nothing
    When the user runs "./install.sh --all"
    Then every installed file is restamped "antz:generated version=4.4.0"
      with the updated role prompts rendered verbatim, and a fresh "--check"
      reports already up to date (antz 4.4.0) for both clients
    And "AGENTS.md" and "CLAUDE.md" carry the updated strict-ownership
      gotcha bullet identically in both files
