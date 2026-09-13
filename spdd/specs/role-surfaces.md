# Domain: role-surfaces

## Origin
- Specced and delivered from change `fix-orchestrator-flow` (2026-09-12,
  pending merge/archive). This is a **new standalone spec domain**: before
  this change no spec domain covered the coder's write-surface ownership or
  the verifier's archive-step instruction. Plan items 1.4 and 1.6 of
  `docs/plan-revision-2026-09.md` §3 Cambio A.
- Extended by change `precision-gaps` (merged 2026-09-13): adds five
  rolechecks-scenarios to this domain (ADD `rolechecks-01..05`), covering
  the coder's literal-grep id search and fixed plan threshold, the
  verifier's mechanical "code present" criterion and per-domain spec-file
  rule with create-when-new, and the re-scoped roles-03 pin. The change's
  scenarios and end-to-end QA are preserved for history in
  `spdd/archive/precision-gaps/`, not reproduced here.

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

## Feature: the coder's and verifier's checks are mechanical (from 02-rolechecks.feature, change `precision-gaps`)

  Background:
    Given "agents/prompts/coder.prompt" carrying the "## Process" section's
      pre-planning id check and "Plan briefly" bullets
    And "agents/prompts/verifier.prompt" carrying the Input Rule's code-present
      bullet and the Merge & Archive merge bullet

  # ADD - rolechecks-01: the id search is a literal grep of the id in the
  # project's test files.
  Scenario: rolechecks-01
    When the reader reads the coder prompt's pre-planning bullet
    Then it states the search mechanism: a literal grep of the sub-spec's
      scenario id in the project's test files (the files carrying the
      unit-test suite)
    And it keeps the bullet's meaning otherwise unchanged: ids that already
      have a passing or skipped test are treated as done rather than redone

  # ADD - rolechecks-02: the plan threshold is fixed at N=8.
  Scenario: rolechecks-02
    When the reader reads the coder prompt's "Plan briefly" bullet
    Then it states the mechanical threshold: a plan of more than 8
      implementation steps for the sub-spec, or more than 1 shared contract
      needing change, marks the change for splitting
    And the vague "if the plan for one sub-spec is long" wording is gone

  # ADD - rolechecks-03: "code present" is a mechanical criterion.
  Scenario: rolechecks-03
    When the reader reads the verifier prompt's Input Rule bullet about
      sub-specs with no code changes yet
    Then it defines "code present" mechanically: a sub-spec has code present
      when its declared scenario ids appear in the project's test files — the
      same literal grep of the id as rolechecks-01 — or its result receipt
      ("spdd/changes/<slug>/NN-<feature>.result") exists
    And it keeps the routing meaning unchanged

  # ADD - rolechecks-04: one spec file per domain, created when the domain is
  # new; the destination domain is read from the change's README.
  Scenario: rolechecks-04
    When the reader reads the verifier prompt's Merge & Archive merge bullet
    Then it states the domain-file rule: one file per domain, at
      "spdd/specs/<domain>.md", domain names kebab-case
    And it states the resolution: each sub-spec's destination domain is read
      from the change README's section for that sub-spec
    And it states the creation rule: when the domain is new, the verifier
      creates the file
    And it keeps the never-overwrite rule: an existing domain file is read
      first and merged scenario-by-scenario (ADD/MODIFY/REMOVE), never
      overwritten wholesale

  # ADD - rolechecks-05: the exact-string pin of the merge bullet follows the
  # legitimate reword.
  Scenario: rolechecks-05
    Given "tests/roles_test.sh"'s roles-03 assertion pins the pre-change
      merge-bullet sentence verbatim
    When the verifier prompt's merge bullet is extended by rolechecks-04
    Then the pin is re-scoped to the extended bullet
    And roles-01, roles-02, roles-04, and roles-05's assertions keep passing
      unmodified, and the rest of the suite stays green

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
