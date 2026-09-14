# Sub-spec 05 — version-current check (revised scope: history-free)
# Destination domain: `versioning`. Dependency order: 5 (independent of
# sub-specs 02-04; the runner picks the new suite up and drops the deleted
# ones mechanically via the tests/*_test.sh glob — no runner edit).
# Supersedes the former 05-versionhistory.feature in full: the suite area
# tests ONLY the current version's behavior; all history/evolution
# calibration and prose pins are deleted, not relocated.

Feature: the suite area tests only the current version's behavior
  All frozen-history version suites are deleted — the nine per-version
  bump suites plus the prose-pinning versioning-rule suite — and the
  interim consolidated history suite is deleted with them, its history
  and evolution checks re-pinned nowhere. What survives is one dedicated
  version-current suite carrying exactly two version assertions: VERSION
  is a semver, and it agrees with the newest CHANGELOG.md entry. A future
  bump therefore requires no test edit, for exactly as long as those two
  assertions stay true.

  Background:
    Given the re-scoped law: the test area pins no version history — no
      append-only guarantee, no entry ordering/uniqueness/dating check,
      no git-HEAD comparison, no per-version content pin
    And the change is tests-only: agents/, install.sh,
      scripts/orchestration/, and spdd/specs/ stay byte-identical, and
      VERSION and CHANGELOG.md are read-only for every test
    And the check suite "tests/versioncurrent_test.sh" is hermetic and
      render-free: it reads only VERSION and CHANGELOG.md of the tree
      under test — no install.sh invocation, no network, no git query —
      and any staged fixture tree lives in temp space per the harness

  # ADD - versioncurrent-01: the frozen-history suites are gone and their
  # unique ids are registered by no suite.
  Scenario: versioncurrent-01
    When the test area is scanned
    Then the files bump440_test.sh, bump450_test.sh, bump460_test.sh,
      bump470_test.sh, bump471_test.sh, bump480_test.sh,
      skills-activation-bump_test.sh, skills-desc-match-bump_test.sh,
      docs-bump_test.sh, versioning-rule_test.sh, and the interim
      changelog-history_test.sh no longer exist under tests/
    And no suite registers a test whose id is bump440-01..02,
      bump450-01..02, bump460-01..02, bump470-01..02, bump471-01..02,
      bump421-01..02, versionbump-01..03, bump-01..03, versioning-01..07,
      or versionhistory-01..05
    And access-model_test.sh still registers meta-01..03, render-01..04,
      and docs-01..04, with its bump-01..03 still retired

  # ADD - versioncurrent-02: the one version check is exactly two
  # assertions.
  Scenario: versioncurrent-02
    When tests/versioncurrent_test.sh runs its version check
    Then it carries exactly two assertions: VERSION's entire content is
      a semver X.Y.Z plus one trailing newline, and VERSION equals the
      version in the newest (topmost) "## [X.Y.Z] - <date>" heading of
      CHANGELOG.md
    And the agreement assertion is relative — it binds whatever VERSION
      and CHANGELOG.md the tree under test carries, never a literal
      version

  # ADD - versioncurrent-03: a future bump needs no test edit, only the
  # two assertions staying true.
  Scenario: versioncurrent-03
    When a staged copy of the working tree prepends a new dated
      "## [X.Y.Z]" entry atop CHANGELOG.md and bumps VERSION to match it
    Then the version check passes from that staged tree with no edit to
      the suite
    And the inverse holds: with VERSION bumped but no new entry added,
      the check fails — it never passes vacuously

### Invariants
- tests/versioncurrent_test.sh is the only home of a version assertion in
  the area: exactly the two assertions of versioncurrent-02; no
  append-only, ordering, dating, uniqueness, history, or git-HEAD check
  exists in any suite, and none regrows.
- Hermetic and render-free throughout: no install.sh invocation, no
  network, no git query; fixture trees are staged copies under temp space
  (harness helpers), and the working tree's own files are never mutated
  by a test.
- Reported test names carry the versioncurrent ids declared here, per the
  repo convention.
- Of the deleted coverage, only the current-version guarantees (semver
  shape, VERSION-to-newest-entry agreement) survive, inside
  versioncurrent-02; everything else — history, evolution calibration,
  prose pins — is deleted outright, with past versions recorded only in
  CHANGELOG.md itself and the merged versioning domain spec.

## Out of scope
- Any VERSION or CHANGELOG.md edit (tests-only change; the versioning
  policy's docs-only clause mandates no bump, and none is introduced).
- Reinstating any per-version or history pin (append-only, ordering,
  dating, uniqueness, git-HEAD comparisons) — deliberately removed by
  this re-scope, not lost by accident.
- The versioning policy's prose in AGENTS.md/CLAUDE.md: versioning-rule's
  prose pins are deleted outright; docs are not edited by this change.
- The hygiene suite (sub-spec 09) and any other suite's content — the
  version check lives in this sub-spec's own dedicated suite, not in
  hygiene.
