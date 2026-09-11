# Change: skills-desc-match

## Goal
Close the "Implementation caution (verifier, 2026-09-11)" recorded in
`spdd/specs/skills-activation.md`: the orchestrator's embedded
`antz-skills.sh` snippet matches keywords against the ENTIRE lowercased
YAML frontmatter block instead of the skill's `description:` field, so a
keyword appearing only in `name:`, `license:`, or `metadata:` lists a
skill (verified today on the real `~/.agents/skills/` tree: `apache` and
`edezacas` falsely list angular-conventions and init-project) and can
displace a genuinely matching skill under the cap of 5. The fix narrows
the match text to the `description:` field only, with correct multi-line
YAML block-scalar handling (`description: >` / `>-` — accumulate indented
continuation lines until the next top-level key or the end of the
frontmatter; a naive line-only extraction returns just ">" and would make
the real omarchy and diagnose-crash skills unmatchable). Patch-grade
implementation fix: the merged contract and the prompt prose are already
description-keyed — only the snippet's code (plus its runtime tests and
the 4.2.1 bookkeeping) moves onto them.

## Contract
- Matching is keyed to the `description:` field's content only:
  name-only, license-only, and metadata-only keywords become
  no-matches; description keywords match as before (case-insensitive,
  same `matched=` reasons).
- Block scalars are matched: `description: >` and `>-` accumulate their
  indented continuation lines into the match text until the next
  top-level key or the end of the frontmatter.
- Output contract unchanged: `skill=<name> path=<abs>/SKILL.md
  matched=<kw,...>` lines, explicit `Skills: none matched` (exit 0),
  cap of five, best-score-first with alphabetical-by-name tie-break.
- Scope of the edit: only lines inside the antz-skills.sh fenced snippet
  of `agents/prompts/orchestrator.prompt`; prose, coder/verifier/specifier
  prompts, `agents/meta/*`, `install.sh`, `AGENTS.md`, `CLAUDE.md` all
  byte-for-byte unchanged (verified truthful already).
- Tests evolve with the fix: `tests/orchestrator-skills-block_test.sh`
  gains the descmatch-01..03 coverage and scopes its vs-HEAD additive
  guard to permit removed lines only inside the snippet.
- Bump: `VERSION` -> 4.2.1, `CHANGELOG.md` gains `[4.2.1] - <date>` with
  a `### Fixed` entry, graded patch (code aligned to already-specced
  behavior; the user's decision), above `[4.2.0]`.

## Shared contracts
The snippet's output contract (line shapes, none-matched line, cap,
tie-break, statelessness, temp-file POSIX sh convention) is unchanged and
is defined once in `spdd/specs/skills-activation.md` (orchestrator-01..04,
prompts-02); this change re-aligns the implementation to it, never
rewrites it. `VERSION` and the topmost `CHANGELOG.md` section must agree
(the cross-change no-byte-pin lesson from `tests/docs-bump_test.sh`).

## Entities / operations
None new: no new data shape, no new endpoint, command, or flag. The only
named artifact is the pre-existing embedded `antz-skills.sh` snippet (its
usage and output lines are pinned by `spdd/specs/skills-activation.md` and
left identical).

## Invariants
- The orchestrator still never reads or follows a SKILL.md's instructions;
  skill bodies below the frontmatter fence are never matched.
- The derivation stays stateless: nothing written to disk, nothing under
  `spdd/`, no registry, no cache; re-derived fresh per delegation.
- `spdd/specs/skills-activation.md` text is not edited by this change
  (the contract was already correct; only implementation drifts onto it).
- No role ever commits anything; the `v4.2.1` tag is the human's
  commit-time follow-up.

## Out of scope
- Role prompt prose, docs (`AGENTS.md`/`CLAUDE.md` verified truthful and
  byte-identical to each other), `install.sh`, `agents/meta/*`.
- YAML coverage beyond plain single-line and folded (`>` / `>-`)
  descriptions (literal `|`, quoted multi-line, anchors).
- Any cap/tie-break/output-shape/directory change, or any delegation-block
  duty change (pinned by orchestrator-01..04).

## Sub-specs (dependency order)
1. `01-descmatch.feature` — the snippet fix and test evolution
   (descmatch-01..05).
2. `02-bump421.feature` — the 4.2.1 patch bump with its Fixed entry
   (bump421-01..02).
3. `03-e2e.feature` — end-to-end QA suite (e2e-01, e2e-02).

## Relevant files
- `agents/prompts/orchestrator.prompt` — the antz-skills.sh fenced
  snippet; the fix is inside lines ~170–226 (`desc_l=$(printf '%s\n'
  "$fm" | lc)` at line 197 is the defect; the `fm`/`nm` extraction
  immediately above is the insertion point for description-only
  extraction with continuation-line accumulation).
- `tests/orchestrator-skills-block_test.sh` — runtime tests for the
  snippet; `test_orchestrator_01_block`'s additive-vs-HEAD guard needs
  snippet-scoping; new tests for descmatch-01..03; fixtures via
  `add_skill`.
- `VERSION`, `CHANGELOG.md` — the 4.2.1 bump (bump421-01..02).
- `spdd/specs/skills-activation.md` — read-only reference: the merged
  contract (prompts-02, orchestrator-01..04) and the Implementation
  caution this change closes.
- `spdd/specs/versioning.md` — read-only reference: bump policy and
  grading scale.
- `spdd/archive/skills-activation/` — the delivering change, history
  only.

## End-to-end QA suite
`03-e2e.feature`: e2e-01 (orchestrated `/antz` delegation blocks on the
real skills tree — Angular work lists angular-conventions; hyprland/
keybinding work lists omarchy via its `description: >` continuation
lines; nothing else matches; `apache`/`edezacas` print exactly
`Skills: none matched`, exit 0 — the pre-fix false positives are gone),
e2e-02 (`./install.sh --check` reports 4.2.0 -> 4.2.1 drift and prints
the `[4.2.1]` entry writing nothing; `--all` stamps
`antz:generated version=4.2.1`; rendered bodies byte-identical except the
snippet lines and marker version).

## OPEN_QUESTIONS.md
Not created: no genuine ambiguity. The patch-grade 4.2.1 call was made by
the user; docs/prose were verified truthful against the real code and
tree; the block-scalar evidence was verified against the live skills
tree and the pre-fix false positives were reproduced before speccing.
