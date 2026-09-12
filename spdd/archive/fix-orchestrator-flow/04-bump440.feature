# Change: fix-orchestrator-flow — sub-spec 04 (the 4.4.0 bump)
#
# The project rule this change carries: any commit touching agents/ bumps
# VERSION and adds the matching CHANGELOG.md entry in the same change
# (spdd/specs/versioning.md). This change edits all three role prompts, so the
# grade is minor (behavior changes to the roles), and the bump lands in the
# same working tree as the items it describes — everything uncommitted on
# antz/fix-orchestrator-flow, the tag being the human's commit-time follow-up.
#
# Precedents: closingblock-06/07 (the 4.3.0 bump), bump-01..03 (4.1.0),
# bump421-01..02 (4.2.1). The suites pin VERSION only as "a semver agreeing
# with the newest (topmost) CHANGELOG entry" — never a pinned literal — and
# pin the immutability of earlier entries, so stacking [4.4.0] on top keeps
# them green.
#
# Merge map: ADD against spdd/specs/versioning.md (the versioning-policy
# domain).

Feature: VERSION bumped to 4.4.0 with a matching CHANGELOG.md entry describing the flow fixes, graded minor

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.3.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.3.0] - 2026-09-11"

  # ADD - bump440-01: the bump is present — VERSION reads 4.4.0 and
  # CHANGELOG.md gains a matching [4.4.0] section above [4.3.0].
  Scenario: bump440-01
    When the reader reads "VERSION"
    Then it reads exactly "4.4.0" (the version value plus one trailing
      newline, its only content)
    And "CHANGELOG.md" carries a "## [4.4.0] - <date>" section above the
      "[4.3.0]" section, in Keep a Changelog format and the file's existing
      entry style
    And that section's Added/Changed entries describe the change's substance:
      the orchestrator delegating never-specified changes to the specifier
      with the mid-session-deletion and post-verifier routing, the dedup
      guard's two enumerated exceptions, step 5 detecting the verifier's
      outcome from disk with the release-gate disambiguation, the defined
      waiting-user stop variant, the coder's write-surface ownership bullet,
      the verifier's plain-mv archive step with its reason, and the literal
      "test_command=none" sentinel with the probe's acceptance and the
      never-execute rule
    And every earlier CHANGELOG entry is byte-for-byte untouched, so the
      pinned history keeps passing: "[4.3.0]" still sits above "[4.2.1]" and
      still describes its changes

  # ADD - bump440-02: the grade is minor, stated and justified against the
  # versioning table — and no tag is created by any role.
  Scenario: bump440-02
    When the reader reads the "[4.4.0]" entry against the versioning gradation
    Then the change grades as "minor": it changes role behavior — the
      orchestrator's routing and outcome detection, the coder's ownership
      bullet, the verifier's archive instruction — which the gradation
      reserves for minor, not patch (not wording-only: rendered agent bodies
      and role behavior both change)
    And it does not grade as "major": the workflow contract, the
      "antz:generated" marker format, the access model, the directory layout,
      and the install locations are all unchanged — the probe's output
      vocabulary, the release machine lines, the receipt grammar's shape, and
      the four-subcommand flow script all survive
    And "install.sh" itself is untouched: the bump flows into installed copies
      only through the re-render, via the normal "./install.sh --all"
      follow-up
    And no tag is created by any role: the local "v4.4.0" tag is the human's
      commit-time follow-up, created against the human's bump commit and not
      pushed automatically
