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
- Extended by change `specifier-readme-fixed-name` (merged 2026-09-09): adds
  a dedicated bullet to the same `## Output` section fixing `README.md` as
  the name of the change's overview file at the whole-section level (ADD
  `readmefile-01..03`), and updates the Entities/Operations table bullet
  (originally added by `specifier-entities-operations-table`) to no longer
  separately name `README.md` itself (MODIFY `entities-table-01`;
  `entities-table-02..05` unaffected). This change's scenarios and
  end-to-end QA are preserved for history in
  `spdd/archive/specifier-readme-fixed-name/`, not reproduced here.

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

`agents/prompts/specifier.prompt`'s `## Output` section also fixes the name
of the change's overview file at the whole-section level, not only via the
table bullet above:

- **Fixed overview file.** The change's overview — goal, contract, shared
  contracts, invariants, out-of-scope, and relevant-files pointers — is
  always written to the fixed file `README.md`, stated once in its own
  bullet (the same one-bullet, name-it-once style already used for
  `OPEN_QUESTIONS.md`). The Entities/Operations table bullet above no
  longer separately names `README.md`; it relies on this bullet instead, so
  the literal string `README.md` appears exactly once in the whole `##
  Output` section. No alternative or rejected file name (e.g. `OVERVIEW.md`,
  `SUMMARY.md`, `NOTES.md`) is named or discussed.

## Shared contracts
None across the two Features below — each covers a disjoint part of the
`## Output` section (the optional table's own column contract vs. the fixed
overview-file-name rule) with no shared data shape between them; each is
defined once, identically, within its own Feature.

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
  # MODIFIED by change `specifier-readme-fixed-name`: the bullet introducing
  # the table no longer names `README.md` itself -- it relies on the Output
  # section's own fixed-file bullet instead (see readmefile-01 below).
  Scenario: entities-table-01
    When the reader reads the "## Output" section of "agents/prompts/specifier.prompt"
    Then it states that when a change introduces a new data shape (entity, model, or interface) or multiple named operations (endpoints, CLI commands/flags, steps, events), the specifier may optionally add a structured table
    And the bullet introducing this table does not itself contain the literal string "README.md"

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

## Feature: specifier.prompt fixes README.md as the change's overview file for the whole Output section

  Background:
    Given "agents/prompts/specifier.prompt" carries a "## Output, written to
      `spdd/changes/<change-slug>/`" section
    And its first bullet reads: "Sub-specs covering goal, contract, tagged
      Gherkin scenarios, invariants, and out-of-scope." (unchanged by this
      addition)
    And its Entities/Operations table bullet currently reads, in full: "When
      a change introduces a new data shape (entity, model, or interface) or
      multiple named operations (endpoints, CLI commands/flags, steps,
      events), you may optionally include a structured table there: an
      entities table with columns Name, Path, New-or-Existing, Notes,
      and/or an operations table with columns Type, Identifier, Description,
      pruning columns per the Specification Rules' example-table rule. This
      table is a scannable complement to the prose contract sections — the
      tagged Gherkin scenarios remain the actual testable behavior spec,
      never replaced by the table."
    And its open-questions bullet already fixes a different file the same
      way this addition fixes the overview file: "Write open questions, if
      any, to the fixed file `spdd/changes/<change-slug>/OPEN_QUESTIONS.md`
      rather than inlining them elsewhere, and only create it when something
      is actually blocked."

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

### Invariants
- This addition touches only the "## Output" section of
  `agents/prompts/specifier.prompt`; the "## Process" section is untouched
  by it (see the independent, sibling `specifier-freshness-check` change,
  expected to extend this domain file separately).
- The existing first bullet of "## Output" is left byte-for-byte unchanged
  — the new bullet is inserted after it, not merged into it.
- `entities-table-02..05` are unaffected; only `entities-table-01`'s
  filename clause changed (see the Feature above).
- The literal string `README.md` appears exactly once in the whole `##
  Output` section — a single, direct statement of the fixed name, not
  repeated across or within bullets.
- No alternative or rejected file name (e.g. `OVERVIEW.md`, `SUMMARY.md`,
  `NOTES.md`) is named anywhere in `## Output`.

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

  ## The overview file is always README.md (live)

  # ADD - e2e-readmefile-01: two differently-shaped requests -- one with no
  # new data shape and a single operation, one introducing a new entity and
  # multiple named operations -- both produce their overview under the same
  # fixed name, never any other name.
  Scenario Outline: e2e-readmefile-01
    Given a request that <request-shape>
    When the user invokes the specifier
    Then "spdd/changes/<slug>/README.md" is created with the change's overview (goal, contract, invariants, out-of-scope)
    And no other overview file (e.g. "OVERVIEW.md", "SUMMARY.md", "NOTES.md") is created in "spdd/changes/<slug>/"

    Examples:
      | request-shape                                                                          |
      | only tweaks an existing single CLI flag's default value, introducing no new entity      |
      | introduces a new "Widget" entity and three named operations ("create", "list", "delete") |

  # ADD - e2e-readmefile-02: when a change does include the optional
  # Entities/Operations table, that table lives inside this same
  # README.md, alongside the rest of the overview -- never in a separate
  # file.
  Scenario: e2e-readmefile-02
    Given a request that introduces a new "Widget" entity and three named operations ("create", "list", "delete")
    When the user invokes the specifier
    Then the Entities/Operations table appears inside "spdd/changes/<slug>/README.md", not in any separate file
    And the numbered ".feature" files still contain the actual testable behavior for each operation (the table never substitutes for the Gherkin scenarios)

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
- Renaming the overview file away from `README.md`, or making its content
  optional/conditional — the fixed-overview-file-name rule only makes the
  existing, universal practice explicit; it does not change what the
  practice is.

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/agents/prompts/specifier.prompt` —
  the `## Output` section carrying this domain's instructions.
- `/home/edezacas/Projects/edezacas/antz/tests/entities-operations-table_test.sh` —
  self-contained bash test harness, one test per scenario above
  (entities-table-01..05), tagged with scenario ids in each test's reported
  name; the e2e-only ids (e2e-entities-01/02) appear there as explicit SKIP
  stubs, verified live by the verifier instead (see End-to-end QA suite
  above).
- `/home/edezacas/Projects/edezacas/antz/tests/readmefile_test.sh` —
  self-contained bash test harness, one test per scenario in the
  fixed-overview-file-name Feature above (readmefile-01..03), tagged with
  scenario ids in each test's reported name; the e2e-only ids
  (e2e-readmefile-01/02) are verified live by the verifier instead (see
  End-to-end QA suite above), not stubbed in this unit suite.
- `/home/edezacas/Projects/edezacas/antz/spdd/archive/specifier-readme-fixed-name/`
  — the change that delivered the fixed-overview-file-name Feature above
  (ADD `readmefile-01..03`, MODIFY `entities-table-01`), preserved for
  history.
