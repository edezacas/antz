# Change: style-rewrite — sub-spec 07 of 07 (the patch bump).
#
# The versioning half of Cambio D: VERSION 4.7.0 → 4.7.1 (patch — a style-only
# rewrite with semantics intact) and the matching dated CHANGELOG.md entry in
# the same change, per AGENTS.md's Versioning rule (any commit touching
# agents/prompts/ bumps VERSION and adds the entry). The suite follows the
# recorded bump-suite pattern (tests/bump470_test.sh and its predecessors):
# VERSION is asserted by agreement with the newest topmost entry, never as a
# cross-change literal; the entry is pinned by content greps scoped to the
# [4.7.1] section alone; and the install.sh-untouched / no-tag guards are
# gated on the change_pending pattern from birth.
#
# Verified no-break in the existing bump suites (no edits needed):
# tests/bump440_test.sh, bump450, bump460, bump470, skills-activation-bump,
# and skills-desc-match-bump all assert by agreement and relative ordering,
# and their change_pending gates enforce harmlessly while this change is
# uncommitted (this change does not touch install.sh). Stacking [4.7.1] above
# [4.7.0] is the legitimate growth bump470's own header already planned for.
#
# Declared destination domain: versioning.

Feature: the style rewrite ships as patch 4.7.1

  Background:
    Given the style-rewrite prose edits of sub-specs 01-06 complete in the
      working tree, uncommitted (no role ever commits)
    And VERSION reading 4.7.0 and CHANGELOG.md's newest entry being
      "## [4.7.0] - 2026-09-13"
    And the repo's bump-suite pattern: agreement-based version assertions, a
      section-scoped entry extract, byte-stable older-entry tails, and
      change_pending-gated working-vs-HEAD guards with loud retirement notes

  # ADD - bump471-01: the bump is present — VERSION agrees with the newest
  # topmost entry, the dated [4.7.1] section sits above [4.7.0] describing
  # the style rewrite, and every older entry is byte-untouched.
  Scenario: bump471-01
    When tests/bump471_test.sh (new, modeled on tests/bump470_test.sh) runs
    Then VERSION is a semver agreeing with the newest (topmost) CHANGELOG
      entry — together pinning "VERSION reads exactly 4.7.1" today — with
      one trailing newline as the file's only content
    And CHANGELOG.md carries exactly one dated "## [4.7.1] - <date>" heading
      sitting above "## [4.7.0]", in the file's entry style (a "### Changed"
      category heading), keeping the Keep-a-Changelog preamble
    And the [4.7.1] section (scoped to that heading alone) describes the
      change, greppable in the entry: the mirror clause stated once per
      prompt; the four long sentences broken into short lists (the coder's
      closing-block bullet folded into "## Receipt", the orchestrator's
      rejected_count=1 row, the dedup guard, the verifier's REJECTED.md
      entry); the specifier's triple negation replaced by the two-line
      table rule; the terminology unified (`<slug>`, one form per concept);
      and the Working-Root triplication documented as an editing rule
    And the entry states the grade and its justification: patch — wording
      only, no behavior change; not minor (no capability, rendered-surface,
      or detection change) and not major (the workflow contract, the
      machine-line formats, the closing-block vocabularies, and the
      latch/dedup contracts are unchanged; agents/meta/* and install.sh are
      byte-untouched)
    And every entry from [4.7.0] down is byte-for-byte unchanged versus git
      HEAD (older entries are immutable history)

  # ADD - bump471-02: the working-vs-HEAD guards are born gated, and the
  # no-commit law holds.
  Scenario: bump471-02
    When the flow's work sits uncommitted on the change's marker branch
    Then the suite's install.sh-untouched and no-v4.7.1-tag checks are gated
      on the change_pending predicate (the working tree differs from HEAD on
      CHANGELOG.md/VERSION and HEAD does not yet carry the [4.7.1] entry) —
      enforced while the bump is pending, retired vacuously with a loud note
      once the human's bump commit lands, never resurrecting against a later
      legitimate bump
    And the suite never commits, never tags, and never mutates the working
      tree
    And the suite exits 0 in both the pending and the committed state

### Invariants
- VERSION is never pinned as a cross-change literal: the agreement with the
  newest topmost entry is the durable assertion (the recorded docs-bump
  lesson).
- The [4.7.1] entry's content greps are scoped to the [4.7.1] section alone,
  so a stray phrase in an older entry can never satisfy them.
- Every new working-vs-HEAD window is born gated on the change_pending
  pattern (stacking-robust by construction).
- The grade is patch: agents/prompts/ wording only — no capability, rendered
  surface, contract, or detection change; agents/meta/* and install.sh are
  byte-unchanged across the whole change.

## Out of scope
- Creating the v4.7.1 tag: the local tag is the human's commit-time
  follow-up, never a role's action.
- Any edits to tests/bump440_test.sh through bump470, skills-activation-bump,
  or skills-desc-match-bump (verified no-break; they assert by agreement and
  relative ordering).
