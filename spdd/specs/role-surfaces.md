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
- Extended by change `optimize-test-suite` (merged 2026-09-14): adds five
  rolesdecouple scenarios (ADD `rolesdecouple-01..05`) verifying that
  `tests/roles_test.sh` and `tests/rolechecks_test.sh` are decoupled from
  the other suites: no cross-suite execution, no cross-suite source
  assertions, no git-HEAD byte-pins of other suites' content. The removed
  sites (roles-05, rolechecks-05, verifier-02's probe-suite rerun,
  testsuite-08's glob half) are decoupled per the four permanent laws
  enforced by the hygiene suite. The change's scenarios and end-to-end QA
  are preserved for history in `spdd/archive/optimize-test-suite/`, not
  reproduced here.

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

## Feature: the verifier's rejection-entry duty is a short list with the same contract (from 03-verifier.feature, change `style-rewrite`)

  Background:
    Given "agents/prompts/verifier.prompt" whose "## On Rejection" section
      opens with a single 100-130-word sentence

  # MODIFY - verifier-01: the rejection-entry sentence becomes a short list.
  Scenario: verifier-01
    When the "## On Rejection" opening bullet is rewritten as a lead line
      plus a short list
    Then the lead line states the duty: before reporting, append (never
      overwrite) one entry to the change's REJECTED.md, via Bash
    And the list carries, one item each: the entry's heading line reading
      exactly "## Rejection <n>" and nothing else; the reason it must be
      literal; and the content that follows the heading
    And the section's second bullet (naming the sub-spec each blocker traces
      to) is unchanged
    And no item carries nested parentheticals deeper than one level

  # ADD - verifier-02: the new pins live with the verifier-suite home.
  Scenario: verifier-02
    When tests/roles_test.sh is extended with verifier-01 and verifier-02
      test functions and runs
    Then the new pins require the lead-line duty, the exact-heading item,
      the probe-counts reason, and the blockers-content item
    And tests/orchestrator-status-probe_test.sh passes unmodified
    And the extended suite exits 0

## Feature: one form per concept, and the Working-Root triplication is a documented editing rule (from 06-terminology.feature, change `style-rewrite`)

  Background:
    Given the four prompts spelling the slug placeholder two ways

  # MODIFY - terminology-01: `<change-slug>` becomes `<slug>` at all seven
  # sites; the suite pins follow loudly.
  Scenario: terminology-01
    When the seven `<change-slug>` sites are rewritten to `<slug>`
    Then the string "change-slug" no longer appears in any of the four prompts
    And the machine-line formats are untouched
    And the suite pins follow in the same change

  # ADD - terminology-02: one form per concept, swept and pinned.
  Scenario: terminology-02
    When the four prompts are swept for variant spellings
    Then the sweep passes: no prompt contains "sub spec" or "subspecs", no
      prompt uses "framework" where the client is meant, and the slug
      placeholder is `<slug>` everywhere prose names it
    And the sweep's declared exemptions hold

  # ADD - terminology-03: the Working-Root triplication becomes a documented,
  # pinned editing rule.
  Scenario: terminology-03
    When the editing rule is documented and pinned
    Then AGENTS.md and CLAUDE.md each carry one new gotcha bullet,
      byte-identical between the two files
    And a test asserts the three prompts' "## Working Root" sections are
      byte-identical to each other
    And the new docs bullet is additive

## Feature: roles_test.sh and rolechecks_test.sh are decoupled from the other suites (from optimize-test-suite)

  Background:
    Given "tests/roles_test.sh" and "tests/rolechecks_test.sh", both
      sourcing the harness library
    And the decoupling law: no suite executes another suite, and no suite
      asserts another test file's source content or output — verifying
      "the whole suite is green" is the documented runner's job

  # ADD - rolesdecouple-01: testsuite-08 keeps its product halves and drops
  # the glob half and the idiom scan.
  Scenario: rolesdecouple-01
    When testsuite-08 runs
    Then it executes no other suite and scans no tests/*_test.sh source
      (the recursion-guard flag and the excluded-suite cases are gone with
      the glob)
    And it still asserts, from one hermetic render through the harness
      library: no role prompt carries an "# antz-include:" marker or a
      script-content fence, the four orchestration scripts install under
      the resolved libdir, and no rendered client file carries a fence or
      an include marker
    And every other id the suite registered before the refactor stays
      registered and green

  # ADD - rolesdecouple-02: roles-05 is removed whole — every clause is
  # cross-test coupling.
  Scenario: rolesdecouple-02
    When the roles suite runs
    Then roles-05 is no longer registered
    And no line of roles_test.sh executes skills-activation-prompts,
      receipts, or closingblock suites, observes their output, or requires
      their source content
    And roles-01..04 and the suite's other retained ids stay registered
      and green

  # ADD - rolesdecouple-03: verifier-02 keeps its product pins and its
  # frozen-surface guard, drops the probe-suite rerun.
  Scenario: rolesdecouple-03
    When verifier-02 runs
    Then it executes no other suite
    And it still pins the rejection-contract wording on the verifier
      prompt and asserts scripts/orchestration/ and agents/meta/ are
      byte-identical to git HEAD — a frozen-surface guard that is green in
      both the uncommitted and the committed era

  # ADD - rolesdecouple-04: terminology-03 keeps the docs bullet pins and
  # drops the five-suite loop.
  Scenario: rolesdecouple-04
    When terminology-03 runs
    Then it executes no other suite
    And it still asserts that the three role prompts' "## Working Root"
      sections are byte-identical to each other, and that AGENTS.md and
      CLAUDE.md each carry one identical Working-Root-triplication gotcha
      bullet stating the rule

  # ADD - rolesdecouple-05: rolechecks-05 is removed whole — its
  # byte-identity-vs-HEAD on roles test functions and its roles-suite
  # rerun are one-change migration guards.
  Scenario: rolesdecouple-05
    When the rolechecks suite runs
    Then rolechecks-05 is no longer registered
    And no line of rolechecks_test.sh executes roles_test.sh or byte-
      compares any of its functions against a git HEAD copy
    And rolechecks-01..04 stay registered and green, unchanged

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
