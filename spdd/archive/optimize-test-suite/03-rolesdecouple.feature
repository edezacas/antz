# Sub-spec 03 — decouple roles_test.sh from the other suites
# Destination domain: `role-surfaces` (the modified/removed ids live there;
# testsuite-08 is currently spec-orphaned and lands here, its suite's home
# domain). Dependency order: 3 (requires the harness library for the
# retained render half; enables runner-01's exactly-once guarantee).

Feature: roles_test.sh stops executing other suites and pinning their
  wording
  roles_test.sh carries five coupling sites: testsuite-08 glob-runs every
  other suite and scans all suite sources for retired idioms; roles-05
  reruns three suites, observes their output, greps every suite for removed
  wording, and requires another suite's source; verifier-02 reruns the
  probe suite; terminology-03 reruns five suites; rolechecks-05 byte-
  compares roles test functions against git HEAD copies and reruns the
  roles suite. Each site's product coverage lives in the owning suite or
  in the site's own retained halves.

  Background:
    Given "tests/roles_test.sh", whose retained scenario ids are roles-01..
      roles-04, terminology-01..03, verifier-01..02, testsuite-06, and
      testsuite-08
    And the decoupling law: no suite executes another suite, and no suite
      asserts another test file's source content or output — verifying
      "the whole suite is green" is the documented runner's job
    And that the suites execute their installs only through the harness
      library's render helpers

  # ADD - rolesdecouple-01: testsuite-08 keeps its product halves and drops
  # the glob half and the idiom scan.
  Scenario: rolesdecouple-01
    When testsuite-08 runs
    Then it executes no other suite and scans no tests/*_test.sh source
      (the recursion-guard flag and the excluded-suite cases are gone with
      the glob)
    And it still asserts, from one hermetic render through the harness
      library: no role prompt carries an "# antz-include:" marker or a
      script-content fence, the four orchestration scripts install under
      the resolved libdir, and no rendered client file carries a fence or
      an include marker
    And every other id the suite registered before the refactor stays
      registered and green

  # ADD - rolesdecouple-02: roles-05 is removed whole — every clause is
  # cross-test coupling (a skills-suite rerun, observation of its
  # retirement notes, a wording grep across all suites, a require on
  # another suite's source, and reruns of two more suites).
  Scenario: rolesdecouple-02
    When the roles suite runs
    Then roles-05 is no longer registered
    And no line of roles_test.sh executes skills-activation-prompts,
      receipts, or closingblock suites, observes their output, or requires
      their source content
    And roles-01..04 and the suite's other retained ids stay registered
      and green

  # ADD - rolesdecouple-03: verifier-02 keeps its product pins and its
  # frozen-surface guard, drops the probe-suite rerun.
  Scenario: rolesdecouple-03
    When verifier-02 runs
    Then it executes no other suite
    And it still pins the rejection-contract wording on the verifier
      prompt and asserts scripts/orchestration/ and agents/meta/ are
      byte-identical to git HEAD — a frozen-surface guard that is green in
      both the uncommitted and the committed era

  # ADD - rolesdecouple-04: terminology-03 keeps the docs bullet pins and
  # drops the five-suite loop.
  Scenario: rolesdecouple-04
    When terminology-03 runs
    Then it executes no other suite
    And it still asserts that the three role prompts' "## Working Root"
      sections are byte-identical to each other, and that AGENTS.md and
      CLAUDE.md each carry one identical Working-Root-triplication gotcha
      bullet stating the rule

  # ADD - rolesdecouple-05: rolechecks-05 is removed whole — its
  # byte-identity-vs-HEAD on roles test functions and its roles-suite
  # rerun are one-change migration guards; the product content lives in
  # roles-03 and rolechecks-01..04, all retained.
  Scenario: rolesdecouple-05
    When the rolechecks suite runs
    Then rolechecks-05 is no longer registered
    And no line of rolechecks_test.sh executes roles_test.sh or byte-
      compares any of its functions against a git HEAD copy
    And rolechecks-01..04 stay registered and green, unchanged

### Invariants
- No product assertion is lost: the removed sites' verifiable content was
  either cross-test coupling (the runner replaces it) or is retained in the
  owning suite's own scenarios (roles-03's merge-bullet pin, the probe's
  behavior suite, the re-scopes recorded in the merged specs).
- tests/roles_test.sh keeps sourcing the harness library and registering
  its retained ids with unchanged names.
