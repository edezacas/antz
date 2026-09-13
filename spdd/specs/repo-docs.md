# Domain: repo-docs

## Origin
- Specced and delivered from change `hardening-installsh` (Cambio E of
  `docs/plan-revision-2026-09.md`, section 3). This domain corrects the
  false "not present yet" claim in `AGENTS.md` and `CLAUDE.md`'s Structure
  section about `spdd/`.

## Goal
The repo's two policy docs (`AGENTS.md` and `CLAUDE.md`) describe the real
state of the `spdd/` directory tree: all three subdirectories exist in the
checkout today. The corrected bullet states what each holds and who creates
what, byte-identical between the two files.

## Feature: AGENTS.md/CLAUDE.md describe the real spdd/ directory state

  Background:
    Given the repo's two policy docs, AGENTS.md and CLAUDE.md, whose
      Structure sections duplicate each other
    And the line under correction currently claims "spdd/{changes,specs,
      archive}/ -- not present yet; created on first run of the workflow",
      which is false: the three directories exist in the checkout, and
      spdd/specs/ and spdd/archive/ hold content

  # ADD - repodocs-01: the Structure bullet states the real state
  Scenario: repodocs-01
    When the reader reads the "spdd/" bullet in AGENTS.md's Structure
      section
    Then it no longer claims the directories are absent or created on
      first run
    And it states the three directories exist in the checkout, with
      spdd/changes/ holding in-flight changes (empty between flows),
      spdd/specs/ holding the governing per-domain spec files, and
      spdd/archive/ holding the archived changes
    And it still states who creates what: the specifier creates
      "spdd/changes/<slug>/"; the verifier creates/updates "spdd/specs/"
      and moves approved changes to "spdd/archive/"

  # ADD - repodocs-02: byte-identical between the two files
  Scenario: repodocs-02
    When the reader compares the "spdd/" Structure bullet in AGENTS.md
      with the one in CLAUDE.md
    Then they are byte-for-byte identical

  # ADD - repodocs-03: false claim is gone everywhere
  Scenario: repodocs-03
    When the reader reads AGENTS.md and CLAUDE.md in full
    Then neither file contains "not present yet" in connection with the
      "spdd/" directories
    And neither file states anywhere that "spdd/specs/" or
      "spdd/archive/" do not exist yet

### Invariants
- Every other bullet in both policy docs is untouched by this sub-spec.
- The docs-only clause of the versioning policy applies to this sub-spec
  alone.
- The Overview sentences ("No application code lives here yet") are a
  different claim and are NOT corrected here.

## Out of scope
- Any edit beyond the one "spdd/" Structure bullet (the Client Integration
  RAW_BASE bullet is the refpin sub-spec's edit).
- Unifying the two policy docs into a single source.
- Any change to `spdd/specs/` or `spdd/archive/` content itself.

## Relevant files
- `AGENTS.md` and `CLAUDE.md` — the `spdd/` Structure bullet in each.
- `tests/repodocs_test.sh` — self-contained test suite tagging the scenario ids.
