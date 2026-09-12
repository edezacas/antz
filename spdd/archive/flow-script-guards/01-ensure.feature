# Change: flow-script-guards — sub-spec 01 (flow script: mechanical slug
# validation, the new-flow tree guard, the resume dirt advisory, and the
# tests that pin them)
#
# Plan items of docs/plan-revision-2026-09.md §3 "Cambio B — flow-script-guards"
# (minor), plus §2's "Guard de árbol (3.1)" decision and the second-review
# notes: validation mecánica de slug, `state=tree_dirty` only at new-flow
# start, the optional `dirty=yes` resume line, and the rewrite of the two
# existing tests that consecrate the old behavior.
#
# Layer: scripts/orchestration/antz-flow.sh (the `ensure` subcommand) plus the
# tests that pin it, tests/antz-flow_test.sh. The orchestrator prompt that
# consumes the new states is sub-spec 02; the VERSION/CHANGELOG bump is 03.
#
# Decisions settled by the delegation (recorded, not guessed):
#   - The tree guard fires only when BOTH the change dir
#     (spdd/changes/<slug>/) is absent AND the marker branch would be newly
#     created (it does not exist). A branch-only candidate that already has a
#     marker branch but never wrote a change dir is a reuse, not a new-flow
#     start: the guard is skipped for it.
#   - `state=bad_slug` (exit 1) is the validation rejection, used for the
#     empty/absent slug as well as any slug failing the mechanical rule; it
#     replaces the old `usage: ensure <slug>` arm. Validation runs before the
#     `state=no_commits` check and before any branch or positioning work.
#   - Slug rule: lowercase letters, digits, and hyphen only; no leading or
#     trailing hyphen; no double hyphen; length at most 40 characters (a
#     40-character slug is valid, 41 is not).
#   - `dirty=yes` is emitted immediately after any `state=reused` line when
#     `git status --porcelain` is non-empty (a change-dir resume or a
#     branch-only reuse). It is advisory only: it changes no routing and is
#     not a stop. A clean reuse still prints exactly `state=reused`.
#
# Edit-shape constraints from the existing suites (the coder must keep them
# green): the flow script keeps its header law verbatim enough that
# tests/antz-flow_test.sh ensure-04/06 still pass (no force/reset/clean/stash/
# restore/branch-delete; the one flagless `git switch "antz/$slug"`); the
# prompt's numbered steps still end at 6, exactly 14 fence lines (one ```sh),
# and the four tables survive (sub-spec 02's concern). ensure-01/03/04 and
# ensure-06..14 keep their fixtures and expectations valid: they all start or
# resume with a clean tree and no change dir, so the guard does not fire and
# no `dirty=yes` line appears.
#
# test-suite maintenance forced by this change: tests/antz-flow_test.sh's
# flow-09 scenario asserts that the whole of scripts/orchestration/ is
# byte-unchanged vs HEAD. This change modifies
# scripts/orchestration/antz-flow.sh, so that check must be re-scoped to the
# files this change leaves untouched (antz-probe.sh, antz-skills.sh); the
# probe/skills byte-unchanged assertion (require "$PROBE_SH" ...) and the
# structural constraints stay enforced. The pre-existing flow-09 id stays
# reported in the suite. Independently, tests/renderinject_test.sh's
# pre-change render byte-identity gate (keyed only on the prompt's prose) must
# be extended to retire when an injected orchestration script differs from the
# base tree, since a script-only sub-spec (this one, before sub-spec 02's
# prose edit) legitimately changes the rendered body; its reconstruction and
# structural assertions stay enforced.
#
# All ADD scenarios are new ids against spdd/specs/flow-branch.md's `ensure`
# feature; the two MODIFY scenarios amend existing ids there (ensure-02,
# ensure-05). The spec's one-line output vocabulary invariant is extended
# with state=bad_slug, state=tree_dirty, and the advisory dirty=yes line.

Feature: the flow script's ensure guards a new flow against an invalid slug and a dirty tree

  Background:
    Given "scripts/orchestration/antz-flow.sh" run from inside a git
      repository that has at least one commit, invoked as `ensure <slug>`
    And the repository's working tree, current branch, HEAD, and branch refs
      are the observable state

  # ADD - ensure-15: ensure rejects a mechanically invalid slug with
  # state=bad_slug and changes nothing.
  Scenario Outline: ensure-15
    Given a clean repository with no "antz/<slug>" branch and no
      "spdd/changes/<slug>/"
    When ensure runs with the slug "<slug>"
    Then stdout is exactly "state=bad_slug" with exit status 1
    And no "antz/..." branch was created
    And the session is still on its original branch
    And HEAD, every branch ref, and the working tree are byte-unchanged
    And no stash entry exists

    # "(empty)" in the table is the empty slug argument; the last row is 41
    # lowercase "a" characters (one past the 40-character bound).
    Examples:
      | slug reason | slug                                      |
      | empty       | (empty)                                   |
      | uppercase   | Bad-Upper                                 |
      | underscore  | under_score                               |
      | dot         | foo.bar                                   |
      | slash       | foo/bar                                   |
      | leading -   | -leading                                  |
      | trailing -  | trailing-                                |
      | double --   | double--hyphen                            |
      | 41 chars    | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa |

  # ADD - ensure-16: the length boundary — a slug of exactly 40 characters is
  # valid.
  Scenario: ensure-16
    Given a clean repository with no "antz/<slug>" branch and no
      "spdd/changes/<slug>/"
    When ensure runs with a 40-character slug of lowercase letters
    Then stdout is exactly "state=created" with exit status 0
    And the session is on branch "antz/<slug>"

  # MODIFY - ensure-02: a dirty tree at a new flow's start is rejected with
  # state=tree_dirty before any branch is created or checked out.
  Scenario: ensure-02
    Given a repository with at least one commit, the session on "master", no
      "antz/<slug>" branch, and no "spdd/changes/<slug>/"
    And an uncommitted modification to a tracked file
    When ensure runs with the slug
    Then stdout is exactly "state=tree_dirty" with exit status 1
    And no "antz/<slug>" branch was created
    And the session is still on "master"
    And HEAD, every branch ref, and the file's contents are byte-unchanged
    And no stash entry exists

  # ADD - ensure-17: non-empty git status --porcelain is the whole trigger —
  # an untracked, non-ignored file blocks a new flow the same way.
  Scenario: ensure-17
    Given a repository with at least one commit, the session on "master", no
      "antz/<slug>" branch, and no "spdd/changes/<slug>/"
    And an untracked, non-ignored file exists in the working tree
    When ensure runs with the slug
    Then stdout is exactly "state=tree_dirty" with exit status 1
    And no "antz/<slug>" branch was created
    And the session is still on "master"
    And the untracked file is untouched
    And no stash entry exists

  # MODIFY - ensure-05: the destructive-checkout refusal now lives on the
  # resume path, where the tree guard is skipped.
  Scenario: ensure-05
    Given the marker branch "antz/<slug>" exists at an earlier commit
    And "spdd/changes/<slug>/" exists (a resume, so the tree guard is skipped)
    And the current branch and "antz/<slug>" carry different committed
      contents for a tracked file, and the working tree holds a third,
      uncommitted content
    When ensure runs with the slug
    Then stdout is exactly "state=checkout_refused" with exit status 1
    And the working tree content, HEAD position, and every branch ref are
      identical before and after
    And the session did not move
    And nothing was forced, stashed, reset, or deleted

  # ADD - ensure-18: the guard is skipped on resume — a dirty tree still
  # positions, and the reuse reports the pre-existing dirt as an advisory
  # machine line.
  Scenario: ensure-18
    Given a repository with at least one commit, the session on "master", the
      marker branch "antz/<slug>" already exists, and
      "spdd/changes/<slug>/" already on disk
    And an uncommitted modification to a tracked file
    When ensure runs with the slug
    Then stdout is "state=reused" followed by "dirty=yes", with exit status 0
    And the session is on branch "antz/<slug>"
    And the file's modification is carried over untouched
    And no stash entry exists
    And the advisory is emitted on any non-empty-porcelain "state=reused",
      including a branch-only reuse whose change dir is still absent

  # ADD - ensure-19: the flow suite's scripts byte-unchanged guard excludes the
  # file this change modifies.
  Scenario: ensure-19
    Given tests/antz-flow_test.sh running the scripts/orchestration/ files
      directly against the working tree
    When the scripts byte-unchanged guard runs
    Then it compares only the files this change leaves untouched
      ("scripts/orchestration/antz-probe.sh" and
      "scripts/orchestration/antz-skills.sh") against HEAD
    And "scripts/orchestration/antz-flow.sh" being modified does not fail it
    And the probe's "change_dir=missing" assertion and every structural
      constraint of that scenario stay enforced

  # ADD - ensure-20: the render-injection suite's pre-change byte-identity gate
  # also retires when an injected orchestration script differs from the base
  # tree, so a script-only change does not fail it.
  Scenario: ensure-20
    Given tests/renderinject_test.sh rendering both clients' orchestrator
      bodies from the working tree and from the change's base tree
    And the base-render byte-identity gate currently keyed on the prompt's
      prose being unchanged vs the base
    When scripts/orchestration/antz-flow.sh differs from the base tree's
      copy
    Then the gate treats the pre-change render identity as legitimately
      superseded and retires it with a note instead of failing
    And the marker-substitution reconstruction, the no-marker-survives
      assertion, the fence shape, and the structural render assertions stay
      enforced
    And once the prompt prose of sub-spec 02 also changes, the gate retires
      for that reason too, with no double failure
