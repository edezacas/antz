# Domain: the bump to 4.2.1 layered above 4.2.0 (bump421 layer)

## Goal
Track the descmatch fix per the repo versioning policy
(`spdd/specs/versioning.md`): a change touching `agents/prompts/` bumps
`VERSION` and adds a matching `CHANGELOG.md` entry in the same commit. The
bump is 4.2.1 and grades **patch**: the snippet's code is aligned to
already-specced, already-merged behavior (the rendered prose is unchanged
and description-keyed, the output contract is unchanged, no workflow
contract, marker format, access model, or install mechanic moves) — the
patch precedent is the 2.4.0 Fixed entry. The entry lands under a `Fixed`
heading per Keep a Changelog and the file's own conventions.

## Shared contracts
"VERSION" and the topmost "CHANGELOG.md" section must agree (the
cross-change lesson recorded in "tests/docs-bump_test.sh" comments and
reused by "tests/skills-activation-bump_test.sh": never pin VERSION as a
byte-exact literal across changes — assert agreement with the newest
changelog entry, which today reads exactly 4.2.1).

## Feature: the patch bump 4.2.1 tracks the description-match fix

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/" bumps "VERSION" and adds a matching
      "CHANGELOG.md" entry in the same commit
    And "CHANGELOG.md" carried "[4.2.0] - 2026-09-11" as its top section

  # ADD - bump421-01: the bump is present — VERSION agrees with a new
  # [4.2.1] section above [4.2.0], carrying a Fixed entry that describes
  # exactly the descmatch narrowing.
  Scenario: bump421-01
    When the reader reads "VERSION" and the top of "CHANGELOG.md"
    Then "VERSION" is a semver string that equals the version of the
      newest (topmost) "CHANGELOG.md" section, which is "[4.2.1] - <date>"
      sitting above the "[4.2.0]" section
    And the "[4.2.1]" section has a "### Fixed" heading whose entry states
      that the orchestrator's embedded antz-skills.sh matching is keyed to
      each skill's "description:" field only — a keyword appearing only in
      the frontmatter "name:", "license:", or "metadata:" no longer lists
      the skill (previously the whole lowercased frontmatter block was
      matched, producing false positives such as "apache" via
      "license: Apache-2.0")
    And that entry states the multi-line support: "description: >" and
      ">-" block scalars match via their indented continuation lines,
      accumulated until the next top-level key or the end of the
      frontmatter (so the real omarchy and diagnose-crash skills stay
      matchable)
    And the entry states nothing else changed — the output shapes, the cap
      of five, the tie-break, the prose, the docs, and install.sh are
      untouched

  # ADD - bump421-02: the grade is patch, stated and justified against the
  # versioning table — the user's decision for this fix.
  Scenario: bump421-02
    When the reader reads the "[4.2.1]" entry against the grading scale
    Then the change grades as "patch": the snippet is aligned to
      already-specced behavior with no contract change — the rendered
      prose, the delegation-block contract, the output shapes, the
      workflow contract, the "antz:generated" marker format, the access
      model, and install.sh's mechanics are all unchanged, so no consumer
      breaks (not "minor": no new role behavior, render mechanic, or
      install mechanic is introduced; not "major": nothing in the workflow
      or rendered command contract changes)
    And the entry records that this closes the "Implementation caution"
      recorded in "spdd/specs/skills-activation.md" at merge time

  ### Invariants
  - No role commits anything; the "v4.2.1" tag is the human's commit-time
    follow-up (created against the bump commit, not pushed automatically).
  - The CHANGELOG entry follows Keep a Changelog format and the file's
    existing style (bold lead-in, self-contained prose).
  - "VERSION" is the only content of the "VERSION" file (the version with
    a trailing newline).
  - "agents/meta/*", "install.sh", "AGENTS.md", and "CLAUDE.md" are
    byte-for-byte unchanged (docs and tests don't require a bump; nothing
    else moved).
