# Change: flow-branch-checkout

## Goal

The orchestrator's embedded `antz-flow.sh` (`agents/prompts/orchestrator.prompt`)
currently creates the marker branch `antz/<slug>` at the flow's base commit but
never checks it out — the "no checkouts" law. The session therefore stays on
whatever branch it was on, and the flow's (always uncommitted) work has no
branch identity of its own. This change makes `ensure` create the branch AND
switch to it:

- **Fresh path**: branch created at the current HEAD **and** the session
  positioned on it, so all roles' uncommitted work lands on the flow branch.
- **Resume path** (`state=reused`): the session is re-positioned onto the
  existing branch (whose ref is never rewritten).
- **Refused positioning**: if git refuses the switch (a destructive-checkout
  conflict — uncommitted changes it would overwrite), the script stops with a
  machine-readable state and exits nonzero rather than forcing anything. No
  `--force`, no `-B`, no resets, no deletes — ever.
- **Never-commits law fully intact**: no role ever commits; commits are
  exclusively the human's follow-up.
- **Human follow-ups updated**: after an approved Merge & Archive the user is
  already on `antz/<slug>`, sees the pending files in `git status`, reviews and
  commits whenever/how they want, then themselves decides whether and where to
  merge (e.g. `git switch <integration> && git merge antz/<slug>`) and may
  delete the branch. The orchestrator never runs those commands and never
  hardcodes an integration branch name.
- **Otherwise unchanged**: the release gate, `discover`, and `state` keep
  their exact contracts. `tests/antz-flow_test.sh`'s no-checkout assertion is
  inverted into a checkout/positioning assertion while the never-commits and
  no-destruction guarantees stay tested. AGENTS.md/CLAUDE.md gotcha wording and
  docs reflect the new contract, with the mandatory VERSION bump 3.0.0 → 4.0.0
  and a matching CHANGELOG.md entry (breaking workflow-contract change per the
  versioning policy — `agents/prompts/orchestrator.prompt` changed).

## Contract

### Sub-specs (in dependency order)

| File | Feature word | Layer |
|---|---|---|
| `01-ensure.feature` | `ensure` | the embedded `antz-flow.sh` script: `ensure`'s create-and-checkout contract, the refused stop, and every other subcommand/guarantee pinned unchanged |
| `02-orchestrator.feature` | `orchestrator` | `orchestrator.prompt`'s prose consuming the script: step-1 state meanings, step-5 human follow-up print, law wording |
| `03-docs.feature` | `docs` | AGENTS.md/CLAUDE.md gotcha bullets, VERSION 4.0.0, CHANGELOG entry |
| `e2e-qa.feature` | `e2e-*` | end-to-end QA, one series per layer |

`01` is self-contained (script-level, verifiable alone). `02` depends only on
`01`'s machine lines (shared contract below). `03` depends on the change
existing at all; it is independently implementable (docs + bump edits).

### Shared contracts (identical across sub-specs)

The machine-line vocabulary — stdout is exactly one line per invocation for
`ensure`/`state`/`release` (discover: one `candidate=` line per match,
possibly none), with these exact forms:

| Line | Exit | Meaning |
|---|---|---|
| `state=created` | 0 | `ensure`: branch did not exist; created at the pre-call HEAD **and** the session is now on `antz/<slug>` |
| `state=reused` | 0 | `ensure`: branch already existed; the session is now positioned on it; the branch ref is untouched |
| `state=no_commits` | 1 | `ensure`: unborn HEAD; nothing created, nothing positioned (unchanged) |
| `state=checkout_refused` | 1 | `ensure`: git refused the positioning (destructive-checkout conflict — uncommitted changes would be overwritten); nothing was forced or altered |
| `state=no_branch` | 1 | `ensure`: the branch could not be made to exist (creation attempt failed and it is still absent); never a success state |
| `state=no_git` / `state=no_repo` | 1 | preflight fail-close, every subcommand (unchanged) |
| `branch=missing` | 1 | `state` subcommand: marker branch absent (unchanged) |
| `gate=refused reason=branch-missing\|archive-missing\|change-still-present` | 1 | `release` gates (unchanged) |
| `released branch=antz/<slug>` | 0 | `release` success; removes nothing; prints no commands to run (unchanged) |
| `candidate=branch slug=…` / `candidate=on-disk slug=…` | — | `discover` (unchanged) |

Naming conventions shared across sub-specs: the branch is always `antz/<slug>`;
the merge target in the human follow-ups is always a placeholder
(`<integration>`), never a hardcoded branch name; the behavior-level marker in
the gotcha bullets moves `3.0` → `4.0`; the version moves `3.0.0` → `4.0.0`.

### Operations (scan table — the tagged scenarios remain the real spec)

| Type | Identifier | Description |
|---|---|---|
| subcommand | `ensure <slug>` | **Changed**: creates the branch AND positions the session on it (fresh → `created`, resume → `reused`); new stop states `state=checkout_refused` and `state=no_branch`; `no_commits` and the preflight unchanged |
| subcommand | `discover` | Unchanged |
| subcommand | `state <slug> <probe-path>` | Unchanged |
| subcommand | `release <slug>` | Unchanged |

No new entities, files, or data shapes.

## Invariants

- No role ever commits anything, in any phase; the branch still points at the
  commit the flow started from forever (nothing is ever committed onto it).
- Positioning is refused, never forced: no `-B`, no `--force`/`-f` on any git
  invocation, no `reset`, no `clean`, no `stash`, no `restore`, no
  `branch -d`/`-D`.
- Success states imply positioned: `state=created`/`state=reused` are printed
  only after the session actually sits on `antz/<slug>`.
- A refused or failed ensure alters nothing: working tree, HEAD position, and
  every branch ref are byte-identical before and after.
- `state=reused` is never printed when the branch does not exist (the old
  loose arm that printed a false `reused` on a failed create is replaced by
  the truthful `state=no_branch` stop).
- The orchestrator never runs git beyond the embedded script's four
  subcommands, never runs the human follow-ups, and never names an integration
  branch.
- AGENTS.md and CLAUDE.md carry the two updated gotcha bullets with identical
  text in both files (the files' shared-bullet sync convention).
- The `## Versioning` sections and the CHANGELOG's earlier entries are
  untouched; the 4.0.0 bump is mandated by the existing versioning policy
  (`agents/prompts/orchestrator.prompt` changed → bump in the same change,
  graded major: breaking workflow contract).

## Out of scope

- `install.sh` logic — it renders `orchestrator.prompt` verbatim; no behavior,
  flag, path, or mapping change (installed copies pick the new prompt up via
  the normal re-render; the version marker update comes from the bump).
- `agents/meta/*.yaml` and the other three role prompts.
- The `state` probe script's internals and steps 2–4 of the orchestrator's
  Process (classification, rejection routing) — untouched.
- `docs/orchestrator.md` and `docs/worktree-isolation-plan*.md` — historical
  design records that self-declare they are not kept in sync and contain no
  branch-marker-law claims contradicting this contract.
- The `worktree` branch's sibling variant (worktree isolation + gated per-role
  commits) — maintained in parallel, untouched.
- The verifier's Merge & Archive mechanics (`git mv` works identically with
  the session positioned on the flow branch; staged, never committed).
- Anything in `spdd/specs/` or `spdd/archive/` (the verifier merges; this
  change's artifacts are preserved on approval).

## Governing spec situation

All scenarios below are **ADD**: `spdd/specs/` holds no domain for the flow
script or the orchestrator prompt's flow instructions (it holds `posixsh.md`,
`set-model.md`, `specifier-role.md`, `versioning.md`). The verifier creates a
new domain file at merge — suggested name `spdd/specs/flow-branch.md` — and
merges every scenario into it as ADD.

## Relevant files (pointers, not a walkthrough)

- `agents/prompts/orchestrator.prompt` — the change's core: embedded script
  fence (`#!/bin/sh` … `esac`, incl. the `ensure` case and the header comment's
  law list), step 1's ensure paragraph and discover table, step 5's release
  table + human follow-up print, `## Owns` first bullet, `## What you don't
  do` git bullet. The script must stay the prompt's first 3-space-indented
  bare fence and the probe its ``` `sh` ``` fence — both test files extract
  them mechanically.
- `tests/antz-flow_test.sh` — the unit suite to update: invert the
  "never checks anything out" assertion into checkout/positioning assertions;
  add the refused and `no_branch` stops; keep never-commits, no-destruction,
  release gates, discover, state, and preflight tests. One test per scenario
  id, ids in the reported test names.
- `AGENTS.md` / `CLAUDE.md` — the "Branch-marked flow, never committed" and
  "Release gating, never speculative" gotcha bullets (byte-identical between
  the two files today; keep them identical).
- `VERSION` / `CHANGELOG.md` — the mandatory bump (4.0.0) and its entry.
- `tests/orchestrator-status-probe_test.sh` — guards the probe fence's shape;
  untouched by this change but must keep passing.

## End-to-end QA suite

`e2e-qa.feature`, one series per layer: the user-visible flow-script workflow
(`e2e-ensure-01/02`), a live orchestrated run (`e2e-orchestrator-01`), and the
version/docs surface a user sees (`e2e-docs-01`). The coder ships them as
explicit SKIP stubs; the verifier exercises them live.
