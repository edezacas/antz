# Domain: skills activation bump (versioning layer)

## Goal
This change touches tracked paths (`agents/prompts/` and `install.sh`), so
per the versioning policy (spdd/specs/versioning.md) `VERSION` must bump and
`CHANGELOG.md` must gain a matching entry in the same working tree. The
grade is **minor**: behavior changes to the roles (`## Skills` sections) and
to install.sh's rendered grants (`Skill` in the readwrite Claude tools
list); nothing in the workflow contract, the `antz:generated` marker
format, the access taxonomy/mapping levels' structure, the directory
layout, or the install locations breaks.

## Shared contracts
Consumes the policy as documented (docs-only changes need no bump; tracked
paths are `agents/prompts/`, `agents/meta/`, `install.sh`). The bumped
value (`4.2.0`) is what the --check machinery (spdd/specs/versioning.md) and
03-render's marker both report, so these sub-specs reference the same value
identically.

## Feature: bump to 4.2.0 with a matching CHANGELOG entry layered above 4.1.0

  Background:
    Given "VERSION" currently reads "4.1.0" and "CHANGELOG.md" carries
      "[4.1.0] - 2026-09-11" as its top section
    And this change's files under "agents/prompts/" and "install.sh" are
      edited (01-prompts, 03-render)

  # ADD - bump-01: the bump is present -- VERSION reads 4.2.0 and
  # CHANGELOG.md gains a matching [4.2.0] section above [4.1.0].
  Scenario: bump-01
    When the reader reads "VERSION"
    Then it reads exactly "4.2.0"
    And "CHANGELOG.md" contains a "[4.2.0] - <date>" section above the
      "[4.1.0]" section
    And that section lists the Added/Changed entries matching this change:
      skills-activation learning in the coder and verifier prompts (new
      "## Skills" sections), the orchestrator's pre-resolved "## Skills
      to load before work" delegation block (02-orchestrator), and the
      "Skill" tool added to the readwrite Claude tools string in
      install.sh

  # ADD - bump-02: the grade is minor, stated and justified against the
  # versioning table.
  Scenario: bump-02
    When the reader reads the "[4.2.0]" entry against the grading scale
    Then the change grades as "minor": behavior changes to the roles'
      prompts ("## Skills" sections) and to install.sh's rendered agent
      capability (the "Skill" grant) -- not "patch" (that grades only
      non-behavioral tweaks), and not "major" (the workflow contract, the
      marker format, the access taxonomy, the rendered command contract,
      and the install locations are all unchanged)

  ### Invariants
  - No role commits anything; the "v4.2.0" tag is the human's commit-time
    follow-up.
  - The CHANGELOG entry follows Keep a Changelog format and file style.
  - "VERSION" is the only content of the "VERSION" file ("4.2.0" with
    trailing newline).
  - "agents/meta/*" are byte-for-byte unchanged (only non-meta edits are
    involved here).

## End-to-end QA suite

  # ADD - e2e-bump-01: the bump is real, discoverable, and reported by
  # --check against pre-change installed copies.
  Scenario: e2e-bump-01
    Given the user's machine has the pre-change antz installed (installed
      marker version "4.1.0")
    When the user reads "VERSION" and the top of "CHANGELOG.md", then runs
      "./install.sh --check"
    Then "VERSION" reads "4.2.0", the top section is "[4.2.0] - <date>"
    And "--check" reports the installed-to-source drift for both detected
      clients and prints the "[4.2.0]" entry
    And "./install.sh --all" reproducibly stamps every installed file with
      the "antz:generated version=4.2.0" marker

## Out of scope
- Editing the versioning policy wording itself (spdd/specs/versioning.md
  remains untouched).
- Tag creation (the human does it at commit time).

## Relevant files
- VERSION, CHANGELOG.md - the bump artifacts.
- spdd/specs/versioning.md - the policy consumed unchanged.
