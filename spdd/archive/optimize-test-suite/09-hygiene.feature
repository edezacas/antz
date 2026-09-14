# Sub-spec 09 — hygiene guard-rails (revised scope: the four permanent laws)
# Destination domain: `test-runner`. Dependency order: 9 (last — every
# other sub-spec's suite exists to be scanned).
# Revised scope, superseding the earlier draft in full: the suite asserts
# exactly the four permanent laws below, as mechanical, hermetic scans
# over `tests/` that hold in the committed-and-archived era. All
# history/evolution calibration is deleted, not relocated — the
# merge-base-era gate, the formerly-red-suite inventory, and the
# in-flight-change scan are gone. The version check is not 09's:
# sub-spec 05 owns it in its own suite, and no scan here re-pins it.

Feature: four permanent laws hold over the whole test area, mechanically
  The area's laws are not left to convention: one hygiene suite scans the
  suite sources and fails loudly when a law is broken. The scans are
  era-independent — they hold identically before and after this change is
  committed and its change directory archived — because none queries the
  working tree's git state or reads its in-flight change content.

  Background:
    Given "tests/hygiene_test.sh", itself a suite picked up by the
      runner's glob, whose scans are pure source scans over a scan root —
      the real "tests/" by default, pointable at a temp fixture copy
    And the discovery contract: a suite is any "tests/*_test.sh" file;
      "tests/bash32-sh.sh" and "tests/harness.sh" are helpers, not suites
    And the carve-outs, applied to every scan: only non-comment lines are
      read; a suite may read its own file; the hygiene suite's own source
      is exempt (it encodes the detection patterns); fixture strings
      naming suite files that do not exist on disk are not references; and
      git operations inside throwaway fixture repositories under temp
      space are not real-tree comparisons
    And no scan passes vacuously: with that scan's violation planted in a
      temp fixture copy of the scan root, the scan fails naming the
      planted file and line

  # ADD - hygiene-01: no suite executes another suite or asserts its
  # content or output.
  Scenario: hygiene-01
    When the suite sources are scanned
    Then no suite source executes another existing tests/*_test.sh file —
      no sh, bash, source, eval, or child-run invocation of it
    And no suite source asserts another existing suite's source content or
      output — no grep, require, or byte-compare against its file;
      "the whole area is green" is answered by the documented runner alone

  # ADD - hygiene-02: no suite compares the real tree against git HEAD.
  Scenario: hygiene-02
    When the suite sources are scanned
    Then no suite source compares the working tree against git HEAD — no
      `git merge-base`, no `show HEAD:`, no `diff --quiet HEAD`, no `cmp`
      against git-extracted content — and no suite byte-pins its own file
      against a git HEAD copy
    And every suite's expectations derive only from the current tree's
      behavior

  # ADD - hygiene-03: no suite pins exact prose phrases of prompts or
  # docs; the Working-Root triplication check is the sole exception.
  Scenario: hygiene-03
    When the suite sources are scanned
    Then no suite source pins an exact prose phrase of a role prompt
      (agents/prompts/) or a doc (docs/, AGENTS.md, CLAUDE.md) — no grep
      of an embedded literal against either, and no byte-compare of
      either's content against embedded expected text
    And a comparison of two live-read files against each other pins no
      phrase and is not a violation
    And the sole declared exception stays green: the Working-Root
      triplication consistency check in "tests/roles_test.sh" — the three
      role prompts' triplicated sections stay byte-identical to each other

  # ADD - hygiene-04: the laws are era-independent — green committed and
  # archived, with no test edit.
  Scenario: hygiene-04
    When the hygiene suite runs against a staged copy of the working tree
      under temp space in which this change is committed and its change
      directory is archived
    Then every scan passes unchanged, as it does in the working tree — no
      scan reads the working tree's spdd/changes/ content, queries its
      git state, or gates on any era
    And committing and archiving this change therefore requires no test
      edit for the suite to stay green

### Invariants
- The hygiene suite is fast, hermetic, and render-free: pure source scans,
  no install.sh invocation, no git query against the working tree, no
  network, no writes outside temp space.
- The scans fail loudly naming the offending file and line, so a regrown
  violation is actionable.
- Conformance is the revised scope's deletion law: residual sites in
  retained suites that break these laws (git-HEAD comparisons, prose
  pins) are deleted by their owning suites per the revision — the scans
  are the permanent guard that none regrow.
- Reported test names carry the hygiene ids declared here, per the repo
  convention.

## Out of scope
- The version check: sub-spec 05 owns it in its own suite; no hygiene scan
  re-pins VERSION or CHANGELOG.md assertions.
- Re-pinning any deleted suite's content: the scans assert the four laws,
  never a named deleted suite's ids, wording, or inventory.
