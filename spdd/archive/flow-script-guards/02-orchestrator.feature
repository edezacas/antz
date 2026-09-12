# Change: flow-script-guards — sub-spec 02 (orchestrator prompt: wire the new
# ensure states into the step-1 ensure instructions, the Session guards'
# latch, and the Report Format's stopped enumeration)
#
# Plan item of docs/plan-revision-2026-09.md §3 "Cambio B": "Cablear los
# estados nuevos en orchestrator.prompt (2ª revisión)" — the ensure table
# (orchestrator.prompt:28) and the latch stop list (:123) only know
# created/reused/checkout_refused/no_branch/no_commits; without this the
# orchestrator could not route `state=tree_dirty` or the invalid-slug
# rejection. The plan calls this mandatory, not optional.
#
# Layer: agents/prompts/orchestrator.prompt prose only. The flow script that
# emits the lines is sub-spec 01; this sub-spec only teaches the orchestrator
# what the lines mean and how to stop on them. No probe field, no new flow
# subcommand, no new fenced block.
#
# Hard edit-shape constraints (pinned by tests/antz-flow_test.sh
# orchestrator-01/orchestrator-05 and flow-08/flow-09): the numbered process
# steps still end at 6 (no renumbering, no step 7); the prompt keeps exactly
# 14 fence lines across 7 blocks, exactly one of them a ```sh fence (no new
# fenced block may be added — these edits are prose inside step 1 and the
# Session guards); the four tables survive with their headers; and every
# string the existing tests pin in step 1's ensure instructions stays: both
# success states position the session on `antz/<slug>` with the work
# uncommitted, `state=checkout_refused`/`state=no_branch`/`state=no_commits`
# stop-and-report, and "nothing is ever forced". The additive-vs-HEAD prose
# guards self-retire with a loud note when the prose changes vs HEAD (the
# established gate), while the structural assertions stay enforced.
#
# All ADD scenarios are new ids against spdd/specs/flow-branch.md's
# `orchestrator` feature; orchestrator-01 MODIFIES the existing id there. The
# latch's stop list is the subject of sessionguards-02 and the Report
# Format's stopped enumeration that of flow-08 — both in the same domain;
# this sub-spec extends them (their tests assert "include at least", so the
# added states are additive and the existing ids stay valid).

Feature: the orchestrator routes the new flow-script guards' states and reports their stops

  Background:
    Given "agents/prompts/orchestrator.prompt" as published before this
      change, carrying step 1's discover/ensure instructions, the Session
      guards (dedup and latch), the step 2 probe-output table, and the Report
      Format
    And the flow script of sub-spec 01, which can print "state=tree_dirty",
      "state=bad_slug", and an advisory "dirty=yes" line

  # MODIFY - orchestrator-01: step 1's ensure-state instructions document the
  # new states and the resume advisory, keeping every existing meaning.
  Scenario: orchestrator-01
    When the reader reads step 1's ensure-state instructions
    Then they keep the existing meanings unchanged: `state=created` and
      `state=reused` both position the session on branch `antz/<slug>` with
      the flow's work uncommitted, `state=checkout_refused` and
      `state=no_branch` stop and report with the user resolving it themselves
      so nothing is ever forced, and `state=no_commits` stops and asks the
      human for the initial commit
    And they document `state=tree_dirty` as the rejection a new flow gets when
      the change dir does not exist, the marker branch would be newly created,
      and "git status --porcelain" is non-empty — fail-closed by design, with
      nothing created or moved, and the user's resume action being to clean,
      commit, or gitignore the dirt and re-invoke
    And they document `state=bad_slug` as the mechanical rejection of an
      invalid slug (charset, no leading/trailing or doubled hyphen, bounded
      length) before any branch or positioning work, with nothing changed on
      disk or in git, and the user's resume action being to re-invoke with a
      valid slug
    And they document `dirty=yes` as an advisory line appended after any
      `state=reused` whose working tree is already dirty (a resume or a
      branch-only reuse): it changes no routing and is not a stop, and the
      orchestrator's report warns that the pre-existing dirt will ride into
      the human's commit

  # ADD - orchestrator-06: the latch's stop list and the Report Format's
  # stopped enumeration name the new machine-line stops; the advisory line is
  # not a stop.
  Scenario: orchestrator-06
    When the reader reads the Session guards' latch bullet and the Report
      Format's stopped definition
    Then the latch's flow-script machine-line stops include
      "state=tree_dirty" and "state=bad_slug"
    And the Report Format's stopped enumeration includes
      "state=tree_dirty" and "state=bad_slug", each as the hard state stop
      variant reported "status=stopped" (not "waiting-user"), each naming its
      resume action
    And "dirty=yes" is documented as advisory only — not a latch outcome, not
      a stop, and never a change of routing
    And the numbered steps still end at 6, no new fenced block was added
      (still 14 fence lines across 7 blocks, exactly one ```sh fence), the
      four tables survive, and the dedup guard's exactly-two exceptions are
      untouched
