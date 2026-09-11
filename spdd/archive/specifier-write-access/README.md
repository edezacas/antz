# Change: specifier-write-access

## Goal

Fix the self-contradictory access model discovered live during
flow-branch-checkout dogfooding: `agents/meta/specifier.yaml` and
`agents/meta/verifier.yaml` declared `access: readonly` (rendering to NO edit
capability on both clients), while both roles' own prompts require writing
their core artifacts — the specifier authors `spdd/changes/<slug>/`
(README.md, numbered `.feature` files, `OPEN_QUESTIONS.md`), the verifier
merges into `spdd/specs/`, owns `spdd/archive/` moves, and appends
`REJECTED.md`. Installed specifier sessions silently completed with zero
files written. Only the coder was renderable as readwrite.

**Decision (settled, not an open question):** both corrected roles get
`access: readwrite`. A path-restricted new access level was considered and
dropped: neither target client's permission layer can scope edits to paths
(no "may write only spdd/"), so a new level would map to nothing mechanically
enforceable — it would be an illusion of least privilege. The honest minimal
fix is readwrite for both, with the real boundary kept where it actually
lives: prompt-level path ownership per role plus the never-commits law.

## Contract

- `agents/meta/specifier.yaml` and `agents/meta/verifier.yaml` declare
  `access: readwrite`; `coder.yaml` and `orchestrator.yaml` untouched.
- `install.sh` is **not edited at all**: its mapping functions already render
  readwrite correctly, and the readonly mapping branches are retained (the
  mapping stays a defined contract even though, post-change, no meta file
  declares readonly).
- Rendered outputs: Claude `tools: Read, Grep, Glob, Bash, Edit, Write`;
  OpenCode `mode: subagent`, `edit: allow`, `task: deny` — for specifier and
  verifier. Coder/orchestrator renders byte-identical to pre-change.
- Docs corrected: AGENTS.md and CLAUDE.md's access-model gotcha bullet (and
  `docs/orchestrator.md`'s delegation-scoping paragraph) now state that
  specifier/coder/verifier are readwrite with prompt-owned artifact surfaces,
  orchestrator stays orchestrateonly, and the boundary is prompt-level path
  ownership + never-commits, not tool absence.
- Versioning: this change touches `agents/meta/` → tracked-path bump, graded
  **minor** (rendered-agent behavior change; taxonomy, mapping, marker
  format, layout, install locations all unchanged) → `VERSION` 4.1.0,
  matching `CHANGELOG.md` `[4.1.0] - 2026-09-11` entry.

## Shared contracts

The access values declared in `agents/meta/*.yaml` are the single input to
install.sh's mapping functions; sub-specs `01-meta` and `02-render` consume
the same field identically. The corrected access-model statement is stated
identically in AGENTS.md and CLAUDE.md (docs-02 pins the sync).

## Sub-specs (dependency order)

| File | Feature | Scenarios |
|---|---|---|
| `01-meta.feature` | meta | meta-01, meta-02, meta-03 |
| `02-render.feature` | render | render-01, render-02, render-03, render-04 |
| `03-docs.feature` | docs | docs-01, docs-02, docs-03, docs-04 |
| `04-bump.feature` | bump | bump-01, bump-02, bump-03 |

Each feature file carries its own end-to-end QA suite in the same file:
e2e-meta-01/02 (01-meta), e2e-render-01/02 (02-render), e2e-docs-01 (03-docs),
e2e-bump-01 (04-bump) — e2e-only ids, SKIP stubs at unit level, verified live
by the verifier.

All scenarios are ADD against `spdd/specs/` — no existing spec domain covers
meta access values, rendered access grants, or the access-model doc wording.
`02-render` depends on `01-meta`; `03-docs` and `04-bump` are independent.

## Invariants

- No prompt body changes (`agents/prompts/*` byte-for-byte unchanged); no new
  access level; marker format unchanged (`antz:generated version=X`).
- `install.sh` byte-for-byte unchanged; readonly mapping semantics retained
  in code and docs as a defined level.
- Safety boundary intact in wording: prompt-level path ownership (coder never
  touches `spdd/specs/`/`spdd/archive/`), never-commits law, Governing-rule
  narrative untouched.
- Installed-copy lifecycle: after this change ships, reinstalling overwrites
  the human's hand-patched temporary `edit: allow` with the real render —
  expected and intended; the marker format is unchanged so `--check` and
  `/antz-set-model` keep working.
- Shared-file layering: `VERSION`, `CHANGELOG.md`, `AGENTS.md`, `CLAUDE.md`
  already carry uncommitted flow-branch-checkout edits in this working tree;
  this change's edits are strictly additive on top (bump-03), never reverting
  them. No commits by anyone; the `v4.1.0` tag is the human's commit-time
  follow-up.
- Verifier merge note: `spdd/specs/specifier-role.md`'s e2e Background line
  ("the specifier's own tool grant is Read, Grep, Glob, Bash — readonly
  access, no Write/Edit tool — it authors files under spdd/changes/ via
  Bash") becomes stale drift from this change; the verifier should touch up
  that line during its merge (coder does not edit `spdd/specs/`).

## Out of scope

- `agents/prompts/*` bodies (path-ownership rules there are already correct).
- Any edit to `install.sh` (including no new access level and no mapping
  change); the flow script (`antz-flow.sh`); the `worktree` branch and its
  historical docs (`docs/worktree-isolation-plan*.md`).
- Other changes' pending work (flow-branch-checkout's hunks beyond additive
  layering; its `tests/docs-bump_test.sh`, `spdd/specs/flow-branch.md`,
  `spdd/archive/flow-branch-checkout/`).
- Path-scoped permission machinery of any kind; mechanical bump enforcement.

## Relevant files

- `agents/meta/specifier.yaml`, `agents/meta/verifier.yaml` — the two
  corrected files (line 3: `access: readonly` → `readwrite`).
- `agents/meta/coder.yaml`, `agents/meta/orchestrator.yaml` — untouched
  regression guards.
- `install.sh:102-159` — `claude_tools_for_access`,
  `opencode_edit_perm_for_access`, `opencode_mode_for_access`,
  `opencode_task_perm_for_access`, `render_claude`, `render_opencode` (read
  only; unchanged).
- `AGENTS.md:19`, `CLAUDE.md:19` — the access-model gotcha bullet to correct;
  `AGENTS.md:33`, `CLAUDE.md:32` — Client Integration mapping bullets (keep
  mapping-accurate, note no role declares readonly post-change).
- `docs/orchestrator.md:87-101` — delegation-scoping paragraph, stale
  parenthetical.
- `CHANGELOG.md`, `VERSION` — bump artifacts (layer over pending 4.0.0).
- `tests/installsh-posixsh_test.sh` — harness pattern for render tests
  (isolated temp dirs); `tests/versioning-rule_test.sh` — pattern for
  doc-content assertions. New suite: `tests/access-model_test.sh`, one test
  per scenario id (meta-01..03, render-01..04, docs-01..04, bump-01..03),
  SKIP stubs for all `e2e-*` ids.
- `spdd/specs/versioning.md` — governing bump policy; `spdd/specs/specifier-role.md`
  — the stale e2e Background line for the verifier's merge.
