Feature: the policy docs and the repo's own versioning artifacts reflect the new flow contract
  # Layer: AGENTS.md/CLAUDE.md recently-populated gotcha bullets (which
  # today state the old "no checkouts" law), plus the mandatory VERSION/
  # CHANGELOG.md bump. Independently implementable: pure documentation and
  # bump edits, no code. All scenarios are ADD -- no existing domain in
  # spdd/specs/ covers the gotcha bullets (versioning.md governs only the
  # "## Versioning" sections, whose invariants here are respected, not
  # modified).
  #
  # The bump is not optional: versioning.md's rule mandates a VERSION bump
  # plus a matching CHANGELOG.md entry in the same change whenever
  # agents/prompts/ changes, graded major here (breaking workflow
  # contract: the flow now moves the user's session onto the flow branch).

  Background:
    Given the repo files "AGENTS.md" and "CLAUDE.md", each carrying a
      "## Gotchas" section whose bullet beginning "**Branch-marked flow,
      never committed (`3.0` behavior)**" currently states: the marker
      branch is created pointing at the commit the flow started from --
      under stable law: no "-B", no "--force", no checkouts, no merges, and
      above all no role ever commits anything -- and whose following
      "Release gating, never speculative" bullet currently states:
      committing the work plus "git branch -d antz/<slug>" are the human's
      follow-up
    And the two files carry those two bullets with textually identical
      content in both files
    And "VERSION" currently reads "3.0.0" and "CHANGELOG.md"'s newest entry
      is "## [3.0.0]"

  # ADD - docs-01: the branch-marker gotcha bullet reflects the
  # create-and-checkout contract, the refused stop, and the revised law --
  # identically in both files.
  Scenario: docs-01
    When the reader reads "AGENTS.md"'s and "CLAUDE.md"'s branch-marker
      gotcha bullet
    Then it states that "ensure" creates the marker branch AND checks it
      out, so the flow's session sits on "antz/<slug>" with the work
      uncommitted in the working tree, and that the resume path re-positions
      onto the existing branch
    And it states that a refused positioning (uncommitted changes the switch
      would overwrite) stops the flow with a machine-readable state and
      never forces anything
    And the law it states no longer lists "no checkouts"; it keeps no
      "-B"/"--force", no merges, no resets, no deletes and adds never a
      forced or overwriting checkout
    And it marks the behavior level "4.0" rather than "3.0"
    And both files state this bullet with identical text

  # ADD - docs-02: the release-gating gotcha bullet states the
  # user-controlled follow-ups, with no integration branch name inline.
  Scenario: docs-02
    When the reader reads "AGENTS.md"'s and "CLAUDE.md"'s release-gating
      gotcha bullet
    Then it states the human follow-ups as: the user is on "antz/<slug>",
      reviews the pending files in "git status", commits whenever and how
      they prefer, then themselves decide whether and where to merge (e.g.
      "git switch <integration> && git merge antz/<slug>") and may delete
      the branch
    And it states the orchestrator never merges and never resets a branch
      (meaning unchanged)
    And it names no concrete integration branch (no "master"/"main")
    And both files state this bullet with identical text

  # ADD - docs-03: the mandatory bump artifact -- VERSION 4.0.0 and a dated,
  # breaking-labelled CHANGELOG entry describing exactly what changed --
  # per the existing versioning policy; no earlier entry is rewritten.
  Scenario: docs-03
    When the reader reads "VERSION" and "CHANGELOG.md"
    Then "VERSION" reads exactly "4.0.0"
    And "CHANGELOG.md" carries a "## [4.0.0]" entry with a date and a
      "### Changed" section labelling the change as breaking (workflow
      contract)
    And the entry describes: "ensure" now also checks the branch out
      (fresh path) and re-positions onto it (resume path); the
      machine-readable "state=checkout_refused" stop with nothing ever
      forced; the never-commits law intact; and the updated human follow-ups
      (the user is on the flow branch and merge/delete are their own
      decisions, never the orchestrator's)
    And the tests note: "tests/antz-flow_test.sh"'s no-checkout assertion
      inverted to a checkout/positioning assertion with the never-commits
      and no-destruction guarantees still tested
    And every CHANGELOG entry earlier than "## [4.0.0]" is byte-untouched

### Invariants
- The "## Versioning" sections of AGENTS.md and CLAUDE.md are untouched
  (versioning.md's domain); the versioning-inventory rule applies as-is: this
  change touches "agents/prompts/orchestrator.prompt", so the bump is
  mandatory and graded major.
- install.sh is untouched (its output changes only because it renders the
  updated orchestrator.prompt verbatim; the version marker update comes from
  VERSION).
- The earlier CHANGELOG entries are immutable history; the gotcha bullets'
  update never touches them.
- The two files' gotcha bullets stay textually identical to each other (the
  files' shared-bullet convention before this change).
- docs/orchestrator.md and docs/worktree-isolation-plan*.md are historical
  records, untouched (they self-declare not-living status and contain no
  branch-marker-law claims).
