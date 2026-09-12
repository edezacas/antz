# Domain: role-surfaces

## Origin
- Specced and delivered from change `fix-orchestrator-flow` (2026-09-12,
  pending merge/archive). This is a **new standalone spec domain**: before
  this change no spec domain covered the coder's write-surface ownership or
  the verifier's archive-step instruction. Plan items 1.4 and 1.6 of
  `docs/plan-revision-2026-09.md` §3 Cambio A.

## Goal
The coder's directory ownership is stated by write surface, not read surface,
and the verifier's archive step is a plain `mv` as the only instruction with
its reason stated in the prompt.

## Shared contracts
- The coder prompt's Input Rule, `## Owns` line, and `## Receipt` section all
  name the same surfaces (reading `spdd/changes/` and `spdd/specs/` as
  read-only context, writing the implementation and tests wherever they belong
  in the project, writing the receipt inside `spdd/changes/<slug>/`, never
  touching `spdd/archive/`).
- The AGENTS.md and CLAUDE.md "Strict directory ownership" gotcha bullet
  restates the write-surface contract identically (byte-identical between the
  two files, the shared-bullet convention).
- The receipt grammar itself (test_command= and per-id lines) is unchanged by
  this domain; it lives in `spdd/specs/receipts.md`.

## Feature: the coder's directory ownership is stated by write surface

  Background:
    Given "agents/prompts/coder.prompt" carrying the "## Owns" line naming
      "spdd/changes/<change-slug>/" and existing "spdd/specs/" for context,
      and the Input Rule bullet stating directory ownership
    And "AGENTS.md" and "CLAUDE.md", each carrying the identical
      "Strict directory ownership" gotcha bullet

  # ADD - roles-01
  The coder prompt's Input Rule directory-ownership bullet states the surface
  by write surface: the coder reads `spdd/changes/` and `spdd/specs/` — both
  as read-only context, `spdd/specs/` never written — and writes the code and
  tests the sub-spec calls for wherever they belong in the project, plus its
  receipt in `spdd/changes/<slug>/`, and never touches `spdd/archive/`. The
  old read-surface phrasing ("Read only from spdd/changes/") is gone, with its
  contradiction against the "## Owns" line. The rest of the Input Rule is
  unchanged: the missing-change-dir stop, the missing-sub-spec stop, the
  OPEN_QUESTIONS.md hard stop, and the refuse-a-multi-layer-plan rule all keep
  their meaning.

  # ADD - roles-02
  The coder prompt stays internally consistent — the Owns line, the
  write-surface bullet, and the Receipt duty name the same surfaces: all three
  name the same surfaces: reading `spdd/changes/` and `spdd/specs/` as
  context, writing the implementation and tests wherever they belong in the
  project, and writing the receipt inside `spdd/changes/<slug>/`. The receipt
  duty itself is unchanged by this domain (the `test_command=` grammar is the
  receipts domain's concern).

## Feature: the verifier's archive step is a plain mv

  Background:
    Given "agents/prompts/verifier.prompt" carrying the Merge & Archive bullet

  # ADD - roles-03
  The verifier's archive-move instruction is a plain `mv` as the only
  mechanism: move `spdd/changes/<change-slug>/` to
  `spdd/archive/<change-slug>/` unmodified after the merge succeeds. The
  reason is stated in the prompt itself: `git mv` on untracked files always
  fails, since nothing is ever committed. `git mv` no longer appears as an
  offered option anywhere in the prompt, and the release-gate half of the
  reason survives (the orchestrator's release gate only reads the working
  tree). The rest of Merge & Archive is unchanged: the move happens only on
  approved or approved-with-warnings, never archives a rejected change, and
  the never-overwrite-a-domain-spec rule stands.

## Feature: the policy docs' gotcha bullet follows the write-surface contract

  Background:
    Given "AGENTS.md" and "CLAUDE.md", each carrying the "Strict directory
      ownership" gotcha bullet

  # ADD - roles-04
  The "Strict directory ownership" gotcha bullet of AGENTS.md and CLAUDE.md
  both state the write-surface contract identically (byte-identical bullet,
  the files' shared-bullet convention): the coder reads `spdd/changes/` and
  `spdd/specs/` as read-only context, never writing `spdd/specs/`, writes the
  code and tests the sub-spec calls for wherever they belong in the project
  plus its receipt in `spdd/changes/<slug>/`, and never touches
  `spdd/archive/`; the verifier merges into specs and archives changes but
  never overwrites a domain spec file wholesale (merge scenario-by-scenario,
  ADD/MODIFY/REMOVE). Neither doc anywhere states that the coder only reads
  `spdd/changes/`, nor that the coder must never touch `spdd/specs/`.

## Feature: the prompt guards that pin pre-change lines are retired

  # ADD - roles-05
  The test suites that pin every pre-change line of the coder and verifier
  prompts are retired loudly — the rewordings are legitimate — and no other
  suite pins the removed wording: the coder-prompt and verifier-prompt
  additive-vs-HEAD guards (the every-HEAD-line-survives-verbatim checks) no
  longer fail. They are retired with a loud printed note — the same
  retirement-note precedent as the render byte-identity retirements — or
  re-scoped the way the sessionguards removal check is gated, so the
  legitimate rewordings pass while the suites keep their other assertions. The
  suites that pin surrounding content stay green without edits: no test pins
  `git mv`, no test pins the coder's "Read only from" wording, and the
  closingblock/receipts/skills-activation extracts of the coder and verifier
  report and receipt sections keep passing.

## Invariants
- The governing rule holds: no role, including the orchestrator, may depend on
  another role's conversational output — every routing decision is derived
  from disk.
- No role ever commits anything; the orchestrator never writes under `spdd/`.
- The receipt grammar is unchanged by this domain; it lives in
  `spdd/specs/receipts.md`.
- The access model is unchanged by this domain; it lives in
  `spdd/specs/access-model.md`. The `access: readwrite` values for coder,
  specifier, and verifier are already correct.

## Out of scope
- The receipt grammar (test_command=, per-id lines) — the receipts domain.
- The access model (meta files, install.sh mapping) — the access-model domain.
- The orchestrator's routing, session guards, or stop vocabulary — the
  flow-branch domain.
- Any change to install.sh, agents/meta/, or the orchestration scripts.

## Relevant files
- `agents/prompts/coder.prompt` — Input Rule's directory-ownership bullet
  (roles-01), consistency with `## Owns` and `## Receipt` (roles-02).
- `agents/prompts/verifier.prompt` — Merge & Archive move bullet (roles-03).
- `AGENTS.md`, `CLAUDE.md` — "Strict directory ownership" gotcha bullet
  (roles-04).
- `tests/roles_test.sh` — one test per scenario id (roles-01..05).
- `tests/skills-activation-prompts_test.sh` — additive-vs-HEAD guards
  retired (roles-05).
