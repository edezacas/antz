# Change: precision-gaps — sub-spec 02 of 05 (coder and verifier checks).
#
# Cambio C items 2, 3, 4, and 5 (verifier half) of
# docs/plan-revision-2026-09.md §3, with the second-review note fixing the
# plan threshold at N=8. Closes the precision gaps in the coder's
# pre-planning id check and plan threshold and in the verifier's "code
# present" gate and domain-file rule. Declared destination domain:
# role-surfaces.

Feature: the coder's and verifier's checks are mechanical

  Background:
    Given "agents/prompts/coder.prompt" carrying the "## Process" section's
      pre-planning id check and "Plan briefly" bullets
    And "agents/prompts/verifier.prompt" carrying the Input Rule's code-present
      bullet and the Merge & Archive merge bullet
    And "spdd/specs/role-surfaces.md" as the destination domain this
      sub-spec's scenarios merge into
    And the receipts domain's grammar unchanged: a sub-spec's result receipt
      is the file "spdd/changes/<slug>/NN-<feature>.result"

  # ADD - rolechecks-01: the id search is a literal grep of the id in the
  # project's test files.
  Scenario: rolechecks-01
    When the reader reads the coder prompt's pre-planning bullet (checking
      the working tree for scenario ids that already have a passing or
      skipped test)
    Then it states the search mechanism: a literal grep of the sub-spec's
      scenario id in the project's test files (the files carrying the
      unit-test suite)
    And it keeps the bullet's meaning otherwise unchanged: ids that already
      have a passing or skipped test are treated as done rather than redone
    And in this repository the criterion is observable: a literal grep of an
      implemented id (for example "rolechecks-01") in "tests/" finds the test
      named after it

  # ADD - rolechecks-02: the plan threshold is fixed at N=8.
  Scenario: rolechecks-02
    When the reader reads the coder prompt's "Plan briefly" bullet
    Then it states the mechanical threshold: a plan of more than 8
      implementation steps for the sub-spec, or more than 1 shared contract
      needing change, marks the change for splitting (the coder flags that
      the specifier should split it further)
    And the vague "if the plan for one sub-spec is long" wording is gone
    And the escalation semantics are unchanged: refusing or escalating over a
      shared contract that needs changing still writes the "BLOCKED:" stub
      per the existing rule

  # ADD - rolechecks-03: "code present" is a mechanical criterion.
  Scenario: rolechecks-03
    When the reader reads the verifier prompt's Input Rule bullet about
      sub-specs with no code changes yet
    Then it defines "code present" mechanically: a sub-spec has code present
      when its declared scenario ids appear in the project's test files — the
      same literal grep of the id as rolechecks-01 — or its result receipt
      ("spdd/changes/<slug>/NN-<feature>.result") exists
    And it keeps the routing meaning unchanged: a named sub-spec with no code
      present stops and reports there's nothing to verify, and the
      whole-change form verifies every sub-spec with code present and flags
      those without as unimplemented rather than stopping outright

  # ADD - rolechecks-04: one spec file per domain, created when the domain is
  # new; the destination domain is read from the change's README.
  Scenario: rolechecks-04
    When the reader reads the verifier prompt's Merge & Archive merge bullet
    Then it states the domain-file rule: one file per domain, at
      "spdd/specs/<domain>.md", domain names kebab-case
    And it states the resolution: each sub-spec's destination domain is read
      from the change README's section for that sub-spec (conventions-03),
      and the merge goes into that domain's file
    And it states the creation rule: when the domain is new (no
      "spdd/specs/<domain>.md" exists), the verifier creates the file — a
      "# Domain: <domain>" header plus the merged scenarios, under the same
      merge rules
    And it keeps the never-overwrite rule: an existing domain file is read
      first and merged scenario-by-scenario (ADD/MODIFY/REMOVE), never
      overwritten wholesale

  # ADD - rolechecks-05: the exact-string pin of the merge bullet follows the
  # legitimate reword.
  Scenario: rolechecks-05
    Given "tests/roles_test.sh"'s roles-03 assertion pins the pre-change
      merge-bullet sentence verbatim
    When the verifier prompt's merge bullet is extended by rolechecks-04
    Then the pin is re-scoped to the extended bullet: it asserts the new
      content (the per-domain file rule, the kebab-case naming, and the
      create-when-new rule) alongside the surviving merge and never-overwrite
      wording
    And roles-01, roles-02, roles-04, and roles-05's assertions keep passing
      unmodified, and the rest of the suite stays green

### Invariants
- The id-search convention is defined once and used identically by the
  coder's pre-planning check and the verifier's code-present check.
- "Code present" reads receipt existence only — never the receipt's grammar
  (a malformed receipt is the doubtful-receipt machinery's concern, not this
  criterion's).
- The threshold N=8 is fixed — no per-change negotiation, no configuration.
- The specifier prompt, the orchestrator prompt, and the probe script are
  byte-unchanged by this sub-spec (conventions', sluglimit's, and
  probealign's scopes respectively).
- No role ever commits anything; the work stays uncommitted in the working
  tree.

## Out of scope
- The receipt grammar itself (the receipts domain) and the probe's
  declared-id extraction (probealign).
- The specifier's authoring conventions (conventions) and the slug
  derivation (sluglimit).
- Cambio D (style rewrite) and Cambio E (install.sh/docs hardening).
