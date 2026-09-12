# Change: flow-script-guards

Implements **Cambio B** of `docs/plan-revision-2026-09.md` §3, including its
second-review notes: mechanical slug validation and a new-flow tree guard in
the flow script, the two new states wired into the orchestrator prompt, and
the existing tests that pinned the old behavior rewritten. Behavior level
moves to `4.5` via the mandated minor bump (VERSION `4.4.0` → `4.5.0`).
Cambios C, E, and D are explicitly out of scope.

## Goal

- **Mechanical slug validation** — `scripts/orchestration/antz-flow.sh`'s
  `ensure` rejects an invalid slug with exactly `state=bad_slug` (exit 1)
  before creating or positioning anything: lowercase letters/digits/hyphen
  only, no leading/trailing hyphen, no doubled hyphen, length at most 40.
  The rejection is non-destructive: no branch, no checkout, no file or ref
  change.
- **New-flow tree guard** — `ensure` rejects with exactly `state=tree_dirty`
  (exit 1) only when it is *starting a new flow*: the change dir
  `spdd/changes/<slug>/` is absent **and** the marker branch would be newly
  created, and `git status --porcelain` is non-empty. The guard is skipped on
  resume (change dir present), because the flow's implementation work
  legitimately lives outside `spdd/` in the working tree. Fail-closed by
  design: untracked, non-ignored files count; the user cleans, commits, or
  gitignores them and re-invokes.
- **Resume advisory** — any `state=reused` whose `git status --porcelain` is
  non-empty is followed by `dirty=yes` (a change-dir resume or a branch-only
  reuse). It is a machine line with no behavior change: routing is unchanged
  and the orchestrator only warns that the pre-existing dirt will ride into
  the human's commit. A clean reuse still prints exactly `state=reused`.
- **Orchestrator wiring (mandatory, second review)** — step 1's ensure-state
  instructions, the Session guards' latch stop list, and the Report Format's
  stopped enumeration document `state=tree_dirty` and `state=bad_slug` as
  hard `status=stopped` stops with their resume actions, plus the advisory
  `dirty=yes`. Without this the orchestrator could not route the new lines.
- **Tests** — `tests/antz-flow_test.sh`'s `ensure-02` and `ensure-05` are
  rewritten to the new contract, new cases are added (invalid slug,
  `tree_dirty` at new-flow start, resume-without-guard), and the `flow-09`
  scripts byte-unchanged guard is re-scoped off `antz-flow.sh` (the file this
  change modifies).
- **Bump** — `VERSION` to `4.5.0` and a matching `CHANGELOG.md` entry (minor:
  flow-script and orchestrator routing behavior changes; no workflow contract
  changes).

`install.sh` is **not edited**: the new script/prompt content reaches installed
copies through the normal `./install.sh --all` re-render (a re-run, not a
change).

## Contract

### Sub-specs (in dependency order)

| File | Feature word | Layer | Plan item |
|---|---|---|---|
| `01-ensure.feature` | `ensure` | `scripts/orchestration/antz-flow.sh` (`ensure`) + `tests/antz-flow_test.sh` | slug validation, tree guard, `dirty=yes`, test rewrite |
| `02-orchestrator.feature` | `orchestrator` | `agents/prompts/orchestrator.prompt` (step 1, latch, Report Format) | wire the new states |
| `03-bump450.feature` | `bump450` | `VERSION`, `CHANGELOG.md` | minor bump to 4.5.0 |
| `e2e-qa.feature` | `e2e-*` | end-to-end QA, one series per user-visible surface | — |

`01` is the API layer and lands first; `02` is the consumer prose and depends
on `01`'s output contract; `03` lands last and describes the whole change.
Each is independently implementable and verifiable — the coder handles exactly
one per session.

### Shared contracts

- **`ensure` output vocabulary, extended (identical in 01 and 02):** exactly
  one machine line per outcome except a resume-with-dirt, which prints two.
  | Type | Identifier | Description |
  |---|---|---|
  | state | `state=created` (0) | marker branch created at HEAD, session positioned |
  | state | `state=reused` (0) | existing marker branch, session positioned |
  | state | `state=tree_dirty` (1) | new-flow start refused: change dir absent, branch newly created, porcelain non-empty; nothing created or moved |
  | state | `state=bad_slug` (1) | mechanical slug rejection before any branch/positioning work; nothing changes |
  | state | `state=checkout_refused` (1) | resume positioning refused because it would overwrite uncommitted changes |
  | state | `state=no_branch` (1) | the branch could not be made to exist |
  | state | `state=no_commits` (1) / `state=no_git` / `state=no_repo` | unchanged preflight fail-closes |
  | advisory | `dirty=yes` | appended after any `state=reused` on a non-empty porcelain; no routing change, not a stop |
- **Slug rule (01 defines it, 02 references it):** `case $slug in
  ''|*[!a-z0-9-]*|-*|*-|*--*)` rejects plus a maximum length of 40
  characters. A 40-character slug is valid; 41 is not.
- **Stop classification (02):** both new stops are hard state stops reported
  `status=stopped` (not `waiting-user`); each names its resume action.
  `dirty=yes` is advisory only.
- **Decisions settled by the delegation (recorded, not guessed):**
  - The tree guard requires the conjunction: change dir absent **and** the
    marker branch newly created. A branch-only candidate (marker branch
    exists, change dir absent) is a reuse, not a new-flow start, so it is not
    guarded. This follows the delegation's "i.e. ... and the marker branch
    would be newly created" over the plan §2 parenthetical that names only the
    absent change dir.
  - The empty/absent slug is `state=bad_slug`, not the old
    `usage: ensure <slug>` arm; validation runs before `state=no_commits` and
    before any branch or positioning work.
  - `dirty=yes` is emitted after any `state=reused` with non-empty porcelain
    (the plan's wording), including a branch-only reuse.
  - Length bound fixed at 40 characters (the plan's suggestion, pinned so the
    boundary is testable).

### Edit-shape constraints from the existing suites (the coder must keep them green)

- `tests/antz-flow_test.sh` `orchestrator-01`, `orchestrator-05`, `flow-08`,
  and `flow-09`: the prompt's numbered steps still end at 6; exactly 14 fence
  lines across 7 blocks with exactly one ```sh fence (no new fenced block);
  the four tables survive; and every pinned step-1 ensure string survives
  (`state=created`/`state=reused` position, `state=checkout_refused`/
  `state=no_branch`/`state=no_commits` stop, "nothing is ever forced").
- `tests/antz-flow_test.sh` `ensure-01`, `ensure-03`, `ensure-04`,
  `ensure-06..14`: their fixtures are clean-tree and change-dir-absent (or the
  ensure call is discarded), so the tree guard never fires and no `dirty=yes`
  line appears; they must keep passing.
- `tests/antz-flow_test.sh` `flow-09`'s `git diff --quiet HEAD --
  scripts/orchestration/` guard must be re-scoped to the files this change
  leaves untouched (`antz-probe.sh`, `antz-skills.sh`), because
  `antz-flow.sh` is this change's subject; the probe's `change_dir=missing`
  assertion and every structural constraint stay enforced.
- `tests/renderinject_test.sh`'s base-render byte-identity gate is keyed only
  on the prompt's prose; a script-only sub-spec (01, before 02's prose edit)
  legitimately changes the rendered body, so the gate must also retire when an
  injected `scripts/orchestration/` file differs from the base tree. The
  marker-substitution reconstruction and structural render assertions stay
  enforced.
- `tests/orchestrator-sessionguards_test.sh` `sessionguards-02`,
  `sessionguards-04`: the latch gains the new stops (its list is "include at
  least", so additive), and the additive-vs-HEAD prose guard self-retires with
  a loud note while the prose is uncommitted (the established gate).
- `tests/access-model_test.sh` pins `state=checkout_refused` in
  `tests/antz-flow_test.sh`, `AGENTS.md`, `CLAUDE.md`, and `CHANGELOG.md`;
  the rewritten `ensure-05` keeps `state=checkout_refused` covered and the old
  entries stay in place.
- `tests/bump440_test.sh` is not broken by a `[4.5.0]` entry above `[4.4.0]`
  (VERSION still agrees with the newest topmost entry; the `[4.4.0]` section
  and the `[4.3.0]`-down tail are untouched). A new `bump450` suite mirrors
  `tests/bump440_test.sh`'s style.

## Invariants (change-wide)

- The flow script stays POSIX `sh` and free of destructive git: no
  `-B`/`--force`/`-f`, no `reset`/`clean`/`stash`/`restore`/branch-delete, and
  the one positioning stays a plain flagless `git switch "antz/$slug"`. No
  subcommand ever commits.
- Every rejection is non-destructive: `state=bad_slug` and `state=tree_dirty`
  leave HEAD, every ref, and the working tree byte-unchanged and create no
  stash.
- Success states imply positioned: `state=created`/`state=reused` are printed
  only once the session sits on `antz/<slug>`.
- The output vocabulary remains externally consistent: 01 emits exactly the
  lines 02 documents; `02` introduces no new script, no new flow subcommand,
  and no new probe field.
- `install.sh`, `agents/meta/*`, `scripts/orchestration/antz-probe.sh`, and
  `scripts/orchestration/antz-skills.sh` are byte-unchanged by this change;
  `scripts/orchestration/antz-flow.sh` is the one script edited.
- No tag is created by any role; `v4.5.0` is the human's commit-time
  follow-up.

## Out of scope

- **Cambio C** (precision gaps: index padding, code-present criterion, id
  search, plan threshold, domain naming, the `e2e-qa.feature` naming
  reconciliation, relevant-files placement, slug-collision handling, the
  probe regex tightening) — not touched.
- **Cambio D** (style rewrite) — not touched.
- **Cambio E** (`install.sh` hardening, AGENTS.md/CLAUDE.md "not present yet")
  — not touched.
- Docs updates in `AGENTS.md`, `CLAUDE.md`, and `docs/orchestrator.md`: not
  required by the versioning rule and not part of this change's scope.
- Any change to `discover`/`state`/`release`, the probe, or the receipt
  grammar.

## Governing spec situation (merge map for the verifier)

- `01-ensure.feature` → `spdd/specs/flow-branch.md`, Feature `ensure`:
  **MODIFY** `ensure-02` and `ensure-05`; **ADD** `ensure-15`..`ensure-20`.
  The spec's Invariants "one-line vocabulary" is extended (no id): the
  `ensure` vocabulary gains `state=bad_slug`, `state=tree_dirty`, and the
  advisory `dirty=yes` second line.
- `02-orchestrator.feature` → `spdd/specs/flow-branch.md`, Feature
  `orchestrator`: **MODIFY** `orchestrator-01`; **ADD** `orchestrator-06`.
  The latch stop list (`sessionguards-02`, in the same domain) and the Report
  Format's stopped enumeration (`flow-08`) are extended by the same change —
  their tests assert "include at least", so the existing ids stay valid; the
  verifier should note the extension on those two entries.
- `03-bump450.feature` → `spdd/specs/versioning.md` (the bump precedent is
  `bump440-*` merged there by change `fix-orchestrator-flow`).
- `e2e-qa.feature` → `spdd/specs/flow-branch.md`'s e2e section (precedent:
  `e2e-ensure-*`, `e2e-delegation-01`, `e2e-version-01`).

## Relevant files (pointers per sub-spec, not a walkthrough)

### 01-ensure.feature

- `scripts/orchestration/antz-flow.sh` — `ensure` only (lines ~41–78): the
  preflight stays at the top; the `[ -n "$slug" ]` usage arm becomes the
  mechanical validation → `state=bad_slug`; the no-commits and branch logic
  follow; the new-flow condition (change dir absent + `br_exists` false) gates
  the `git status --porcelain` tree check → `state=tree_dirty` *before*
  `git branch`; on the successful positioning, any `state=reused` with
  non-empty porcelain (resume or branch-only reuse) appends `dirty=yes` after
  the state line. Keep the header law and the flagless `git switch` intact.
- `tests/antz-flow_test.sh` — rewrite `test_ensure_02_uncommitted_work_survives`
  and `test_ensure_05_refused_switch_stops_clean`; add tests for the invalid
  slug outline, the 40-char boundary, untracked-non-ignored `tree_dirty`,
  resume-without-guard + `dirty=yes`, and the re-scoped `flow-09` guard (keep
  the `flow-09` reported name); update the file's header comment. Reuse the
  existing `new_repo`/`mk_change_dir`/`run_flow` helpers.
- `tests/renderinject_test.sh` — extend `if_base_identity_active` (and its
  helpers) so the pre-change render byte-identity gate also retires when any
  `scripts/orchestration/` file differs from the base tree; keep the
  reconstruction and structural assertions.
- `spdd/specs/flow-branch.md` — the governing `ensure` feature and its
  Invariants (read-only reference; the verifier merges).

### 02-orchestrator.feature

- `agents/prompts/orchestrator.prompt` — step 1's ensure-state bullet
  (line ~28), the Session guards' latch bullet (line ~123), and the Report
  Format's stopped definition (line ~129). Prose only: no fence, no step, no
  table row added. Keep every string pinned by `orchestrator-01`,
  `orchestrator-05`, `flow-08`, and `flow-09`.
- `tests/antz-flow_test.sh` — extend `test_orchestrator_01_state_meanings`
  (step-1 bullet) and, for the enumerations, the assertions there and/or in
  `tests/orchestrator-sessionguards_test.sh` (`test_sessionguards_02`); at
  least one test name carries `orchestrator-06`.
- `tests/orchestrator-sessionguards_test.sh` — `sessionguards-02`'s latch
  list and `sessionguards-04`'s structural assertions.

### 03-bump450.feature

- `VERSION` — reads exactly `4.5.0` (one trailing newline, its only content).
- `CHANGELOG.md` — new `## [4.5.0] - <date>` section above `[4.4.0]`,
  Keep a Changelog format, describing the change and the minor grade; every
  earlier entry byte-untouched.
- A new `tests/bump450_test.sh` mirroring `tests/bump440_test.sh` (the
  recorded lesson: VERSION is asserted to agree with the newest topmost entry,
  never pinned as a literal that the next bump breaks).

### e2e-qa.feature

- `e2e-qa.feature` — this file; the verifier exercises it during Integration
  Verification (the live-orchestrator half of `e2e-tree-01` judged by
  mechanism, per the established e2e convention). `install.sh` is not edited;
  `./install.sh --all` is the re-render the `e2e-version-01` scenario checks.

## End-to-end QA suite

`e2e-qa.feature`, three series: the mechanical slug rejection a user sees
through the flow script (`e2e-slug-01`), the new-flow tree guard and the
resume advisory plus the orchestrator's stop/report routing (`e2e-tree-01`),
and the 4.5.0 version surface through `install.sh` (`e2e-version-01`). The
coder ships the live-session halves as explicit SKIP stubs; the verifier
exercises them live.
