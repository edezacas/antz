Feature: End-to-end QA - the flow's user-visible surface, layer by layer
  # End-to-end suite for change flow-branch-checkout, one series per layer.
  # Operates at the product "UI" only: for the flow script that is the
  # orchestrator's documented convention of saving the embedded script to a
  # temp file and driving it with "sh <tempfile> <cmd>" (a CLI affordance),
  # observed through git's user-visible state; for the orchestrator role it
  # is a live invocation of the installed antz-orchestrator; for the docs
  # layer it is install.sh's own flags (a UI affordance) plus the documents
  # a user reads. No internal API calls anywhere.
  #
  # The coder ships these as explicit SKIP stubs (tagged with their ids);
  # the verifier exercises them live during Integration Verification.

  # --- flow-script layer (pairs with 01-ensure.feature) ---

  Background:
    Given a scratch git project with at least one commit and a dirty working
      tree (uncommitted edits the user cares about)
    And the flow script saved to a temp file exactly as the orchestrator
      prompt prescribes

  # ADD - e2e-ensure-01: the user-visible start-and-resume workflow: ensure
  # puts the session on the flow branch with the user's dirty files intact,
  # and re-running it mid-flow is safe.
  Scenario: e2e-ensure-01
    When the user runs "ensure my-slug" from inside the project
    Then the printed line is "state=created"
    And "git status" shows the session on branch "antz/my-slug" with the
      user's uncommitted edits still listed
    And the files' contents are unchanged on disk
    When the user resumes later and runs "ensure my-slug" again
    Then the printed line is "state=reused" and the session is still on
      "antz/my-slug"
    And "git log" shows no new commits anywhere

  # ADD - e2e-ensure-02: the refused off-ramp is user-controlled: the script
  # stops machine-readably, the user reproduces and resolves the conflict
  # with their own git commands, and ensure then completes.
  Scenario: e2e-ensure-02
    Given a repository where "antz/stuck-slug" exists at an older commit
      whose "a.txt" differs from HEAD's, and "a.txt" is locally modified
    When the user runs "ensure stuck-slug"
    Then the printed line is "state=checkout_refused" with a nonzero exit,
      the modification is intact, and the session is unmoved
    When the user runs their own "git switch antz/stuck-slug", sees git's
      conflict message, commits their work, and runs "ensure stuck-slug"
      again
    Then the printed line is "state=reused" and the session is on
      "antz/stuck-slug"

  # --- orchestrator-prompt layer (pairs with 02-orchestrator.feature) ---

  # ADD - e2e-orchestrator-01: a live orchestrated run leaves the user on
  # the flow branch, prints follow-ups with a placeholder merge target, and
  # never runs a git command beyond the flow script's own subcommands.
  Scenario: e2e-orchestrator-01
    Given a scratch git project (at least one commit) with the installed
      antz-orchestrator available as the product's UI
    When the user asks the orchestrator, via its native invocation, to
      deliver a small change
    Then during the flow "git status" shows the session on branch
      "antz/<flow slug>" with the roles' artifacts listed as pending,
      uncommitted files
    And on approval the orchestrator's final report prints the human
      follow-ups: the user's own review-and-commit, a merge example whose
      target is a placeholder (no hardcoded integration branch name), and
      the optional branch deletion
    And the repository's history gains no commit from any role, no merge was
      ever run by the orchestrator, and the marker branch still exists
      pointing at the flow's base commit

  # --- docs layer (pairs with 03-docs.feature) ---

  # ADD - e2e-docs-01: the version bump is visible through install.sh's own
  # CLI and the updated policy docs read consistently.
  Scenario: e2e-docs-01
    Given both clients installed from the pre-change source (markers
      "antz:generated version=3.0.0")
    When the user runs "./install.sh --check"
    Then it reports "Claude Code: antz 3.0.0 -> 4.0.0" and "OpenCode: antz
      3.0.0 -> 4.0.0", prints the new CHANGELOG entry describing the
      breaking checkout-contract change, and writes no file
    When the user runs "./install.sh --all"
    Then the installed agent files are re-rendered carrying the new flow
      contract and markers "antz:generated version=4.0.0"
    And a fresh "./install.sh --check" reports "already up to date (antz
      4.0.0)" for both clients
    When the user reads AGENTS.md and CLAUDE.md
    Then both carry the updated branch-marker and release-gating gotcha
      bullets with identical text
