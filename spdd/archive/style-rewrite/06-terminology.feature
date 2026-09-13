# Change: style-rewrite — sub-spec 06 of 07 (terminology unified; the
# Working-Root triplication rule documented).
#
# Implements the terminology half of Cambio D (docs/plan-revision-2026-09.md
# §3): the path placeholder `<change-slug>` and `<slug>` are two spellings of
# one concept — unified to `<slug>` (the form the orchestrator, the coder's
# Receipt section, and the verifier's code-present bullet already use); the
# one-form-per-concept rule for `sub-spec`, `slug`, `client`, and
# `working root` is pinned as a sweep; and the plan's editing rule — "##
# Working Root" is duplicated verbatim across the three role prompts on
# purpose (per-prompt autonomy); every future edit must touch all three sites
# — is documented in AGENTS.md and CLAUDE.md (byte-identical, per the docs'
# shared-bullet convention) and pinned by a test so drift is caught.
#
# Out of the unification's scope, deliberately: the delegation-header line
# "Working root: <repo root absolute path>" and the orchestrator's "main
# checkout" descriptions are pinned byte-identical by
# tests/orchestrator-skills-block_test.sh and tests/antz-flow_test.sh — suites
# this change does not touch — and the probe-output tokens `subspec=` and
# `<subspec-file>=` are machine-line formats the hard constraints protect.
# They are declared exempt in the sweep, not silently left inconsistent.
#
# Declared destination domain: role-surfaces.

Feature: one form per concept, and the Working-Root triplication is a documented editing rule

  Background:
    Given the four prompts spelling the slug placeholder two ways:
      "spdd/changes/<change-slug>/" in agents/prompts/specifier.prompt (the
      "## Output, written to" heading and the OPEN_QUESTIONS bullet),
      agents/prompts/coder.prompt (the "## Owns" bullet and the Input Rule's
      missing-change-dir bullet), and agents/prompts/verifier.prompt (the
      Input Rule's missing-change-dir bullet, the Merge & Archive move
      bullet, and the On Rejection path) — against "spdd/changes/<slug>/"
      everywhere else
    And tests pinning the old spellings: tests/roles_test.sh (roles-01's
      coder Input Rule line, roles-02's coder Owns line, roles-03's
      move-bullet line), tests/rolechecks_test.sh (rolechecks-03/04's
      working-vs-HEAD byte-identity windows on the changed verifier bullets),
      and tests/closingblock_test.sh (the specifier report extract keyed on
      the full heading text)
    And the three role prompts carrying byte-identical "## Working Root"
      sections (specifier, coder, verifier) — the triplication the editing
      rule documents

  # MODIFY - terminology-01: `<change-slug>` becomes `<slug>` at all seven
  # sites; the suite pins follow loudly.
  Scenario: terminology-01
    When the seven `<change-slug>` sites are rewritten to `<slug>`: the
      specifier's Output heading (reading "## Output, written to
      `spdd/changes/<slug>/`") and its OPEN_QUESTIONS bullet, the coder's
      Owns bullet and Input Rule bullet, and the verifier's Input Rule
      bullet, Merge & Archive move bullet, and On Rejection path
    Then the string "change-slug" no longer appears in any of the four
      prompts
    And the machine-line formats are untouched: `Change slug: <slug>` in the
      delegation template, the flow subcommand invocations (`ensure <slug>`,
      `state <slug> <probe-tempfile>`, `release <slug>`), and every
      `state=`/`gate=`/`class=`/`receipt=`/`id=`/`test_command=` line are
      byte-unchanged
    And the suite pins follow in the same change: roles-01's coder Input Rule
      line, roles-02's coder Owns line, and roles-03's move-bullet line are
      re-pinned to the `<slug>` spellings; closingblock's specifier extract
      anchor is re-keyed on the new heading text; and rolechecks-03/04's
      working-vs-HEAD byte-identity windows on the changed verifier bullets
      are gated from birth on the change_pending pattern (enforced while
      verifier.prompt differs from HEAD and HEAD's bullets still read
      `<change-slug>`, retired with a loud note otherwise, the absolute
      content pins staying enforced in every repo state)

  # ADD - terminology-02: one form per concept, swept and pinned.
  Scenario: terminology-02
    When the four prompts are swept for variant spellings of the four
      concepts
    Then the sweep passes: no prompt contains "sub spec" (with a space) or
      "subspecs", no prompt uses "framework" where the client is meant, and
      the slug placeholder is `<slug>` everywhere prose names it
    And the sweep's declared exemptions hold: the probe-output tokens
      "subspec=" and "<subspec-file>=" (machine-line formats), the
      delegation-header line "Working root: <repo root absolute path>" and
      the orchestrator's "main checkout" descriptions (byte-pinned by suites
      this change does not touch)
    And the sweep is a test (named after this scenario id) so a future variant
      spelling fails it

  # ADD - terminology-03: the Working-Root triplication becomes a documented,
  # pinned editing rule.
  Scenario: terminology-03
    When the editing rule is documented and pinned
    Then AGENTS.md and CLAUDE.md each carry one new gotcha bullet,
      byte-identical between the two files, stating that the "## Working
      Root" section is duplicated verbatim across the three role prompts
      (specifier, coder, verifier) on purpose — per-prompt autonomy — and
      that every future edit of it must touch all three sites
    And a test (named after this scenario id) asserts the three prompts'
      "## Working Root" sections are byte-identical to each other, so any
      edit touching fewer than three sites fails it
    And the new docs bullet is additive: the docs' existing gotcha bullets
      (the closing-block bullet, the receipt-convention bullet, the
      write-surface bullet, and the rest) pass their suites byte-unchanged

### Invariants
- One form per concept in the prompts: `sub-spec`, `slug` (`<slug>`), and
  `client` each have a single spelling; `working root` is the term of art,
  with the documented byte-pinned exemptions.
- The three "## Working Root" sections stay byte-identical — the triplication
  is per-prompt autonomy, not drift.
- Every diff-window assertion in the updated suites is born gated on the
  change_pending pattern (stacking-robust: HEAD carrying the marker content
  retires the window instead of resurrecting it against a later legitimate
  edit).
- agents/meta/*, install.sh, and scripts/orchestration/* are byte-unchanged
  by this sub-spec; AGENTS.md and CLAUDE.md change only by the one additive
  identical bullet.

## Out of scope
- Rewording the delegation-header line "Working root: <repo root absolute
  path>" or the orchestrator's "main checkout" prose (byte-pinned by
  tests/orchestrator-skills-block_test.sh and tests/antz-flow_test.sh, which
  this change does not touch).
- The probe-output tokens `subspec=` and `<subspec-file>=` (machine-line
  formats protected by the hard constraints).
