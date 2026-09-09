# Change: specifier-readme-fixed-name

## Goal
This is a meta-change: it extends `agents/prompts/specifier.prompt`'s `## Output`
section so the file name for a change's overview (goal, contract, shared
contracts, invariants, out-of-scope, relevant-files pointers) is fixed
explicitly, at the whole-`## Output`-section level, instead of only being
implied by the one existing bullet that happens to name it in passing (the
optional Entities/Operations table bullet added by the sibling change
`specifier-entities-operations-table`).

**Why now.** Two existing fixed-file conventions in this repo's role
prompts (`OPEN_QUESTIONS.md` in the specifier's `## Output`, `REJECTED.md`
in the verifier's rejection-reporting instructions) are each stated once,
plainly, in their own dedicated bullet. The change's
overview file has no such bullet: the string `` `README.md` `` appears exactly
once in the whole section today, inside the Entities/Operations table
bullet, as an incidental example rather than a rule. Nothing else pins the
name, so a future edit to that one bullet (or a differently-run specifier
session) could drift onto another name for the overview file, even though
every archived change under `spdd/archive/*/README.md` already uses this
name consistently in practice. This change makes that existing, universal
practice an explicit rule instead of an implied one — closing the drift risk
at its root (the whole `## Output` section) rather than re-deriving it only
for the table.

**Design note, from prior feedback.** State the fixed name once, in one new
bullet; every other bullet that produces overview content (contract,
invariants, out-of-scope, relevant files, shared contracts, and the
Entities/Operations table) refers back to that one file without repeating
its name. No alternative names (e.g. `OVERVIEW.md`, `SUMMARY.md`, `NOTES.md`)
are enumerated or discussed — the rule is stated directly, the same way
`OPEN_QUESTIONS.md` and `REJECTED.md` are: name it once, move on.

## Governing spec situation (for the verifier)
`spdd/specs/specifier-role.md` already exists (created merging the sibling
change `specifier-entities-operations-table`, per its own Origin section)
and already covers part of `agents/prompts/specifier.prompt`'s `## Output`
section (`entities-table-01..05`). This change extends the same domain
file, touching the same `## Output` section (not the disjoint `## Process`
section the independent sibling change `specifier-freshness-check` covers):

- **ADD** `readmefile-01`, `readmefile-02`, `readmefile-03` (new scenarios,
  new file `01-readmefile.feature`).
- **MODIFY** `entities-table-01` (originally added by
  `specifier-entities-operations-table`, now superseded by the version in
  `01-readmefile.feature`): the Entities/Operations table bullet no longer
  names `README.md` itself; it relies on this change's new fixed-file
  bullet instead. `entities-table-02..05` are untouched (they don't mention
  the file name).
- At merge, also update `spdd/specs/specifier-role.md`'s `## Origin` section
  to note this change as a third contributor to the domain, alongside the
  two already listed.

## Agreed design decisions (from the brief; not redesigned here)
1. **One new bullet, not a rewrite of the section header.** The `## Output,
   written to `spdd/changes/<change-slug>/`` header already names the
   directory; a new bullet (placed right after the existing first bullet)
   states the fixed file name for the overview content. The existing first
   bullet ("Sub-specs covering goal, contract, tagged Gherkin scenarios,
   invariants, and out-of-scope.") is left byte-for-byte unchanged, so the
   Background precondition already committed to
   `spdd/specs/specifier-role.md` (which quotes that bullet verbatim) stays
   valid without needing a merge-time text update.
2. **The Entities/Operations table bullet drops its own filename mention.**
   It keeps stating the same trigger condition and table shape
   (`entities-table-02..05` are unaffected), but no longer separately names
   `README.md` — that repetition is exactly the root-cause drift risk this
   change closes.
3. **No enumeration of rejected alternatives.** The new bullet states the
   fixed name directly, with no discussion of names not chosen — matching
   how `OPEN_QUESTIONS.md` and `REJECTED.md` are each introduced in this
   repo's prompts/docs.
4. **Scope: `## Output` section only.** No change to `## Process`, `##
   Specification Rules`, `## End-To-End QA Suite`, `## Ambiguity`, `##
   Verification`, or `## What you don't do`. No change to any other role
   prompt, `install.sh`, or `agents/meta/*.yaml`.

## Sub-specs, in dependency order
1. `01-readmefile.feature` — the `## Output` section addition (fixed
   overview-file name) and the accompanying `MODIFY` to the Entities/
   Operations table bullet. This is the only sub-spec in this change.

## Shared contracts
None — a single sub-spec, no cross-sub-spec data shape to keep consistent.

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
  touched; the `## Process` section is untouched (see the independent
  sibling `specifier-freshness-check` change for that section).
- The existing first bullet of `## Output` ("Sub-specs covering goal,
  contract, tagged Gherkin scenarios, invariants, and out-of-scope.") is
  left byte-for-byte unchanged.
- The literal string `README.md` appears exactly once in the whole `##
  Output` section after this change — a single, direct statement of the
  fixed name, not repeated across or within bullets.
- No alternative or rejected file name (e.g. `OVERVIEW.md`, `SUMMARY.md`,
  `NOTES.md`) is named anywhere in `## Output`.
- The Entities/Operations table bullet's substantive content (trigger
  condition, column sets, optionality) is unchanged — only its filename
  mention is removed.

## Out of scope
- Any change to `coder.prompt`, `verifier.prompt`, or `orchestrator.prompt`.
- Any change to `install.sh` or `agents/meta/*.yaml`.
- A new script file or scripts directory for role prompts.
- Renaming the overview file away from `README.md`, or making its content
  optional/conditional — this change only makes the existing, universal
  practice explicit, it does not change what the practice is.
- Any change to `entities-table-02..05` (column sets, complement statement,
  optionality, canvas-rigidity rejection) — only `entities-table-01`'s
  filename clause changes.
- The mechanical freshness/drift check addition to the `## Process` section
  — that is the independent, sibling change `specifier-freshness-check` (no
  dependency in either direction; both edit disjoint sections of the same
  file).

## Versioning note (for the coder — not performed by this specifier change)
This change touches only `agents/prompts/specifier.prompt`. Per
`CLAUDE.md`'s `## Versioning` section, any commit changing `agents/prompts/`
requires a `VERSION` bump (this is a **behavior** change to a role — it
fixes where required output content must be written, not a wording-only
tweak — so **minor**, matching the precedent set by the sibling
`specifier-entities-operations-table` change) and a matching
`CHANGELOG.md` entry in the same commit, plus a local `vX.Y.Z` git tag
against that commit. The specifier does not perform this bump — it is the
implementing coder's responsibility during the sub-spec's implementation
commit(s).

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/agents/prompts/specifier.prompt:34-43` —
  the `## Output` section this sub-spec edits. The new bullet is inserted
  after the current first bullet (line 35); the Entities/Operations table
  bullet (line 36) is the one that loses its `README.md` mention.
- `/home/edezacas/Projects/edezacas/antz/spdd/specs/specifier-role.md` —
  the governing domain spec the verifier merges into (ADD
  `readmefile-01..03`, MODIFY `entities-table-01`, update `## Origin`).
- `/home/edezacas/Projects/edezacas/antz/spdd/archive/specifier-entities-operations-table/`
  — the sibling change that introduced `entities-table-01..05` and the
  current, single `README.md` mention this change generalizes.
- `/home/edezacas/Projects/edezacas/antz/tests/entities-operations-table_test.sh:81-91`
  — `test_entities_table_01` currently asserts the literal substring
  `` "may optionally include a structured table in the change's \`README.md\`" ``
  against the Output section; this exact `require` call must change to
  match the new bullet text (no `README.md` in that specific bullet
  anymore) as part of implementing the `entities-table-01` MODIFY — see
  Verification levels below.
- `/home/edezacas/Projects/edezacas/antz/agents/prompts/specifier.prompt`
  bullet stating `` Write open questions, if any, to the fixed file
  `spdd/changes/<change-slug>/OPEN_QUESTIONS.md` `` — the existing,
  one-bullet, name-it-once style this change's new bullet follows for
  `README.md`.
- the independent sibling change `specifier-freshness-check` — disjoint
  `## Process` section of the same file; no dependency in either direction
  (noted only so the coder doesn't confuse the two when touching
  `specifier.prompt`).

## Verification levels
- Unit-testable (coder's suite): `01-readmefile.feature` in full — every
  scenario is a deterministic content assertion against the static text of
  `agents/prompts/specifier.prompt` (grep-style, same technique
  `entities-operations-table_test.sh` already uses), not a live LLM
  invocation.
- End-to-end only (verifier, live specifier sessions): `e2e-qa.feature` in
  full — observing whether a live specifier session actually names its
  overview file `README.md` (with or without the optional table) can only
  be verified by invoking the specifier and inspecting the artifacts it
  produces, per Integration Verification.
