Feature: specifier.prompt describes an optional Entities/Operations table in the change's README.md
  # Layer: prompt text only -- the "## Output" section of
  # agents/prompts/specifier.prompt. This is a NEW standalone domain: no
  # governing spec exists in spdd/specs/ for the specifier's own Process/
  # Output instructions (spdd/specs/ holds only set-model.md and
  # versioning.md, both product-feature/policy domains, not role-behavior
  # domains). The verifier creates spdd/specs/specifier-role.md at merge (or
  # merges into it, if the independent sibling change
  # specifier-freshness-check already created it) and merges every scenario
  # below into it as ADD -- there is nothing to MODIFY or REMOVE. See
  # README.md "Governing spec situation".
  #
  # Verification: every scenario here is a deterministic content assertion
  # against the static text of agents/prompts/specifier.prompt (grep-style),
  # not a live LLM invocation -- unit-testable by the coder's own suite.
  # e2e-qa.feature covers the live-session behavior this instruction
  # produces (whether a real specifier run includes/omits the table
  # appropriately).

  Background:
    Given "agents/prompts/specifier.prompt" carries a "## Output, written to
      `spdd/changes/<change-slug>/`" section
    And its first bullet currently reads: "Sub-specs covering goal, contract,
      tagged Gherkin scenarios, invariants, and out-of-scope."
    And the "## Specification Rules" section already states: "Use example
      tables for varying fields, pruning columns where every row is
      identical and adds no acceptance value."

  # ADD - entities-table-01: the Output section states the option to
  # include a structured Entities/Operations table when a change introduces
  # a new data shape or multiple named operations.
  Scenario: entities-table-01
    When the reader reads the "## Output" section of "agents/prompts/specifier.prompt"
    Then it states that when a change introduces a new data shape (entity, model, or interface) or multiple named operations (endpoints, CLI commands/flags, steps, events), the specifier may optionally include a structured table in the change's "README.md"

  # ADD - entities-table-02: the exact column sets are specified for each
  # table kind.
  Scenario: entities-table-02
    When the reader reads the "## Output" section
    Then it states the entities table's columns as "Name", "Path", "New-or-Existing", "Notes"
    And it states the operations table's columns as "Type", "Identifier", "Description"

  # ADD - entities-table-03: the table is a scannable complement, never a
  # replacement for the Gherkin scenarios.
  Scenario: entities-table-03
    When the reader reads the "## Output" section
    Then it states that this table is a scannable complement to the prose contract sections
    And it states that the Gherkin scenarios remain the actual testable behavior spec, never replaced by the table

  # ADD - entities-table-04: the table is optional per change, never
  # mandatory -- explicitly not forced when there is no new data shape and
  # at most one operation.
  Scenario: entities-table-04
    When the reader reads the "## Output" section
    Then it states the table is not mandatory for every change
    And it states that a change with no new data shape and only one operation should not be forced to produce a near-empty table

  # ADD - entities-table-05: the rigid "fill every section or mark not
  # applicable" behavior of the open-spdd canvas template is explicitly not
  # adopted -- only the table format itself is.
  Scenario: entities-table-05
    When the reader reads the "## Output" section
    Then it does not require marking every section "not applicable" when empty
    And it does not mandate filling a table regardless of relevance
    And it states that only the table format is adopted as an available tool, not a rigid always-fill-every-section requirement

  ### Invariants
  - This sub-spec touches only the "## Output" section of
    "agents/prompts/specifier.prompt"; the "## Process" section is untouched
    here (see the independent, sibling change specifier-freshness-check).
  - Column pruning (dropping a column where every row is identical and adds
    no acceptance value) reuses the existing "## Specification Rules"
    example-table pruning bullet -- no new pruning rule is introduced for
    this table.
  - See README.md Invariants for the shared cross-cutting invariants
    (no change to other role prompts, install.sh, or agents/meta/*.yaml).

  ### Out of scope
  - See README.md Out of scope (shared across this whole change).
