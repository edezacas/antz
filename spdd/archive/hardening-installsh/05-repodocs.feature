# Domain: repo-docs (new)

## Feature: AGENTS.md/CLAUDE.md describe the real spdd/ directory state

  Background:
    Given the repo's two policy docs, AGENTS.md and CLAUDE.md, whose
      Structure sections duplicate each other
    And the line under correction currently claims "spdd/{changes,specs,
      archive}/ -- not present yet; created on first run of the workflow",
      which is false: the three directories exist in the checkout, and
      spdd/specs/ and spdd/archive/ hold content

  # ADD - repodocs-01: the Structure bullet states the real state: the
  # three directories exist in the checkout today; spdd/changes/ holds
  # in-flight changes (empty between flows, since approved changes are
  # archived out); spdd/specs/ holds the governing per-domain spec files;
  # spdd/archive/ holds the archived changes. The ownership half of the
  # old line stays true and is kept: the specifier creates
  # spdd/changes/<slug>/, the verifier creates/updates spdd/specs/ and
  # moves approved changes to spdd/archive/.
  Scenario: repodocs-01
    When the reader reads the "spdd/" bullet in AGENTS.md's Structure
      section
    Then it no longer claims the directories are absent or created on
      first run
    And it states the three directories exist in the checkout, with
      spdd/changes/ holding in-flight changes (empty between flows),
      spdd/specs/ holding the governing per-domain specs, and
      spdd/archive/ holding the archived changes
    And it still states who creates what: the specifier creates
      "spdd/changes/<slug>/"; the verifier creates/updates "spdd/specs/"
      and moves approved changes to "spdd/archive/"

  # ADD - repodocs-02: the two policy docs stay in sync: the corrected
  # bullet is byte-identical between AGENTS.md and CLAUDE.md (the docs
  # duplicate each other and must not fork on this line).
  Scenario: repodocs-02
    When the reader compares the "spdd/" Structure bullet in AGENTS.md
      with the one in CLAUDE.md
    Then they are byte-for-byte identical

  # ADD - repodocs-03: the false claim is gone everywhere: neither policy
  # doc says "not present yet" about spdd/ (or otherwise states the spdd/
  # directories do not exist yet).
  Scenario: repodocs-03
    When the reader reads AGENTS.md and CLAUDE.md in full
    Then neither file contains "not present yet" in connection with the
      "spdd/" directories
    And neither file states anywhere that "spdd/specs/" or
      "spdd/archive/" do not exist yet

### Invariants
- Every other bullet in both policy docs is untouched by this sub-spec:
  the many byte-identity pins on the access-model, skills-activation,
  branch-marker, release-gating, receipts, closing-block, and
  slug-derivation bullets, and on the "## Versioning" sections, all stay
  green unmodified.
- The docs-only clause of the versioning policy applies to this sub-spec
  alone; the change as a whole bumps because it touches install.sh (see
  the bump470 sub-spec).
- The Overview sentences ("No application code lives here yet") are a
  different claim about a different subject and are NOT corrected here --
  that evaluation is a separate decision per the plan.

## Out of scope
- Any edit to AGENTS.md/CLAUDE.md beyond the one "spdd/" Structure bullet
  (the Client Integration RAW_BASE bullet is sub-spec 03's edit).
- Unifying the two policy docs into a single source for their
  byte-identical portions (explicitly a separate decision per the plan).
- Any change to spdd/specs/ or spdd/archive/ content itself.
