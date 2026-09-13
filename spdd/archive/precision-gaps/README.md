# Change: precision-gaps

Implements **Cambio C** of `docs/plan-revision-2026-09.md` §3, including the
second-review notes: the precision gaps in the role prompts and the probe
script are closed with mechanical, fixed rules. **Cambio D and Cambio E are
explicitly out of scope.** Behavior level moves to `4.6` via the mandated
minor bump (VERSION `4.5.0` → `4.6.0`, matching `CHANGELOG.md` entry, local
tag `v4.6.0` as the human's commit-time follow-up).

## Goal

- **`<index>` defined** — a scenario id's `<index>` is two zero-padded
  digits, sequential from 01 within the sub-spec (`specifier.prompt`
  Specification Rules).
- **"code present" mechanical** — the verifier's gate becomes: the sub-spec's
  scenario ids appear in the project's test files (literal grep of the id)
  **or** its receipt exists.
- **Id search defined** — wherever a role searches for scenario ids in the
  working tree, the search is a literal grep of the id in the project's test
  files.
- **Plan threshold fixed** — N = 8 (second review: not left open): more than
  8 implementation steps, or more than 1 shared contract needing change,
  marks the change for splitting.
- **Domain rule** — one file per domain `spdd/specs/<domain>.md`
  (kebab-case); the specifier declares each sub-spec's destination domain in
  `README.md`; the verifier creates the file when the domain is new.
- **e2e QA suite** — fixed name `e2e-qa.feature`, **one per change dir** (the
  archived practice), not "one per feature" — reconciling
  `specifier.prompt`'s wording (with multi-layer sub-specs, one file per
  feature cannot fit a single fixed name).
- **Relevant files** — in `README.md`, one section per sub-spec.
- **Slug** — the derivation states the flow script's mechanical length limit
  (at most 40); a collision without semantic continuation asks the user
  rather than suffixing `-2` (the ask-on-unclear half is already prompt law —
  pinned here).
- **Probe regex aligned** — the id extraction admits no hyphen in the
  `<feature>` portion, so a violating tag surfaces as an id mismatch instead
  of being tolerated; `tests/orchestrator-status-probe_test.sh` and
  `spdd/specs/receipts.md` are updated in this same change (second review).

## Contract (per sub-spec)

Each sub-spec below is independently implementable and verifiable; they are
ordered by dependency (the specifier's conventions define the id shape the
other sub-specs consume).

- **01-conventions** — `agents/prompts/specifier.prompt`'s three bullets
  (index format, e2e count and fixed file name, README per-sub-spec sections
  with relevant files + destination domain) plus the loud by-gating
  retirement of the specifier diff-window pins the rewordings trip.
- **02-rolechecks** — `agents/prompts/coder.prompt` (literal-grep id search
  in the pre-planning check; fixed plan threshold N=8) and
  `agents/prompts/verifier.prompt` (mechanical "code present"; per-domain
  spec-file rule with create-when-new), plus the re-scoped roles-03 pin.
- **03-probealign** — `scripts/orchestration/antz-probe.sh`'s id-extraction
  regex aligned with the specifier convention, and
  `tests/orchestrator-status-probe_test.sh`'s tolerant-behavior fixtures
  rewritten; the `spdd/specs/receipts.md` update is this sub-spec's merge.
- **04-sluglimit** — `agents/prompts/orchestrator.prompt`'s slug-derivation
  bullet states the ≤40-character mechanical limit; the collision rules
  (suffix only on continuation, ask on unclear) are pinned.
- **05-bump460** — `VERSION` at `4.6.0`, the matching `CHANGELOG.md` entry,
  graded minor with the versioning-table justification, and the new
  `tests/bump460_test.sh`.

## Shared contracts

Defined once, used identically across sub-specs:

- **Scenario-id shape**: `<feature>-<index>` with `<feature>` one word
  (letters, digits, underscores — no hyphens or spaces) and `<index>` two
  zero-padded digits, sequential from 01. Authored by the specifier
  (conventions-01), tagged on tests and receipts by the coder, grepped by the
  verifier (rolechecks-01/03), and matched by the probe's extraction
  (probealign-01).
- **Id search**: a literal grep of the id in the project's test files (the
  files carrying the unit-test suite) — the coder's pre-planning done-check
  and the verifier's code-present criterion use the same mechanism.
- **Destination domain**: declared per sub-spec in the change README's
  section for that sub-spec (kebab-case); the verifier resolves it to
  `spdd/specs/<domain>.md`, creating the file when the domain is new.
- **e2e QA suite**: exactly one per change dir, fixed file name
  `e2e-qa.feature` (this change's own suite is the working instance).
- **Slug rule**: lowercase letters/digits/hyphen, no leading/trailing or
  doubled hyphen, at most 40 characters (the flow script's `state=bad_slug`
  rule); suffixing only on semantic continuation, ask on unclear.

## Invariants

- No role ever commits anything: the work stays uncommitted on
  `antz/precision-gaps` in the working tree; committing (and the `v4.6.0`
  tag) is the human's follow-up. No spec carries commit steps.
- No commit produced later by the human touches `agents/` and/or
  `install.sh` without carrying the `VERSION` bump (`4.5.0` → `4.6.0`) and a
  matching `CHANGELOG.md` entry (Keep a Changelog format), per the versioning
  rule.
- The probe runs no tests and no git; its other outputs
  (`open_questions=`, `rejected_count=`, `change_dir=missing`,
  `receipt=/covered=/complete=/class=`) are byte-unchanged.
- The receipt grammar, the classification mapping, and the doubtful-receipt
  exception are unchanged.
- `install.sh` and `agents/meta/*` are byte-unchanged by this change.
- Cambio D (style rewrite) and Cambio E (install.sh/docs hardening) are not
  implemented by this change.

## Sub-specs, destination domains, and relevant files

### 01-conventions.feature

- **Declared destination domain**: `specifier-role`
  (`spdd/specs/specifier-role.md`)
- Relevant files:
  - `agents/prompts/specifier.prompt` — the three reworded bullets: the
    `## Specification Rules` scenario-naming bullet (conventions-01), the
    `## End-To-End QA Suite` first bullet (conventions-02), the
    relevant-files bullet in `## Output` (conventions-03).
  - `tests/skills-activation-prompts_test.sh` — prompts-05's specifier
    guard, gated-retired loudly (conventions-04).
  - `tests/closingblock_test.sh` — closingblock-05's two specifier
    diff-window assertions, gated-retired loudly (conventions-04).
  - `tests/readmefile_test.sh`, `tests/entities-operations-table_test.sh` —
    surrounding `## Output` pins that must stay green unmodified
    (read-only reference).

### 02-rolechecks.feature

- **Declared destination domain**: `role-surfaces`
  (`spdd/specs/role-surfaces.md`)
- Relevant files:
  - `agents/prompts/coder.prompt` — `## Process`: the pre-planning id-check
    bullet (rolechecks-01) and the "Plan briefly" bullet (rolechecks-02).
  - `agents/prompts/verifier.prompt` — the Input Rule's code-present bullet
    (rolechecks-03) and the Merge & Archive merge bullet (rolechecks-04).
  - `tests/roles_test.sh` — roles-03's exact-string pin of the merge bullet,
    re-scoped to the extended bullet (rolechecks-05).
  - `spdd/specs/receipts.md` — read-only reference (receipt existence is the
    "code present" criterion's second disjunct).

### 03-probealign.feature

- **Declared destination domain**: `receipts` (`spdd/specs/receipts.md`)
- Relevant files:
  - `scripts/orchestration/antz-probe.sh` — the id-extraction grep at the
    per-file loop (probealign-01/02).
  - `tests/orchestrator-status-probe_test.sh` — the tolerant-behavior pins
    rewritten (`test_probe_subspec_ids_hyphenated_feature`, and the
    hyphenated fixture ids `command-install-01` / `picker-cmd-01` in the
    multi-line-tag and tag-crossref tests); aligned-extraction assertions
    tagged `probealign-*` added to the same suite (probealign-03).
  - `spdd/specs/flow-branch.md` — read-only reference (receipts-06 pins the
    probe's other outputs as unchanged).

### 04-sluglimit.feature

- **Declared destination domain**: `flow-branch` (`spdd/specs/flow-branch.md`)
- Relevant files:
  - `agents/prompts/orchestrator.prompt` — step 1's slug-derivation bullet
    (sluglimit-01/02).
  - `scripts/orchestration/antz-flow.sh` — read-only reference: the
    mechanical `state=bad_slug` rule (≤40) the bullet now states;
    byte-unchanged.
  - `tests/antz-flow_test.sh`, `tests/orchestrator-sessionguards_test.sh` —
    surrounding pins that must stay green (read-only reference).

### 05-bump460.feature

- **Declared destination domain**: `versioning` (`spdd/specs/versioning.md`)
- Relevant files:
  - `VERSION`, `CHANGELOG.md` — the 4.6.0 bump (bump460-01/02).
  - `tests/bump460_test.sh` — new self-contained suite, one test per
    bump460 id, mirroring `tests/bump440_test.sh`/`tests/bump450_test.sh`.
  - `spdd/specs/versioning.md` — read-only reference (the governing
    gradation).

## Out of scope

- **Cambio D** (style rewrite: mirror-clause dedup, long-sentence
  restructuring, terminology unification) — explicitly not this change.
- **Cambio E** (install.sh hardening: header-anchored marker, YAML quoting,
  ref pinning, mktemp trap, `.bak` policy, AGENTS.md/CLAUDE.md "not present
  yet" fixes) — explicitly not this change.
- Any change to the receipt grammar, the access model, `install.sh`, or
  `agents/meta/*`.
- Enforcing the two-digit index in the probe (the probe's extraction stays
  index-format-agnostic; padding is the specifier's authoring rule).
