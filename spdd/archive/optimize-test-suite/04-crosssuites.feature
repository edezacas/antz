# Sub-spec 04 — decouple the remaining cross-suite sites
# Destination domain: `install-render` (quoting-05's home; the coder-04
# re-scope merges into `spdd/specs/receipts.md`, the conventions-04 and
# specifier-02 removals into `spdd/specs/specifier-role.md`, and the
# setmodeldeembed-05 removal into `spdd/specs/posixsh.md`). Dependency
# order: 4 (requires the harness library; independent of sub-spec 03's
# file).

Feature: the remaining cross-suite execution and wording pins are removed
  Outside roles_test.sh, five more sites couple suites to each other:
  quoting-05 glob-runs every suite and greps two suite sources; the
  closingblock suite's coder-04 reruns receipts and byte-pins it against
  git HEAD; conventions-04 is a meta-test that runs two other suites eight
  times across real and fixture trees; entities-operations-table's
  specifier-02 re-executes its own whole suite in a child process and runs
  two more suites; setmodeldeembed-05 greps two suite sources and reruns
  both.

  Background:
    Given the decoupling law: no suite executes another suite, and no
      suite asserts another test file's source content or output
    And that each site's product coverage lives in the owning suite and is
      retained (stated per scenario)

  # ADD - crosssuites-01: quoting-05 is removed whole.
  Scenario: crosssuites-01
    When the description-quoting suite runs
    Then quoting-05 is no longer registered: no glob over tests/*_test.sh,
      no grep of the renderinject or skills-activation-render suite
      sources, and no recursion-guard flag
    And quoting-01..04 stay registered and green, unchanged

  # ADD - crosssuites-02: coder-04 keeps its own-source extract pins and
  # drops the receipts rerun and byte-pin.
  Scenario: crosssuites-02
    When the closingblock suite runs
    Then coder-04 executes no other suite and byte-compares no other test
      file against a git HEAD copy
    And coder-04 still asserts, from closingblock_test.sh's own source,
      that the coder-report extract is keyed on the Receipt heading and
      the verifier and orchestrator extract lines are unchanged
    And closingblock-01..07 and coder-01..03 stay registered and green

  # ADD - crosssuites-03: conventions-04 is removed whole — all its
  # registrations run other suites (real tree and fixture checkouts) and
  # observe their output; the gating behavior they meta-tested stays
  # green in the owning suites and needs no second suite to vouch for it.
  Scenario: crosssuites-03
    When the conventions suite runs
    Then conventions-04 is no longer registered: no run of the
      skills-activation-prompts or closingblock suites against the real
      tree or against fixture checkouts, and no observation of their
      output or registrations
    And conventions-01..03 stay registered and green, unchanged

  # ADD - crosssuites-04: specifier-02 is removed whole — it re-executes
  # the suite itself in a child process and runs two more suites; the
  # table bullets' product pins are specifier-01 and the retained
  # entities-table ids.
  Scenario: crosssuites-04
    When the entities-operations-table suite runs
    Then specifier-02 is no longer registered: no self-rerun of the suite
      (the child-run guard flag is gone with it), no run of the readmefile
      or conventions suites, and no observation of their output or
      registrations
    And entities-table-01..05 and specifier-01 stay registered and green

  # ADD - crosssuites-05: setmodeldeembed-05 is removed whole.
  Scenario: crosssuites-05
    When the setmodeldeembed suite runs
    Then setmodeldeembed-05 is no longer registered: no grep of the
      set-model-command or installsh-posixsh suite sources and no
      execution of either suite
    And setmodeldeembed-01..04 and setmodeldeembed-06 stay registered and
      green; the product clauses it used to observe are pinned by their
      owning suites (the installed-libdir run by set-model-command's
      setmodel-01..04, the re-keyed installed-file assertion by
      posixsh-04)

### Invariants
- The retained ids keep their names and their assertions; only the
  coupling clauses disappear.
- Dead fixture machinery left behind by a removed meta-test
  (conventions-04's fixture builders and suite-path variables) is removed
  with it, not left as unreachable code.
