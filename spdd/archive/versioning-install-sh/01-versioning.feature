Feature: Repo versioning policy - VERSION/CHANGELOG.md track agents/, and now install.sh
  # Layer: repo policy documentation (AGENTS.md + CLAUDE.md, which duplicate
  # each other and must stay in sync). This is a NEW standalone domain: no
  # governing spec exists in spdd/specs/ (it contains only set-model.md, the
  # /antz-set-model command domain, which does not cover repo policy). The
  # verifier therefore creates spdd/specs/versioning.md at merge and merges
  # every scenario below into it as ADD - there is nothing to MODIFY or
  # REMOVE. See README.md "Governing spec situation".
  #
  # Change shape: docs-only. NO VERSION bump, NO CHANGELOG.md entry for this
  # change itself (that is the preserved docs-only clause, worked through by
  # dogfooding), and NO edit to install.sh of any kind (see Invariants).
  #
  # The coder's unit-level test suite asserts the documented content (a new
  # tests/versioning-rule_test.sh is the natural vehicle; precedent:
  # tests/set-model-command_test.sh), tagging every test name with its
  # versioning-<index> id.

  Background:
    Given the repo files "AGENTS.md" and "CLAUDE.md", each carrying a
      "## Versioning" section whose first bullet currently reads: "VERSION
      (semver) and CHANGELOG.md (Keep a Changelog format) track changes to
      agents/prompts/ and agents/meta/. Any commit that changes those
      directories must bump VERSION and add a matching CHANGELOG.md entry in
      the same commit - patch for non-behavioral wording tweaks, minor for
      behavior changes, major for breaking changes to the workflow contract
      (directory layout, access model, etc). Changes elsewhere (install.sh,
      docs) don't require a bump."
    And the section's second bullet (marker embedding, --check report) and
      third bullet (local vX.Y.Z tag per bump) exist and must survive this
      change with unchanged meaning
    And "install.sh" renders every installed agent and command file with an
      "antz:generated version=X.Y.Z" marker comment embedding the source
      VERSION, and "./install.sh --check" compares the installed specifier
      agent copy's embedded version against the source VERSION, printing the
      intervening CHANGELOG.md entries when they differ

  # ADD - versioning-01: the tracked set expands to include install.sh, and
  # the same-commit requirement carries over verbatim in structure. A commit
  # is bump-mandatory if it touches ANY of the three, regardless of what else
  # it contains (docs, tests, spdd/ - mixed commits are still bump commits).
  Scenario: versioning-01
    When the reader reads the "## Versioning" section of AGENTS.md
    Then it states that "VERSION" (semver) and "CHANGELOG.md" (Keep a
      Changelog format) track changes to "agents/prompts/", "agents/meta/",
      and "install.sh"
    And it states that any commit that changes any of those three must bump
      "VERSION" and add a matching "CHANGELOG.md" entry in the same commit
    And the same-commit bump requirement holds regardless of what else the
      commit changes - a commit touching "agents/" and/or "install.sh"
      together with docs or tests is still a bump commit

  # ADD - versioning-02: the wrong sentence is gone, and nothing equivalent
  # takes its place. The old sentence singled out install.sh as bump-exempt;
  # any wording with that effect must disappear from both files.
  Scenario: versioning-02
    When the reader reads AGENTS.md and CLAUDE.md in full
    Then neither file contains the sentence "Changes elsewhere (install.sh,
      docs) don't require a bump"
    And neither file contains any other statement that a change to
      "install.sh" is exempt from the "VERSION"/"CHANGELOG.md" bump
      requirement

  # ADD - versioning-03: the docs-only no-bump clause is preserved
  # explicitly, not left to inference from the removal of the old sentence.
  # The stated rule must resolve every row of the table unambiguously - a
  # reader applying it to a real commit never lands on "unclear". Note the
  # first row pair: this very change is the worked example (docs-only commit,
  # no bump).
  Scenario Outline: versioning-03
    When the reader reads the "## Versioning" section of AGENTS.md (and
      CLAUDE.md)
    Then it explicitly states which paths are NOT tracked and require no
      "VERSION"/"CHANGELOG.md" bump
    And the stated rule resolves the row's commit as: <resolution>

    Examples:
      | a commit that changes only            | resolution                                             |
      | agents/prompts/                       | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | agents/meta/                          | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | install.sh                            | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | agents/ and install.sh in one commit  | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | AGENTS.md, CLAUDE.md, docs/, or spdd/ | no VERSION bump and no CHANGELOG.md entry             |
      | tests/                                | no VERSION bump and no CHANGELOG.md entry             |

  # ADD - versioning-04: the gradation applies to install.sh changes exactly
  # as the existing gradation applies to agents/ changes - one scale, not a
  # second rubric. The rows pin the boundary of each grade with concrete
  # install.sh-shaped examples. A commit touching several tracked paths is
  # graded by its most severe component.
  Scenario Outline: versioning-04
    When the reader reads the "## Versioning" section
    Then it applies the same patch/minor/major scale to "install.sh" changes
      as to "agents/" changes
    And it grades the row's install.sh-only change as a <grade> bump

    Examples:
      | install.sh-only change                                                                                                                             | grade |
      | wording-only tweak: comment, usage/echo string, or internal refactor with no change to rendered output or reported behavior                        | patch |
      | behavior change: rendered agent/command bodies, flags, install paths, detection logic, or the --check report change                                 | minor |
      | breaking change to the workflow contract or the rendered command contract (e.g. the "antz:generated" marker format the /antz-set-model management check depends on, or the access-to-frontmatter mapping) | major |

  # ADD - versioning-05: the rationale is recorded in the section, so a
  # future maintainer can re-derive the rule instead of relitigating it. The
  # rationale must not promise any new machinery: it relies on the existing
  # marker/version/--check behavior, unchanged by this change.
  Scenario: versioning-05
    When the reader reads the "## Versioning" section
    Then it records why "install.sh" is tracked: "install.sh" renders the
      installed agent and command files directly and embeds the source
      "VERSION" in each installed file's "antz:generated" marker comment
    And it records that without a bump, "./install.sh --check"'s version
      comparison reports no drift, so installed command/agent copies
      silently go stale after an install.sh-only change - the only defense
      is the documented bump rule

  # ADD - versioning-06: the two policy docs stay in sync - they duplicate
  # each other today, and the rule must not fork between them.
  Scenario: versioning-06
    When the reader compares the "## Versioning" sections of AGENTS.md and
      CLAUDE.md
    Then they state the identical rule: same tracked set, same same-commit
      bump requirement, same preserved docs-only no-bump clause, same
      gradation
    And a future rule change updates both files in the same commit - neither
      file may lag the other

  # ADD - versioning-07: the section's other two bullets survive with
  # unchanged meaning, and the tag rule now covers install.sh-mandated bumps
  # without being reworded.
  Scenario: versioning-07
    When the reader reads the "## Versioning" section
    Then it still states that "install.sh" embeds the source "VERSION" in
      each installed file's marker comment, that every run compares the
      installed copy's embedded version and prints the intervening
      "CHANGELOG.md" entries when newer, and that "./install.sh --check"
      only prints that report without writing files
    And it still states that every "VERSION" bump gets a local "vX.Y.Z" git
      tag created against the bumping commit, tags not pushed automatically -
      now applying to install.sh-mandated bumps as well

  ## Invariants
  - This change edits ONLY "AGENTS.md" and "CLAUDE.md" (the "## Versioning"
    first bullet) plus the single scope line of "CHANGELOG.md" (see README.md
    decision 3). "install.sh" is byte-for-byte untouched - including its
    header comment at install.sh:21, which restates the OLD tracked set
    ("VERSION + CHANGELOG.md track changes to agents/prompts/ and
    agents/meta/.") and is accepted, recorded drift (README.md decision 2).
  - No "VERSION" bump and no "CHANGELOG.md" entry accompanies this change
    itself: its diff is docs-only, which the new rule classifies as no-bump
    (worked example for versioning-03's "AGENTS.md, CLAUDE.md, docs/, or
    spdd/" row).
  - The new rule is forward-looking. It mandates no retroactive "CHANGELOG.md"
    entries or tags for past install.sh-only changes (notably
    set-model-interactive-picker, shipped without a bump - README.md decision
    5), and no rewrite of history in "spdd/specs/" or "spdd/archive/".
  - "VERSION"/"CHANGELOG.md" edits that ARE a bump are part of that bump,
    never separately tracked changes requiring a further bump.
  - Mixed-commit grading (versioning-04): the commit's grade is the most
    severe component's grade.
  - The rule is policy documentation only. Nothing in this change adds
    mechanical enforcement (no script, hook, or CI check verifying bumps);
    enforcement is the maintainer's discipline plus the existing --check
    report.

  ## Out of scope
  - Any edit to "install.sh" (including its stale line-21 header comment),
    "agents/prompts/", "agents/meta/", "VERSION", "tests/", "docs/",
    "spdd/specs/", or "spdd/archive/".
  - Any behavioral change to "install.sh"'s marker/version/--check machinery
    - it already fully supports the new rule (README.md "Non-goal").
  - Extending the tracked set beyond "agents/prompts/", "agents/meta/", and
    "install.sh" ("tests/" and "spdd/" stay untracked).
  - Retroactive entries, tags, or version renumbering for past changes.
  - Mechanical bump enforcement (CI/pre-commit).

  ## Merge mapping (for the verifier)
  | Scenario     | Tag | Merge action                                                              |
  | versioning-01| ADD | Create spdd/specs/versioning.md (new domain); add the scenario            |
  | versioning-02| ADD | Append to the new domain spec                                             |
  | versioning-03| ADD | Append (Scenario Outline + Examples table)                                |
  | versioning-04| ADD | Append (Scenario Outline + Examples table)                                |
  | versioning-05| ADD | Append                                                                    |
  | versioning-06| ADD | Append                                                                    |
  | versioning-07| ADD | Append                                                                    |
