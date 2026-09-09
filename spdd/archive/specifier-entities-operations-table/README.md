# Change: specifier-entities-operations-table

## Goal
This is a meta-change: it extends `agents/prompts/specifier.prompt` itself
with an optional Entities/Operations table, informed by a comparative
review against a sibling project (`open-spdd`'s `spdd-canvas` skill):

When a change introduces a new data shape or multiple named operations, the
specifier may optionally add a structured, scannable table to the change's
`README.md` — never mandatory, and never a replacement for the Gherkin
scenarios.

This is prompt-text instructions for the specifier to follow, not a new
file convention, script, or tooling. No other role's prompt, `install.sh`,
or `agents/meta/*.yaml` changes.

## Governing spec situation (for the verifier)
`spdd/specs/` today holds only `set-model.md` and `versioning.md` — both
product-feature/policy domains. **No governing spec covers the specifier's
own Process/Output instructions** (or any of the four role prompts' own
behavior). This change therefore defines a **new standalone spec domain**:
at merge, the verifier creates `spdd/specs/specifier-role.md` (or merges
into it, if a sibling change — `specifier-freshness-check` — has already
created it) and merges every scenario from
`01-entities-operations-table.feature` into it as **ADD** (nothing
pre-exists for this domain, so there are no MODIFY/REMOVE tags anywhere in
this change).

## Agreed design decisions (from the brief; not redesigned here)
1. **Entities/Operations table columns are fixed, per the brief:** Entities
   — Name, Path, New-or-Existing, Notes. Operations — Type, Identifier,
   Description. Column pruning (dropping a column where every row is
   identical and adds no acceptance value) follows the existing
   Specification Rules bullet on example tables — same pruning logic, no new
   rule needed.
2. **The table is optional per change, never forced.** Unlike open-spdd's
   canvas template (which mandates every section be filled or marked "not
   applicable"), antz does not adopt that rigidity — only the table format
   itself is adopted, as an available tool. A change with no new data shape
   and at most one named operation produces no table and is not penalized
   for omitting it.

## Sub-specs, in dependency order
1. `01-entities-operations-table.feature` — the Output-section addition
   (optional Entities/Operations table). This is the only sub-spec in this
   change.

## Shared contracts
None — a single sub-spec, no cross-sub-spec data shape to keep consistent.
The table's own column contract (see decision 1 above) is defined once,
identically, in `01-entities-operations-table.feature`.

## Invariants
- This addition is plain instruction/procedure text within
  `agents/prompts/specifier.prompt`'s existing bullet style (concise
  imperative bullets).
- No new file, script, or scripts-directory convention is introduced.
- No change to `agents/prompts/coder.prompt`, `agents/prompts/verifier.prompt`,
  or `agents/prompts/orchestrator.prompt`.
- No change to `install.sh` or any `agents/meta/*.yaml` (no access/frontmatter
  changes needed).
- Only the `## Output` section of `agents/prompts/specifier.prompt` is
  touched; the `## Process` section is untouched by this change (see the
  independent, sibling `specifier-freshness-check` change for that
  section).
- Column pruning (dropping a column where every row is identical and adds
  no acceptance value) reuses the existing `## Specification Rules`
  example-table pruning bullet — no new pruning rule is introduced for this
  table.
- The Entities/Operations table is additive and optional: it never replaces
  or narrows the requirement for tagged Gherkin scenarios as the actual
  testable behavior spec.

## Out of scope
- Any change to `coder.prompt`, `verifier.prompt`, or `orchestrator.prompt`.
- Any change to `install.sh` or `agents/meta/*.yaml`.
- A new script file or scripts directory for role prompts.
- Making the Entities/Operations table mandatory, or requiring every section
  to be filled/marked "not applicable" (explicitly rejecting the open-spdd
  canvas template's rigidity on this point).
- The mechanical freshness/drift check addition to the `## Process` section
  — that is the independent, sibling change `specifier-freshness-check`
  (no dependency in either direction; both edit disjoint sections of the
  same file).

## Versioning note (for the coder — not performed by this specifier change)
This change touches only `agents/prompts/specifier.prompt`. Per
`AGENTS.md`/`CLAUDE.md`'s `## Versioning` section, any commit changing
`agents/prompts/` requires a `VERSION` bump (this is a **behavior** change to
a role, not a wording-only tweak, so **minor**) and a matching
`CHANGELOG.md` entry in the same commit, plus a local `vX.Y.Z` git tag
against that commit. The specifier does not perform this bump — it is the
implementing coder's responsibility during the sub-spec's implementation
commit(s), per this repo's own versioning rule.

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/agents/prompts/specifier.prompt` —
  the file this sub-spec edits. Current `## Output` bullet 1 ("Sub-specs
  covering goal, contract, tagged Gherkin scenarios, invariants, and
  out-of-scope.") is extended by `01-entities-operations-table.feature`.
- `/home/edezacas/Projects/edezacas/antz/install.sh:104-106` —
  `claude_tools_for_access`/equivalent mapping showing `readonly` grants
  `Read, Grep, Glob, Bash` only (no `Edit`/`Write`) — confirmation that no
  tool-grant change is needed for this feature (the specifier already
  authors its `README.md` output via Bash).
- `/home/edezacas/Projects/edezacas/antz/tests/orchestrator-status-probe_test.sh` —
  precedent for how this repo unit-tests a prompt-embedded procedure (there,
  a fenced script extracted and executed; here, the coder's equivalent
  suite should instead assert the *presence and exact content* of the
  described table columns as literal text within `specifier.prompt`, since
  this feature has no executable script of its own — see the Verification
  levels below).

## Verification levels
- Unit-testable (coder's suite): `01-entities-operations-table.feature` in
  full — every scenario is a deterministic content assertion against the
  static text of `agents/prompts/specifier.prompt` (grep-style, same
  technique `set-model-command_test.sh` uses against rendered command
  bodies), not a live LLM invocation.
- End-to-end only (verifier, live specifier sessions): `e2e-qa.feature` in
  full — observing whether a live specifier session actually includes or
  omits the table appropriately can only be verified by invoking the
  specifier and inspecting the artifacts it produces, per Integration
  Verification.
