# Change: fix-test-regression-precision-gaps — sub-spec 01 of 03 (the
# sluglimit suite's diff-window guard retires by gating, stacking-robustly).
#
# Fixes the test regression Change C (precision-gaps) left on master once
# committed: tests/sluglimit_test.sh's sluglimit-02 asserts the working
# agents/prompts/orchestrator.prompt's diff vs HEAD removes exactly one line
# and adds exactly one (the HEAD and working derivation bullets verbatim) --
# a window that assumed HEAD = the pre-change state, valid only while the
# flow's work is uncommitted. With the reword committed (7969c2b) the diff
# reads 0 removed / 0 added and the suite fails.
#
# Fix: apply the established change_pending() gating pattern of
# tests/bump440_test.sh, tests/bump450_test.sh, and tests/bump460_test.sh
# (retiro ruidoso por gating, stacking-robusto) to sluglimit-02's
# working-vs-HEAD window assertions: enforced while the derivation-bullet
# reword is pending (uncommitted), retired with a loud note once committed.
# The pinned-meaning assertions are absolute (read no git HEAD) and stay
# enforced in every repo state -- they are the durable coverage once the
# window retires.
#
# Scope: tests/sluglimit_test.sh only. agents/prompts/orchestrator.prompt
# and scripts/orchestration/antz-flow.sh are byte-unchanged by this
# sub-spec (Change C already committed the reword; the flow script is not
# part of this regression).
#
# Declared destination domain: flow-branch.

Feature: sluglimit-02's working-vs-HEAD window assertions retire by gating, stacking-robustly

  Background:
    Given "tests/sluglimit_test.sh" whose sluglimit-02 test pins the
      collision rules' meaning of the step-1 slug-derivation bullet and
      asserts the working "agents/prompts/orchestrator.prompt" against git
      HEAD
    And git HEAD carrying the committed derivation-bullet reword (HEAD's
      bullet already states the length limit), so the old "diff vs HEAD is
      exactly one line removed and one added" window reads an empty diff
    And the established change_pending() gating pattern of
      tests/bump440_test.sh, tests/bump450_test.sh, and tests/bump460_test.sh:
      a HEAD-comparison guard is enforced only while the guarded artifact
      differs from HEAD and HEAD does not yet carry the change's marker
      content, and retires vacuously with a loud note otherwise -- so a
      later legitimate edit of the artifact can never resurrect the guard

  # MODIFY - sluglimit-02: the collision rules keep their pinned meaning --
  # enforced absolutely; the working-vs-HEAD window assertions retire by
  # gating with a loud note once the reword is committed.
  Scenario: sluglimit-02
    When tests/sluglimit_test.sh runs -- whether the derivation-bullet
      reword is pending (uncommitted) or committed
    Then the pinned-meaning assertions stay enforced in both states without
      reading git HEAD: the collision checks string ("checked against
      `spdd/changes/`, `spdd/archive/`, and `git branch --list 'antz/*'`
      for collisions"), the suffix-only-on-continuation rule, the
      ask-the-user stop on a semantically unclear continuation, the
      prompt's slug-ambiguity stop line, the numbered steps ending at 6
      with no step 7, and the dedup guard's exactly-two exceptions
    And the working-vs-HEAD window assertions -- the collision-rule tail
      byte-identical to HEAD's, the diff vs HEAD removing exactly one line
      and adding exactly one with the removed line being HEAD's bullet
      verbatim and the added line the working bullet verbatim, and the
      fence-count and table-row counts equal to HEAD's -- are gated on the
      suite's change_pending predicate: enforced while
      "agents/prompts/orchestrator.prompt" differs from HEAD and HEAD's
      derivation bullet does not yet state the length limit (the reword
      pending), retired with a loud note otherwise
    And the predicate keeps the bump-pattern conjunction (stacking-robust):
      HEAD already carrying the marker content means any current diff is a
      later change's legitimate edit, so the window guards stay retired
      instead of resurrecting against that later edit
    And the retirement prints one loud note naming "orchestrator.prompt"
      and stating the vacuous retirement, greppable in the established
      "note:" style, while the sluglimit-02 test stays registered (retired
      by gating, never deleted) and passes in both states
    And the suite exits 0 in both states -- with the window really enforced
      while pending (an orchestrator.prompt edit breaking the window shape
      fails it) and with only the note path once committed

### Invariants
- The pinned-meaning assertions never read git HEAD: they hold in any repo
  state, which is the durable coverage once the window retires.
- The gated window assertions run only while the change_pending predicate
  says pending; when retired they run nothing and print their note.
- No new diff-window assertion may be born ungated: every working-vs-HEAD
  window assertion in this suite carries the change_pending gate from
  birth.
- The suite never commits, never mutates the working tree, and never
  touches "agents/prompts/orchestrator.prompt" or
  "scripts/orchestration/antz-flow.sh".

## Out of scope
- sluglimit-01 and its flow-script byte-unchanged invariant (passing in
  both repo states today; not part of the reported regression).
- The rolechecks and conventions suites (sub-specs 02 and 03).
- Any change to agents/prompts/orchestrator.prompt,
  scripts/orchestration/antz-flow.sh, VERSION, or CHANGELOG.md.
