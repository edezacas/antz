# Change: style-rewrite — sub-spec 01 of 07 (the specifier's triple negation
# becomes the plan's two-line rewrite).
#
# Implements the specifier-side half of Cambio D (docs/plan-revision-2026-09.md
# §3, "Cambio D — style rewrite (patch; semántica intacta)"): the
# Entities/Operations table bullets in `agents/prompts/specifier.prompt`'s
# "## Output" section (the bullets starting "When a change introduces a new
# data shape" and "This table is never mandatory") are replaced by a two-bullet
# rewrite with no stacked negation. The table rules' semantics are unchanged —
# this is a style-only change; the rendered bodies change text only, no
# capability change.
#
# Note on sourcing: the plan cites "the proposal in the external review" for
# the rewrite, but the review itself is not in the repository — only the plan's
# reference to it. The rewrite's outcome and shape are nonetheless fully
# pinned by the plan (two lines, no triple negation, semantics intact) and by
# the pinned semantics of tests/entities-operations-table_test.sh, so this
# sub-spec pins the canonical two-line text deterministically instead of
# blocking on wording.
#
# Scope: agents/prompts/specifier.prompt's two table bullets and
# tests/entities-operations-table_test.sh's re-scope. tests/readmefile_test.sh
# and tests/conventions_test.sh are verified to need no edits (their extracts
# — keyed on the "## Output" heading and other bullets — do not touch the
# rewritten bullets).
#
# Declared destination domain: specifier-role.

Feature: the specifier's Entities/Operations table rule is stated in two positive lines

  Background:
    Given "agents/prompts/specifier.prompt" whose "## Output" section carries
      the two table bullets to be rewritten: the bullet starting "- When a
      change introduces a new data shape" (which stacks "you may optionally
      include" under a trigger sentence) and the bullet starting "- This table
      is never mandatory" (which stacks "should not be forced", "Don't
      require", and "don't mandate")
    And "tests/entities-operations-table_test.sh" pinning both bullets'
      component strings, including the refusal sentinel "You must mark every
      section" and the no-README.md-in-the-table-bullet rule

  # MODIFY - specifier-01: the two table bullets become the plan's two-line
  # rewrite — the triple negation ("you may optionally include... never
  # mandatory... don't require...") is gone, the pinned semantics survive
  # verbatim.
  Scenario: specifier-01
    When the style rewrite replaces the two table bullets with exactly two
      bullets in the "## Output" section
    Then the first bullet starts "- When a change introduces a new data shape"
      and states, in one line, the trigger (a new data shape (entity, model,
      or interface) or multiple named operations (endpoints, CLI
      commands/flags, steps, events)), the two tables with their exact column
      sets ("entities table with columns Name, Path, New-or-Existing, Notes"
      and "operations table with columns Type, Identifier, Description"), and
      column pruning per the Specification Rules' example-table rule
    And the first bullet does not contain the literal string "README.md" (the
      fixed-file bullet remains the one place that names it)
    And the second bullet states, in one line, that the table is a scannable
      complement to the prose contract sections, that the tagged Gherkin
      scenarios remain the actual testable behavior spec, never replaced by
      the table, and that a change with neither a new data shape nor multiple
      named operations includes no table
    And the triple-negation strings no longer appear anywhere in the prompt:
      "you may optionally include", "This table is never mandatory", "should
      not be forced to produce a near-empty table", "Don't require marking
      every section", "don't mandate filling a table", and
      "always-fill-every-section"

  # ADD - specifier-02: the suite pins follow the rewrite loudly — the legacy
  # entities-table pins are re-scoped in place, the semantic pins survive, and
  # the neighboring specifier suites pass unmodified.
  Scenario: specifier-02
    When tests/entities-operations-table_test.sh is updated in the same
      change and runs
    Then the legacy entities-table-01..05 test functions are re-scoped in
      place to the rewritten bullets: the retained pins (the trigger strings,
      both column strings, "scannable complement to the prose contract
      sections", "the tagged Gherkin scenarios remain the actual testable
      behavior spec, never replaced by the table", the no-README.md
      table-bullet refusal, and the "You must mark every section" sentinel)
      keep passing, and the retired strings ("you may optionally include",
      "never mandatory", "should not be forced", "Don't require marking every
      section", "always-fill-every-section") become refusals
    And the suite carries new test functions named after this sub-spec's ids
      (specifier-01 and specifier-02), so a failure maps back to the scenario
    And the suite exits 0
    And tests/readmefile_test.sh and tests/conventions_test.sh pass
      unmodified — their extracts (keyed on the "## Output" heading and on
      bullets this sub-spec does not touch) never read the rewritten bullets

### Invariants
- Semantics are intact: the table's trigger, both column sets, the pruning
  rule, the complement-not-replacement status, and the scenarios' primacy are
  all still stated — only the negation stacking changed.
- The rewrite is exactly two bullets: the optionality is stated positively
  ("includes no table"), not as a stack of not/never/don't.
- The table bullet still never names `README.md`; the Output section's
  fixed-file bullet stays the single place that names it.
- agents/prompts/coder.prompt, agents/prompts/verifier.prompt,
  agents/prompts/orchestrator.prompt, agents/meta/*, install.sh, and
  scripts/orchestration/* are byte-unchanged by this sub-spec.

## Out of scope
- The other three prompts' style edits (sub-specs 02, 03, 04, 05), the
  terminology unification (06), and the version bump (07).
- Any change to the table rules' meaning: the columns, the trigger, or the
  scenarios' primacy are behavior, not style.
