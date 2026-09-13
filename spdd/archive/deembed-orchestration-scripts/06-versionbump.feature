# Change: deembed-orchestration-scripts — sub-spec 06 (VERSION bump)
#
# agents/prompts/orchestrator.prompt and install.sh both change in this
# change, so the versioning policy mandates a VERSION bump and a matching
# CHANGELOG.md entry. Decision 3 (2026-09-13): grade minor, with the
# explicit note in the CHANGELOG entry — the "install locations" clause of
# the grading table makes the grade discutable (a new install location
# appears), so the entry must address it head-on, the way the 4.3.0 entry
# addressed its render-contract adjacency. The bump lives in the working
# tree; no role ever commits or tags.

Feature: versionbump — VERSION 4.7.1 -> 4.8.0 with a matching CHANGELOG entry graded minor, explicitly justified

  Background:
    Given "VERSION" reads "4.7.1" at this change's start, with
      CHANGELOG.md's newest entry "## [4.7.1] - 2026-09-13"
    And the versioning policy: a commit changing "agents/prompts/",
      "agents/meta/", or "install.sh" bumps "VERSION" and adds a matching
      "CHANGELOG.md" entry in the same commit; the grade is the most
      severe component's

  # ADD - versionbump-01: the bump is present and describes the change's
  # substance; earlier entries are byte-untouched.
  Scenario: versionbump-01
    When the reader reads "VERSION"
    Then it reads exactly "4.8.0" (the value plus one trailing newline,
      its only content)
    And "CHANGELOG.md" carries a "## [4.8.0] - <date>" section above the
      "[4.7.1]" section, in Keep a Changelog format and the file's
      existing entry style
    And that section's entries describe the change's substance: the four
      scripts installed as files under the resolved
      "${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/" libdir with
      marker, backup, and --check reporting; the orchestrator prompt and
      both /antz-set-model command bodies invoking the installed scripts
      by their resolved paths with zero script re-materialization;
      inject_includes() and the "# antz-include:" markers retired along
      with the antz-skills.sh fence-indent carve-out; the set-model
      script's required client first argument and internal agents-dir
      resolution; --check extended to the installed scripts; the
      AGENTS.md/CLAUDE.md law and docs/orchestrator.md updated; and the
      expected cache effect (the rendered orchestrator body from ~483
      lines to ~150, per-session script re-materialization to zero)
    And every earlier CHANGELOG entry is byte-for-byte untouched

  # ADD - versionbump-02: the grade is minor, stated explicitly, with the
  # install-locations clause addressed head-on.
  Scenario: versionbump-02
    When the reader reads the "[4.8.0]" entry's grading statement
    Then it states the grade as minor — rendered agent/command bodies and
      install mechanics change, which is a behavior change and not the
      wording-only kind that grades as patch
    And it states explicitly why it is not major, addressing the
      "install locations" clause head-on: the workflow contract, the
      machine-line vocabulary, the "antz:generated" marker format, the
      access model, and the twelve client-file install paths are all
      unchanged; the libdir is an additional install location shared by
      both clients that no existing consumer breaks on (the same
      explicit-adjacency-note precedent as the 4.3.0 entry)
    And it states that the local "v4.8.0" tag is the human's commit-time
      follow-up, created against the human's bump commit and never pushed
      automatically, and that no role creates it

  # ADD - versionbump-03: one bump covers the whole change.
  Scenario: versionbump-03
    When the change's diff is graded by its most severe component
    Then the single 4.8.0 bump covers the orchestrator prompt edit,
      install.sh's mechanics change, the command files' rendered shape,
      and the docs/tests edits together
    And no additional bump or entry is required for the docs-only or
      tests-only parts (the docs-only clause of the policy applies to
      them)
