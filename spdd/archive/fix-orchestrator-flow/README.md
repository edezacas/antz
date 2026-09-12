# Change: fix-orchestrator-flow

Implements **Cambio A** (items 1.1–1.7 only) of `docs/plan-revision-2026-09.md` §3,
the external-review fixes to the orchestrator's flow. Behavior level moves to
`4.4` via the mandated minor bump (VERSION `4.3.0` → `4.4.0`).

## Goal

Make the orchestrator's happy path actually flow, end to end, on disk state alone:

- **1.1 — the specifier delegation exists.** After `ensure`, a flow with no
  change dir is no longer a dead end: when neither `spdd/changes/<slug>/` nor
  `spdd/archive/<slug>/` exists (a `state=created` flow, or the branch-only
  `state=reused` candidate that never wrote anything), the orchestrator
  delegates the whole change to the `specifier` (which creates the change dir),
  then re-probes and continues. `delegated-specifier` gains its producing step.
  `change_dir=missing` when the dir *did* exist at `discover` time (an on-disk
  candidate) means mid-session deletion: stop and ask. After a verifier
  delegation, `change_dir=missing` never re-triggers this rule — step 5 routes it.
- **1.2 — the dedup guard enumerates exactly two exceptions**: step 4's relay of
  attributable blockers to the named sub-spec's `coder` session, and step 4's
  single whole-change `verifier` retry (bounded by `REJECTED.md`). Today the
  guard's "single carve-out" wording prohibits the verifier retry that step 4
  itself orders.
- **1.3 — step 5 detects the verifier's outcome from disk, not conversation**
  (the governing rule, applied): re-probe after the verifier delegation; change
  dir absent + `release` green = approved (approved-with-warnings included — its
  archive move is identical on disk); a new `REJECTED.md` entry → step 6;
  anything else (dir present, no new rejection) → fail-closed stop. The
  `release` gate disambiguates a post-verifier `change_dir=missing`: archive
  present = approved; `gate=refused reason=archive-missing` = anomalous → stop.
- **1.4 — the coder's directory ownership is restated by write surface, not
  read surface**: the coder reads `spdd/changes/` and `spdd/specs/` (read-only
  context, never written), writes the code and tests the sub-spec calls for
  wherever they belong in the project plus its receipt in
  `spdd/changes/<slug>/`, and never touches `spdd/archive/`. (The second-review
  correction: the earlier "writes only inside `spdd/changes/<slug>/`" phrasing
  would forbid implementing — the coder writes outside `spdd/` by definition.)
- **1.5 — `waiting-user` is defined, not removed**: the stop variant that hands
  a decision to the user (open questions, slug ambiguity, receipt doubt) versus
  `stopped` (the hard state stop). The latch applies identically to both —
  `waiting-user` changes only the closing `status=` value, never stop behavior.
  Latch wording and the vocabulary in tests/docs are reconciled.
- **1.6 — the verifier's archive step is a plain `mv` as the only instruction**,
  with the reason stated in the prompt: `git mv` on untracked files always
  fails, since nothing is ever committed.
- **1.7 — the literal sentinel `test_command=none`** when no suite is
  discoverable. The probe accepts it as a well-formed non-empty value
  (`complete` may be `yes`); the orchestrator never executes it — with `none`
  and a doubtful receipt it classifies from the receipt's `id=` lines or asks
  the user once.

Project rules encoded in this change: bump `VERSION` to `4.4.0` (minor — this
touches `agents/`) with the matching `CHANGELOG.md` entry, and update the
existing tests that pin the touched prose, in the same change. Everything stays
uncommitted on branch `antz/fix-orchestrator-flow`; committing is the human's
follow-up.

## Contract

### Sub-specs (in dependency order)

| File | Feature word | Layer | Plan items |
|---|---|---|---|
| `01-flow.feature` | `flow` | `agents/prompts/orchestrator.prompt` prose (steps 1–2 routing, session guards, step 5 detection, Report Format vocabulary) + one historical-record row in `docs/orchestrator.md` | 1.1, 1.2, 1.3, 1.5 |
| `02-receipts.feature` | `receipts` | `agents/prompts/coder.prompt` `## Receipt` grammar, the probe's acceptance contract, the orchestrator's doubtful-receipt exception | 1.7 |
| `03-roles.feature` | `roles` | `agents/prompts/coder.prompt` Input Rule ownership bullet, `agents/prompts/verifier.prompt` Merge & Archive, the AGENTS.md/CLAUDE.md strict-ownership gotcha bullet | 1.4, 1.6 |
| `04-bump440.feature` | `bump440` | `VERSION`, `CHANGELOG.md` | the mandated bump |
| `e2e-qa.feature` | `e2e-*` | end-to-end QA, one series per user-visible surface | — |

`01` is self-contained (prompt prose + one docs row). `02` and `03` are
independent of `01` and of each other (different prompt sections/files; both
reconcile their own pinned tests). `04` lands last: its CHANGELOG entry
describes the whole change. All five are independently implementable and
verifiable; the coder handles exactly one per session.

### Shared contracts (identical across sub-specs)

- **Probe output vocabulary unchanged.** `change_dir=missing` stays a probe
  output (the short-circuit line, exit 1); `open_questions=`,
  `rejected_count=`, and the `subspec=... receipt= covered= complete= class=`
  lines are untouched. Only the orchestrator's *routing* on
  `change_dir=missing` changes. No new probe field, no new flow subcommand
  (`discover`/`ensure`/`state`/`release` remain the four), and the
  `scripts/orchestration/` files are byte-unchanged by this change.
- **Release machine lines unchanged.** The four `release` lines
  (`gate=refused reason=branch-missing|archive-missing|change-still-present`,
  `released branch=antz/<slug>`) keep their exact forms; step 5's rewrite only
  changes *when* the orchestrator consults them and what it concludes.
- **Receipt grammar, one amendment.** Exactly one non-empty `test_command=`
  line whose value is the discovered unit-suite run command — or the literal
  sentinel `none` when nothing is genuinely discoverable; one
  `id=<feature>-<index> result=<green|skip|blocked> reason=<text>` line per
  declared id, unchanged in every other respect.
- **Stop vocabulary, now defined.** Every stop-and-report outcome ends the
  session's delegation (the latch); the closing block reads `status=stopped`
  for a hard state stop and `status=waiting-user` when the stop hands a
  decision to the user. The rest of the closing-block vocabulary
  (`delegated-specifier`, `delegated-coder`, `delegated-verifier`, `released`)
  is unchanged.
- **Delegation message shape unchanged.** The specifier delegation carries the
  same two `Working root` / `Change slug` lines and the same
  `## Skills to load before work` block as every delegation; no new fenced
  block appears in the prompt.
- **Edit-shape constraints from the existing suites** (the coder must keep
  them green while rewording): `tests/antz-flow_test.sh`
  `test_orchestrator_01_state_meanings` and
  `test_orchestrator_05_unchanged_surface` — the numbered steps still end at
  6, exactly 14 fence lines (7 blocks, exactly one ``` `sh` ```), the four
  tables survive, and step-1/step-5 pinned strings survive; the
  additive-vs-HEAD prose-diff guards self-retire with a loud note when the
  prose changes vs HEAD (established gate — rewording is permitted, the
  structural assertions stay enforced).

## Invariants (change-wide)

- The governing rule holds everywhere: every routing decision is derived from
  disk (probe output, receipts, `REJECTED.md` count, archive presence); no
  role's conversational report is trusted for state. Step 5's disk-based
  detection is this rule applied to the verifier's verdict.
- No role ever commits anything; the orchestrator never writes under `spdd/`;
  delegation never leaves the three roles; the dedup guard and the latch keep
  their standing (prompt-level law, binding regardless of the tool grant).
- Steps keep their numbering: the process still ends at step 6; the specifier
  delegation folds into steps 1–2; no step 7, no new fenced block.
- The latch's named stop outcomes all stay named, including
  `change_dir=missing` (now routed, still a stop in its stop-cases).
- `agents/meta/*`, `install.sh`, and `scripts/orchestration/*.sh` are
  byte-unchanged by this change; the render and install mechanics are
  untouched.
- The never-guessed-command law: an empty `test_command=` value stays
  malformed; the only sanctioned non-command value is the literal `none`.
- No tag is created by any role; `v4.4.0` is the human's commit-time follow-up.

## Out of scope

- Plan items 2.x, 3.x, 4, 5 — Cambios B–E: slug validation, the
  `state=tree_dirty` guard, precision gaps (index padding, id search, plan
  threshold, domain naming, the e2e-suite naming reconciliation), the style
  rewrite, install.sh hardening, and the AGENTS/CLAUDE "not present yet" line.
- `docs/orchestrator.md` rows other than the specifier-diff row (line 29) —
  e.g. its stale run-the-suite classification row stays as-is (historical
  record; separate concern).
- Any change to the probe's extraction regex or `subspec=` line (Cambio C).
- The verifier's rejection machinery, the e2e suite's role as the independent
  gate, the `BLOCKED:` convention, and `REJECTED.md`'s bounds — all unchanged.
- `install.sh`, `agents/meta/`, and the three orchestration scripts.

## Governing spec situation (merge map for the verifier)

- `01-flow.feature` → `spdd/specs/flow-branch.md`: all scenarios ADD; no
  existing id in that domain is modified (orchestrator-01..05,
  sessionguards-01..04 stay as merged; this change *amends* their subject
  matter with new, additive ids).
- `02-receipts.feature` → split at merge, per the split precedent recorded in
  `spdd/specs/receipts.md`'s Origin: `receipts-01` and `receipts-05` (MODIFY)
  merge into `spdd/specs/receipts.md` (the grammar they define lives there);
  `receipts-06` (MODIFY) and `receipts-11` (ADD) merge into
  `spdd/specs/flow-branch.md`, beside `receipts-06..09` (probe and step-3
  flow edges).
- `03-roles.feature` → new domain file at merge; suggested name
  `spdd/specs/role-surfaces.md`. Note for the merge:
  `spdd/specs/access-model.md`'s invariant "Coder ownership rules stay as-is:
  the coder only reads `spdd/changes/` and never touches `spdd/specs/` or
  `spdd/archive/`" is **superseded** by this change's roles-01/roles-04 (the
  coder now also reads `spdd/specs/` as read-only context and writes the
  implementation outside `spdd/`); the verifier should record the supersession
  there.
- `04-bump440.feature` → `spdd/specs/versioning.md` (the versioning-policy
  domain; precedent for a self-contained bump sub-spec landing elsewhere is
  `bump421-*` in `spdd/specs/skills-activation.md`).
- `e2e-qa.feature` → its scenarios merge into `spdd/specs/flow-branch.md`
  (e2e series precedent: `e2e-ensure-*`, `e2e-01..05`).

## Relevant files (pointers per sub-spec, not a walkthrough)

### 01-flow.feature

- `agents/prompts/orchestrator.prompt` — the change's core: step 1's
  ensure-state bullet and the new specifier-delegation routing (folds in
  before step 2), step 2's probe-table `change_dir=missing` row (row kept,
  meaning re-routed), the **Session guards** section (dedup bullet's
  carve-out enumeration; latch wording gains the waiting-user sentence),
  step 3's doubtful-receipt bullet is *not* touched here (see 02-receipts),
  step 5's preamble (disk-based detection; the release table and human
  follow-up print survive verbatim), step 6 (unchanged), Report Format's
  status vocabulary (stopped/waiting-user definitions).
- `docs/orchestrator.md` — line 29 only: the "What change/slug is this?" row
  of the derived-state table describes the old before/after-diff derivation;
  updated to the disk-routed specifier delegation (docs only — no bump
  required for docs).
- `tests/antz-flow_test.sh` — keeps `test_orchestrator_01_state_meanings` and
  `test_orchestrator_05_unchanged_surface` green (edit-shape constraints);
  gains the new `flow-*` tests (precedent: this suite guards orchestrator
  prose).
- `tests/orchestrator-sessionguards_test.sh` — `test_sessionguards_01` pins
  the "single carve-out" wording that 1.2 replaces (update to the
  two-exception wording); `test_sessionguards_02`'s `change_dir=missing` pin
  (line 271) must keep passing (the latch keeps the token);
  `test_sessionguards_04`'s removal check self-retires when prose changed vs
  HEAD, structural assertions stay enforced.

### 02-receipts.feature

- `agents/prompts/coder.prompt` — `## Receipt` section: the
  `test_command=` sentence ("record that honestly rather than leaving the
  line empty") gains the literal `none` sentinel; the planning-stage-refusal
  bullet's "honestly undiscoverable" wording follows.
- `scripts/orchestration/antz-probe.sh` — **byte-unchanged**: any non-empty
  `test_command=` value is already well-formed, so `none` is accepted with no
  code change; the scenario pins this so a future grammar tightening cannot
  silently reject the sentinel.
- `agents/prompts/orchestrator.prompt` — step 3's doubtful-receipt bullet
  only (declared boundary vs 01-flow's edits): the sentinel is never
  executed; classify from the `id=` lines or ask the user once.
- `tests/receipts_test.sh` — `test_receipts_01` pins
  `test_command=<discovered unit-suite run command>` and `test_receipts_05`
  pins "honestly undiscoverable" — both reworded to the sentinel;
  `test_receipts_08`'s step-3 pins checked against the amended bullet.
- `tests/orchestrator-status-probe_test.sh` — gains the sentinel fixture
  (`test_command=none` + exactly the declared id set, all green →
  `complete=yes class=done`).

### 03-roles.feature

- `agents/prompts/coder.prompt` — Input Rule's directory-ownership bullet
  (line 10, "Read only from `spdd/changes/`. Never touch ...") rewritten by
  write surface; `## Owns` first line already consistent, verified not broken.
- `agents/prompts/verifier.prompt` — Merge & Archive's move bullet (line 30):
  plain `mv` as the only instruction, reason stated; `git mv` no longer
  offered. No test pins `git mv` today (verified).
- `AGENTS.md`, `CLAUDE.md` — the "Strict directory ownership" gotcha bullet
  (line 16 in both) updated to the write-surface contract, byte-identical
  between the two files (shared-bullet convention); the access bullet's
  "coder implements sub-specs" phrasing already matches.
- `tests/skills-activation-prompts_test.sh` — `test_coder_additive_only` and
  `test_additive_only_verifier` compare every HEAD line verbatim; the 1.4/1.6
  rewordings legitimately remove lines, so these two guards are retired with
  a loud note (the renderinject-05 retirement-note precedent), re-scoped or
  gated the way `sessionguards-04`'s removal check is gated.

### 04-bump440.feature

- `VERSION` — reads exactly `4.4.0` (trailing newline, only content).
- `CHANGELOG.md` — new `## [4.4.0] - <date>` section above `[4.3.0]`, Keep a
  Changelog format, Added/Changed entries describing the items; every earlier
  entry byte-untouched (closingblock-06's pins survive: `[4.3.0]` still sits
  above `[4.2.1]`, and VERSION still agrees with the newest topmost entry).

### e2e-qa.feature

- `e2e-qa.feature` — this file; the verifier exercises it during Integration
  Verification (live-session halves judged by mechanism, per the repo's
  established e2e convention).

## End-to-end QA suite

`e2e-qa.feature`, three series: the user-visible fresh-flow delegation
(`e2e-delegation-01`), the disk-detected approval and its human follow-ups
(`e2e-approval-01`), and the version/docs surface a user sees through
install.sh (`e2e-version-01`). The coder ships the live-session halves as
explicit SKIP stubs; the verifier exercises them live.
