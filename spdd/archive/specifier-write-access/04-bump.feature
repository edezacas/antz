Feature: VERSION bumped to 4.1.0 with a matching CHANGELOG.md entry in the same working tree
  # Layer: versioning policy (spdd/specs/versioning.md). The change touches
  # agents/meta/ -- a tracked path -- so the same-change bump rule applies.
  # Grade: minor. The rendered agent output changes (behavior change to the
  # roles), which is the minor row; it is NOT major: the workflow contract's
  # access-model taxonomy is unchanged, the access-to-frontmatter mapping is
  # unchanged, the marker format is unchanged, no layout or install location
  # moves. Precedent: adding "orchestrateonly" (3.0.0) was major because it
  # broke the then-documented access contract; this change breaks no
  # consumer -- it broadens capability to match what the prompts always
  # required. Note: VERSION/CHANGELOG.md/AGENTS.md/CLAUDE.md carry uncommitted
  # edits from the pending flow-branch-checkout change in this same working
  # tree; this change's edits are strictly additive on top.
  #
  # Verification: deterministic content assertions on VERSION and
  # CHANGELOG.md, plus the additive-layering check against the other
  # change's pending hunks.

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit changing "agents/prompts/", "agents/meta/", or "install.sh" bumps "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" currently reads "4.0.0" (flow-branch-checkout's pending, uncommitted bump; today is 2026-09-11)
    And "CHANGELOG.md" currently carries an uncommitted "[4.0.0] - 2026-09-11" section (flow-branch-checkout)

  # ADD - bump-01: the bump is present -- VERSION reads 4.1.0 and
  # CHANGELOG.md gains a matching [4.1.0] section, layered above [4.0.0].
  Scenario: bump-01
    When the reader reads "VERSION"
    Then it reads exactly "4.1.0"
    And "CHANGELOG.md" contains a "[4.1.0] - 2026-09-11" section above the "[4.0.0]" section
    And that section's Changed entries describe the specifier and verifier access correction to "readwrite", the unchanged render for coder/orchestrator, the retained readonly mapping, and the docs correction

  # ADD - bump-02: the grade is minor, stated and justified against the
  # versioning table.
  Scenario: bump-02
    When the reader reads the "[4.1.0]" entry against the "## Versioning" gradation
    Then the change grades as "minor": a behavior change to the roles' rendered agents (Edit/Write granted, edit allowed)
    And it does not grade as "major": the access-model taxonomy, the access-to-frontmatter mapping, the "antz:generated" marker format, the directory layout, and the install locations are all unchanged

  # ADD - bump-03: shared-file edits are strictly additive over the pending
  # flow-branch-checkout edits -- never reverting them.
  Scenario: bump-03
    When the reader inspects this change's edits to "VERSION", "CHANGELOG.md", "AGENTS.md", and "CLAUDE.md"
    Then each edit adds or corrects on top of flow-branch-checkout's pending hunks
    And flow-branch-checkout's pending content survives: "VERSION" keeps its 4.0.0 history via the "[4.0.0]" section, the flow-branch gotcha wording in both docs, the orchestrator.prompt and antz-flow changes, and tests/antz-flow_test.sh are all still present and unmodified by this change

  ### Invariants
  - No tag is created by any role: per the never-commits law the local
    "v4.1.0" tag is the human's commit-time follow-up, created against the
    human's bump commit.
  - The CHANGELOG entry follows Keep a Changelog format and the file's
    existing entry style.
  - VERSION is the only content of the "VERSION" file ("4.1.0", trailing
    newline as before).

## End-to-end QA suite

  # Operates at the user-visible surface: reading VERSION/CHANGELOG.md and
  # install.sh's --check CLI. e2e only.

  # ADD - e2e-bump-01: the bump is real, discoverable, and consistent with
  # the --check machinery the versioning policy describes.
  Scenario: e2e-bump-01
    When the user reads "VERSION" and the top of "CHANGELOG.md"
    Then "VERSION" reads "4.1.0" and the top section is "[4.1.0] - 2026-09-11" describing the access correction
    And "./install.sh --check" on a machine with pre-change installed copies reports the drift to "4.1.0" and prints the "[4.1.0]" entry
