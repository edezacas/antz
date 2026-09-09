# Domain: specifier-role

## Origin
- Specced and delivered from change `specifier-entities-operations-table`
  (merged 2026-09-09). This is a **new standalone spec domain**: before this
  change, `spdd/specs/` held only `set-model.md` and `versioning.md`, both
  product-feature/policy domains — no governing spec covered any of the four
  role prompts' own Process/Output behavior. This file now covers the
  specifier's `## Output` section addition delivered by that change. The
  change's scenarios and end-to-end QA are preserved for history in
  `spdd/archive/specifier-entities-operations-table/`, not reproduced here.
- The independent, sibling change `specifier-freshness-check` (not yet
  merged as of this writing) is expected to add scenarios to this same
  domain file, covering the specifier's `## Process` section instead (a
  mechanical freshness/drift check) — a disjoint section of the same
  `agents/prompts/specifier.prompt` file, with no dependency in either
  direction on the table addition below.

## Goal
`agents/prompts/specifier.prompt`'s `## Output` section documents an
optional, structured Entities/Operations table the specifier may add to a
change's `README.md`, informed by a comparative review against a sibling
project (`open-spdd`'s `spdd-canvas` skill):

- **When offered.** A change that introduces a new data shape (entity,
  model, or interface) or multiple named operations (endpoints, CLI
  commands/flags, steps, events) may get a structured, scannable table in
  the change's `README.md`.
- **Fixed columns.** Entities table: Name, Path, New-or-Existing, Notes.
  Operations table: Type, Identifier, Description. Column pruning (dropping
  a column where every row is identical and adds no acceptance value)
  reuses the existing `## Specification Rules` example-table pruning bullet
  — no new pruning rule was introduced.
- **Never mandatory, never a replacement.** The table is a scannable
  complement to the prose contract sections; the tagged Gherkin scenarios
  remain the actual testable behavior spec, never replaced by the table. A
  change with no new data shape and only one operation is not forced to
  produce a near-empty table, and no section must be marked "not
  applicable" when empty — antz deliberately does not adopt `open-spdd`'s
  canvas-template rigidity (every section filled or marked not applicable);
  only the table format itself is adopted, as an available tool.

## Shared contracts
None — a single sub-spec delivered this domain so far; the table's own
column contract (see Goal above) is defined once, identically, in the
Feature below.

## Feature: specifier.prompt describes an optional Entities/Operations table in the change's README.md

  Background:
    Given "agents/prompts/specifier.prompt" carries a "## Output, written to
      `spdd/changes/<change-slug>/`" section
    And its first bullet reads: "Sub-specs covering goal, contract, tagged
      Gherkin scenarios, invariants, and out-of-scope."
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
- This addition is plain instruction/procedure text within
  `agents/prompts/specifier.prompt`'s existing bullet style (concise
  imperative bullets).
- No new file, script, or scripts-directory convention is introduced.
- No change to `agents/prompts/coder.prompt`, `agents/prompts/verifier.prompt`,
  or `agents/prompts/orchestrator.prompt`.
- No change to `install.sh` or any `agents/meta/*.yaml` (no access/frontmatter
  changes needed).
- Only the `## Output` section of `agents/prompts/specifier.prompt` was
  touched; the `## Process` section is untouched by this domain so far (see
  the independent, sibling `specifier-freshness-check` change for that
  section, expected to extend this file).
- Column pruning (dropping a column where every row is identical and adds
  no acceptance value) reuses the existing `## Specification Rules`
  example-table pruning bullet — no new pruning rule was introduced for this
  table.
- The Entities/Operations table is additive and optional: it never replaces
  or narrows the requirement for tagged Gherkin scenarios as the actual
  testable behavior spec.

## End-to-end QA suite

Operates through the real product "UI" for this role: invoking the
specifier agent (Claude Code "antz-specifier" or OpenCode equivalent) with a
natural-language request, then inspecting the artifacts it writes under
`spdd/changes/<slug>/` — `README.md`, the numbered `.feature` files, and
`OPEN_QUESTIONS.md` (or its absence). For a role whose entire product is
written specification text, these produced files ARE the observable output
of "running the specifier" — there is no other UI surface to exercise. No
internal API calls: every step is either an agent invocation or a file the
invocation produced, read back.

  Background:
    Given a local checkout of a test repo that is a git repository
    And the specifier's own tool grant is "Read, Grep, Glob, Bash" (readonly access, no Write/Edit tool) -- it authors files under spdd/changes/ via Bash

  ## Optional Entities/Operations table (live)

  # ADD - e2e-entities-01: a change introducing a new data shape and
  # multiple named operations gets a scannable table in README.md.
  Scenario: e2e-entities-01
    Given a request that introduces a new "Widget" entity and three named operations ("create", "list", "delete")
    When the user invokes the specifier
    Then "spdd/changes/<slug>/README.md" includes an Entities table with columns "Name", "Path", "New-or-Existing", "Notes" listing "Widget"
    And an Operations table with columns "Type", "Identifier", "Description" listing "create", "list", "delete"
    And the numbered ".feature" files still contain the actual testable behavior for each operation (the table never substitutes for the Gherkin scenarios)

  # ADD - e2e-entities-02: a change with no new data shape and a single
  # operation produces no table, and is not penalized for omitting it.
  Scenario: e2e-entities-02
    Given a request that only tweaks an existing single CLI flag's default value, introducing no new entity and no additional operation
    When the user invokes the specifier
    Then "spdd/changes/<slug>/README.md" contains no Entities/Operations table
    And the produced README.md is not flagged as incomplete for omitting it

## Out of scope
- Any change to `coder.prompt`, `verifier.prompt`, or `orchestrator.prompt`.
- Any change to `install.sh` or `agents/meta/*.yaml`.
- A new script file or scripts directory for role prompts.
- Making the Entities/Operations table mandatory, or requiring every section
  to be filled/marked "not applicable" (explicitly rejecting the open-spdd
  canvas template's rigidity on this point).
- The mechanical freshness/drift check addition to the specifier's
  `## Process` section — that is the independent, sibling change
  `specifier-freshness-check` (no dependency in either direction; both edit
  disjoint sections of the same file), expected to extend this domain file
  separately when it merges.

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/agents/prompts/specifier.prompt` —
  the `## Output` section carrying this domain's instructions.
- `/home/edezacas/Projects/edezacas/antz/tests/entities-operations-table_test.sh` —
  self-contained bash test harness, one test per scenario above
  (entities-table-01..05), tagged with scenario ids in each test's reported
  name; the e2e-only ids (e2e-entities-01/02) appear there as explicit SKIP
  stubs, verified live by the verifier instead (see End-to-end QA suite
  above).
