# Change: fix-test-regression-precision-gaps — sub-spec 02 of 03 (the
# rolechecks suite's diff-window guards retire by gating, stacking-robustly).
#
# Fixes the test regression Change C (precision-gaps) left on master once
# committed: tests/rolechecks_test.sh compares the working
# agents/prompts/coder.prompt and tests/roles_test.sh against git HEAD as
# if HEAD were the pre-change state:
#   - rolechecks-01 asserts that stripping the appended id-search sentence
#     from the working pre-planning bullet yields HEAD's bullet verbatim --
#     post-commit HEAD's bullet IS the extended one and the check fails;
#   - rolechecks-05 asserts test_roles_03 differs from HEAD's (equality
#     reading "the pin was not re-scoped") and frames HEAD's roles-03 as
#     pinning the pre-change merge-bullet sentence -- post-commit the
#     re-scoped pin IS HEAD's and the inversion check fails.
#
# Fix: apply the established change_pending() gating pattern of
# tests/bump440_test.sh, tests/bump450_test.sh, and tests/bump460_test.sh
# (retiro ruidoso por gating, stacking-robusto) to those working-vs-HEAD
# window assertions: enforced while the guarded artifact's reword is
# pending (uncommitted), retired with a loud note once HEAD carries the
# change's marker content. The content pins and the observable criterion
# are absolute (read no git HEAD) and stay enforced in every repo state.
#
# Scope: tests/rolechecks_test.sh only. agents/prompts/coder.prompt,
# agents/prompts/verifier.prompt, and tests/roles_test.sh are byte-unchanged
# by this sub-spec (Change C already committed their rewordings).
#
# Declared destination domain: role-surfaces.

Feature: rolechecks-01 and rolechecks-05's working-vs-HEAD window assertions retire by gating, stacking-robustly

  Background:
    Given "tests/rolechecks_test.sh" whose rolechecks-01 and rolechecks-05
      assert the working "agents/prompts/coder.prompt" and
      "tests/roles_test.sh" against git HEAD
    And git HEAD carrying the committed rewordings (HEAD's pre-planning
      bullet already carries the appended id-search sentence; HEAD's
      roles-03 already pins the extended merge bullet), so both window
      inversions misread a committed state as an unre-scoped pin
    And the established change_pending() gating pattern of
      tests/bump440_test.sh, tests/bump450_test.sh, and tests/bump460_test.sh:
      a HEAD-comparison guard is enforced only while the guarded artifact
      differs from HEAD and HEAD does not yet carry the change's marker
      content, and retires vacuously with a loud note otherwise -- so a
      later legitimate edit of the artifact can never resurrect the guard

  # MODIFY - rolechecks-01: the id search stays a literal grep of the id in
  # the project's test files, enforced absolutely; the
  # appended-sentence-vs-HEAD window check retires by gating.
  Scenario: rolechecks-01
    When tests/rolechecks_test.sh runs -- whether the coder-prompt reword
      is pending (uncommitted) or committed
    Then the content pins stay enforced in both states without reading git
      HEAD: the pre-planning bullet's "Before planning" framing and
      scenario-id shape, the shared id-search convention (the same literal
      grep the verifier's code-present criterion uses), the
      passing-or-skipped done-not-redo meaning, and the observable
      criterion (a literal grep of the id rolechecks-01 in tests/ finds the
      run_test-registered test named after it)
    And the window check -- stripping the appended mechanism sentence from
      the working bullet yields HEAD's pre-planning bullet verbatim -- is
      gated on the suite's change_pending predicate for
      "agents/prompts/coder.prompt": enforced while the file differs from
      HEAD and HEAD's pre-planning bullet does not yet carry the appended
      id-search sentence (the reword pending), retired with a loud note
      otherwise
    And the predicate keeps the bump-pattern conjunction (stacking-robust):
      HEAD already carrying the appended sentence means any current
      coder.prompt diff is a later change's legitimate edit, so the window
      check stays retired instead of resurrecting against that later edit
    And the retirement prints one loud note naming "coder.prompt" and
      stating the vacuous retirement, greppable in the established "note:"
      style, while the rolechecks-01 test stays registered (retired by
      gating, never deleted) and passes in both states
    And the suite exits 0 in both states -- with the window really enforced
      while pending (a coder.prompt edit breaking the appended-sentence
      shape fails it) and with only the note path once committed

  # MODIFY - rolechecks-05: the roles-03 pin is re-scoped to the extended
  # bullet, enforced absolutely; the HEAD-relative re-scope window
  # assertions retire by gating.
  Scenario: rolechecks-05
    When tests/rolechecks_test.sh runs -- whether the roles_test.sh
      re-scope is pending (uncommitted) or committed
    Then the re-scope content pins stay enforced in both states without
      reading git HEAD: the working test_roles_03 still asserts the
      surviving pre-change merge-bullet sentence verbatim alongside the
      extended bullet's new content (the per-domain file rule, the
      kebab-case naming, the create-when-new rule), and the whole roles
      suite passes with its five roles tests
    And the HEAD-relative window assertions -- HEAD's roles-03 pinning the
      pre-change merge-bullet sentence (the Given), test_roles_03 differing
      from HEAD's (equality reading "the pin was not re-scoped"), and
      roles-01, roles-02, roles-04, and roles-05 byte-identical to HEAD --
      are gated on the suite's change_pending predicate for
      "tests/roles_test.sh": enforced while the file differs from HEAD and
      HEAD's roles-03 does not yet pin the extended bullet (the re-scope
      pending), retired with a loud note otherwise
    And the predicate keeps the bump-pattern conjunction (stacking-robust):
      HEAD already carrying the re-scoped pin means any current
      roles_test.sh diff is a later change's legitimate edit, so the window
      assertions stay retired instead of resurrecting against that later
      edit
    And the retirement prints one loud note naming "roles_test.sh" and
      stating the vacuous retirement, greppable in the established "note:"
      style, while the rolechecks-05 test stays registered (retired by
      gating, never deleted) and passes in both states
    And the suite exits 0 in both states -- with the window really enforced
      while pending (an unre-scoped roles-03 in a differing roles_test.sh
      fails it) and with only the note path once committed

### Invariants
- The content pins and the observable criterion never read git HEAD: they
  hold in any repo state, which is the durable coverage once the windows
  retire.
- The two predicates are per-artifact: the coder.prompt window and the
  roles_test.sh window gate independently (one artifact reworded while the
  other sits committed is a real state of a change touching both).
- No new diff-window assertion may be born ungated: every working-vs-HEAD
  window assertion in this suite carries the change_pending gate from
  birth.
- The suite never commits, never mutates the working tree, and never
  touches the two prompts or tests/roles_test.sh.

## Out of scope
- rolechecks-02/03/04's byte-identity-vs-HEAD comparisons of surrounding
  bullets (passing in both repo states today; retiring them is a future
  change's call if a later reword trips them).
- The sluglimit and conventions suites (sub-specs 01 and 03).
- Any change to agents/prompts/coder.prompt, agents/prompts/verifier.prompt,
  tests/roles_test.sh, VERSION, or CHANGELOG.md.
