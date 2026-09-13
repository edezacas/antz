# Change: style-rewrite

Implements **Cambio D** of `docs/plan-revision-2026-09.md` §3 ("style rewrite
(patch; semántica intacta)"). A **style-only** change: the four role prompts'
rendered bodies change text only — no capability change. Semantics land at
`4.7.1` via the mandated patch bump (VERSION `4.7.0` → `4.7.1`, matching
`CHANGELOG.md` entry; the local tag `v4.7.1` is the human's commit-time
follow-up).

## Goal

- **Mirror clause once per prompt** — "mirror only / the receipt is the
  authority" is stated exactly once in each of the four prompts (today: the
  coder's skills-line tail, the coder's Receipt-section variant restatement,
  and the verifier's skills-line tail duplicate the closing-block statement;
  the specifier's and orchestrator's are already single).
- **Long sentences become short lists** — the four 100-130-word blocks: the
  coder's closing-block bullet, the orchestrator's `rejected_count=1` table
  row, the dedup guard, and the verifier's `REJECTED.md` entry sentence.
- **The orphan folds** — coder.prompt's two orphaned bullets (the blank-line
  separated receipt-naming bullet and the closing-block bullet) move into the
  `## Receipt` section they belong to.
- **The triple negation goes** — specifier.prompt's two table bullets become
  the plan's two-line rewrite.
- **Terminology unifies** — `<change-slug>` → `<slug>`; one form per concept
  for `sub-spec`, `slug`, `client`, `working root`.
- **The triplication rule is documented** — `## Working Root` is duplicated
  verbatim across the three role prompts on purpose (per-prompt autonomy);
  every future edit must touch all three sites. Documented in AGENTS.md and
  CLAUDE.md (identical additive bullet) and pinned by a test.
- **The test suites follow, loudly** — every suite pinning the rewritten
  prose is updated in the same change; every diff-window assertion is born
  gated on the `change_pending` pattern (bump440/450/460 as applied in
  864d2a8).

## Contract

Hard constraints (violations are blockers), from the delegation:

- The closing-block vocabularies are unchanged: `done|blocked`,
  `approved|rejected` (approved-with-warnings folds to `approved`),
  `spec_complete`, and `delegated-specifier|delegated-coder|delegated-verifier|
  stopped|released|waiting-user`.
- Every machine-line format is unchanged: `state=...`, `gate=...`,
  `class=...`, `receipt=...`, `id=... result=... reason=...`,
  `test_command=...`, plus the probe's `subspec=`/`covered=`/`complete=`/
  `rejected_count=`/`open_questions=`/`branch=`/`change_dir=` outputs and the
  delegation-header lines (`Working root: <repo root absolute path>`,
  `Change slug: <slug>`).
- The latch contract and the dedup contract are unchanged (the dedup bullet's
  *prose shape* changes; its law, exceptions, and bounds do not).
- Rendered bodies change text only — no capability change; `agents/meta/*`
  and `install.sh` are byte-unchanged across the whole change.

Sourcing note: the plan cites "the proposal in the external review" for the
two-line rewrite, but the review is not in the repository — only the plan
references it. The rewrite's outcome and shape are fully pinned by the plan
(two lines, no triple negation, semantics intact) and by the pinned semantics
of `tests/entities-operations-table_test.sh`, so sub-spec 01 pins the
canonical two-line text deterministically. Nothing is blocked; no
`OPEN_QUESTIONS.md` is left.

## Shared contracts

Identical across dependent sub-specs:

- **The mirror-clause strings** (pinned once per prompt at the closing-block
  statement): "The block is a mirror only", "no routing, count, or decision
  ever derives from it", "the receipt is the authority", "never an input to
  any routing state or count". Sub-specs 02 (fold), 04 (tail removals), and
  06 (no interaction, sweep-only) all treat these as the once-per-prompt
  invariant.
- **The slug placeholder** is `<slug>` everywhere prose names it (sub-spec
  06); the machine tokens `subspec=`/`<subspec-file>=` and the delegation
  header are exempt (byte-pinned elsewhere / machine formats).
- **The `change_pending` pattern** (sub-specs 06 and 07): a working-vs-HEAD
  window is enforced only while the guarded artifact differs from HEAD and
  HEAD lacks the change's marker content; it retires vacuously with a loud
  `note:` otherwise, never resurrecting against a later legitimate edit.
- **Known intermediate red** (documented in sub-specs 02 and 03): the
  skills-suite prompts-06 pins fail between sub-specs 02/03 and 04 — the
  flow's normal mid-change state; no suite is red at the change's end.

## Invariants

- Every pinned phrase that survives the rewrite is preserved verbatim (the
  per-sub-spec scenarios enumerate them); suites not listed for edits pass
  unmodified, verified per sub-spec.
- No new diff-window assertion is born ungated.
- No role commits; the work stays uncommitted on the flow's marker branch.

## Out of scope

- Any behavior change: vocabularies, machine lines, latch/dedup contracts,
  receipt grammar, delegation block, skills-activation mechanics.
- The latch's stop lists, the Report Format's stopped/waiting-user
  enumerations, the specifier's/orchestrator's closing bullets (already
  single), and the delegation-header line (byte-pinned).
- `agents/meta/*`, `install.sh`, `scripts/orchestration/*` — byte-unchanged.

## Sub-specs (dependency order)

### 01-specifier.feature — the two-line table rewrite
Destination domain: `specifier-role`.
Relevant files:
- `agents/prompts/specifier.prompt` — the "## Output" table bullets (lines
  41-42) are the rewrite target; the section heading changes only in
  sub-spec 06.
- `tests/entities-operations-table_test.sh` — re-scopes the legacy
  entities-table-01..05 pins to the new text; hosts the new specifier-01/02
  test functions.
- `tests/readmefile_test.sh`, `tests/conventions_test.sh` — verified no-break
  (extracts keyed on the `## Output` heading and untouched bullets).
Spec home: `spdd/specs/specifier-role.md` (entities-table-01..05 re-scope
merges there).

### 02-coder.feature — the orphan fold and the once-per-prompt clause
Destination domain: `receipts`.
Relevant files:
- `agents/prompts/coder.prompt` — the blank line + orphan bullets at 43-45
  fold into `## Receipt`; the closing-block bullet becomes a short list; the
  Receipt section's closing statement drops its variant restatement.
- `tests/closingblock_test.sh` — the coder extract anchor moves from
  "Output" to "Receipt" (closingblock-01/02/03/04's coder checks).
- `tests/receipts_test.sh` — verified no-break (its `## Receipt` pins and
  refusals are all still satisfied).
Spec home: `spdd/specs/receipts.md` (closingblock feature lives there).

### 03-verifier.feature — the REJECTED.md entry as a short list
Destination domain: `role-surfaces`.
Relevant files:
- `agents/prompts/verifier.prompt` — the `## On Rejection` opening sentence
  (line 34) becomes a lead line plus a short list; the attribution bullet is
  unchanged.
- `tests/roles_test.sh` — extended with the verifier-01/02 test functions
  (no existing pin touches this sentence — verified).
- `tests/orchestrator-status-probe_test.sh` — verified no-break (the probe
  counts `## Rejection <n>` headings at runtime; script untouched).
Spec home: `spdd/specs/role-surfaces.md`.

### 04-skillsline.feature — the skills lines stop restating the mirror principle
Destination domain: `skills-activation`.
Relevant files:
- `agents/prompts/coder.prompt` (## Output skills bullet) and
  `agents/prompts/verifier.prompt` (## Report Format skills bullet) — the
  duplicated tails come off; the mandatory-reporting rule stays.
- `tests/skills-activation-prompts_test.sh` — prompts-06 splits into
  per-role halves; the not-a-routing-input pins become whole-prompt
  once-per-prompt counts; the additive-only windows self-retire.
- `tests/skills-activation-docs_test.sh` — verified no-break (the docs
  gotcha keeps "a transparency line only, never a routing input").
Spec home: `spdd/specs/skills-activation.md` (prompts-06 re-scope merges
there).

### 05-orchprose.feature — the orchestrator's two lists
Destination domain: `flow-branch`.
Relevant files:
- `agents/prompts/orchestrator.prompt` — step 4's `rejected_count=1` row
  (line 90) becomes a short cell plus a relay bullet list under the table;
  the Session guards' dedup bullet (line 122) becomes a lead sentence plus a
  two-exception list; the latch bullet is byte-unchanged.
- `tests/orchestrator-sessionguards_test.sh` — extended with the
  orchprose-01/02/03 test functions.
- `tests/antz-flow_test.sh`, `tests/receipts_test.sh`,
  `tests/orchestrator-status-probe_test.sh` — verified no-break (flow-06's
  dedup phrases, the structural pins, and receipts-09's step-4 strings are
  preserved by construction; the sub-spec enumerates them).
Spec home: `spdd/specs/flow-branch.md` (sessionguards feature lives there).

### 06-terminology.feature — one form per concept; the triplication rule
Destination domain: `role-surfaces`.
Relevant files:
- `agents/prompts/specifier.prompt` (Output heading + OPEN_QUESTIONS bullet),
  `agents/prompts/coder.prompt` (Owns + Input Rule bullets),
  `agents/prompts/verifier.prompt` (Input Rule, Merge & Archive move, On
  Rejection path) — the seven `<change-slug>` sites become `<slug>`.
- `AGENTS.md`, `CLAUDE.md` — one identical additive gotcha bullet documenting
  the Working-Root triplication editing rule.
- `tests/roles_test.sh` — roles-01/roles-02/roles-03's line pins re-keyed to
  `<slug>`; hosts the terminology-02/03 sweep and triplication checks.
- `tests/rolechecks_test.sh` — rolechecks-03/04's byte-identity windows on
  the changed verifier bullets get born-gated `change_pending` predicates.
- `tests/closingblock_test.sh` — the specifier extract anchor re-keys on the
  new heading text.
- `tests/orchestrator-skills-block_test.sh` — verified no-break (pins
  `Change slug: <slug>` and `Working root: <repo root absolute path>`;
  byte-unchanged by design).
Spec home: `spdd/specs/role-surfaces.md`.

### 07-bump471.feature — the patch bump
Destination domain: `versioning`.
Relevant files:
- `VERSION` (4.7.0 → 4.7.1), `CHANGELOG.md` (the dated `[4.7.1]` entry).
- `tests/bump471_test.sh` — new, modeled on `tests/bump470_test.sh`
  (agreement-based version assertion, section-scoped entry greps,
  change_pending-gated guards).
- `tests/bump440_test.sh` … `bump470_test.sh`, `tests/skills-activation-bump_test.sh`,
  `tests/skills-desc-match-bump_test.sh` — verified no-break (agreement-based
  and stacking-safe; declared in the sub-spec).
Spec home: `spdd/specs/versioning.md`.

## End-to-end QA suite

`e2e-style-01..03` in `e2e-qa.feature` — the installed-agents surface (after
`./install.sh --all`: rewritten bodies, machine surfaces verbatim, mirror
clause once per body), the version surface (4.7.1 patch entry; `--check` up
to date), and the docs/source surface (the triplication rule stated and
true). All runnable by the verifier; no live agent sessions needed.
