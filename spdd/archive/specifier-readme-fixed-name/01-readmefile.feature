Feature: specifier.prompt fixes README.md as the change's overview file for the whole Output section
  # Layer: prompt text only -- the "## Output" section of
  # agents/prompts/specifier.prompt. This extends the existing domain
  # spdd/specs/specifier-role.md (created by the sibling change
  # specifier-entities-operations-table), which already covers part of this
  # same section (entities-table-01..05). See README.md "Governing spec
  # situation" for the exact ADD/MODIFY mapping.
  #
  # Verification: every scenario here is a deterministic content assertion
  # against the static text of agents/prompts/specifier.prompt (grep-style),
  # not a live LLM invocation -- unit-testable by the coder's own suite.
  # e2e-qa.feature covers the live-session behavior this instruction
  # produces (whether a real specifier run actually names its overview file
  # README.md).

  Background:
    Given "agents/prompts/specifier.prompt" carries a "## Output, written to
      `spdd/changes/<change-slug>/`" section
    And its first bullet reads: "Sub-specs covering goal, contract, tagged
      Gherkin scenarios, invariants, and out-of-scope." (unchanged by this
      sub-spec)
    And its Entities/Operations table bullet currently reads, in full: "When
      a change introduces a new data shape (entity, model, or interface) or
      multiple named operations (endpoints, CLI commands/flags, steps,
      events), you may optionally include a structured table in the change's
      `README.md`: an entities table with columns Name, Path,
      New-or-Existing, Notes, and/or an operations table with columns Type,
      Identifier, Description, pruning columns per the Specification Rules'
      example-table rule. This table is a scannable complement to the prose
      contract sections — the tagged Gherkin scenarios remain the actual
      testable behavior spec, never replaced by the table."
    And its open-questions bullet already fixes a different file the same
      way this change fixes the overview file: "Write open questions, if
      any, to the fixed file `spdd/changes/<change-slug>/OPEN_QUESTIONS.md`
      rather than inlining them elsewhere, and only create it when something
      is actually blocked."

  ## New: the overview file is fixed at the whole-Output-section level

  # ADD - readmefile-01: a dedicated bullet states that the change's
  # overview content -- not only the optional Entities/Operations table --
  # is written to the fixed file README.md.
  Scenario: readmefile-01
    When the reader reads the "## Output" section of "agents/prompts/specifier.prompt"
    Then it states that the change's overview -- goal, contract, shared contracts, invariants, out-of-scope, and relevant-files pointers -- is written to the fixed file "README.md"
    And this statement is its own bullet, not scoped only to the Entities/Operations table bullet

  # ADD - readmefile-02: the fixed name is stated once, directly -- no
  # repetition within or across bullets.
  Scenario: readmefile-02
    When the reader counts occurrences of the literal string "README.md" within the "## Output" section
    Then it appears exactly once
    And no single bullet contains the literal string "README.md" more than once

  # ADD - readmefile-03: no rejected alternative names are enumerated or
  # discussed -- the fixed name is stated directly, the same way
  # OPEN_QUESTIONS.md and REJECTED.md are each introduced elsewhere in this
  # repo's prompts.
  Scenario: readmefile-03
    When the reader reads the "## Output" section
    Then it does not contain the literal strings "OVERVIEW.md", "SUMMARY.md", or "NOTES.md"
    And it does not explain or justify why "README.md" was chosen over any alternative name

  ## Modified: the Entities/Operations table bullet no longer repeats the name

  # MODIFY - entities-table-01: the bullet introducing the optional
  # Entities/Operations table keeps stating the same trigger condition (new
  # data shape or multiple named operations) but no longer separately names
  # README.md itself -- it relies on the Output section's own new fixed-file
  # bullet instead.
  # entities-table-02..05 (column sets, complement statement, optionality,
  # canvas-rigidity rejection) are unaffected and keep their existing text.
  Scenario: entities-table-01
    When the reader reads the "## Output" section of "agents/prompts/specifier.prompt"
    Then it states that when a change introduces a new data shape (entity, model, or interface) or multiple named operations (endpoints, CLI commands/flags, steps, events), the specifier may optionally add a structured table
    And the bullet introducing this table does not itself contain the literal string "README.md"

  ### Invariants
  - This sub-spec touches only the "## Output" section of
    "agents/prompts/specifier.prompt"; the "## Process" section is untouched
    here (see the independent, sibling change specifier-freshness-check).
  - The existing first bullet of "## Output" is left byte-for-byte
    unchanged -- the new bullet is inserted after it, not merged into it.
  - entities-table-02..05 are unaffected; only entities-table-01's filename
    clause changes.
  - See README.md Invariants for the shared cross-cutting invariants (no
    change to other role prompts, install.sh, or agents/meta/*.yaml; no
    enumeration of rejected names).

  ### Out of scope
  - See README.md Out of scope (shared across this whole change).
