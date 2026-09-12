# Change: flow-script-guards — sub-spec 03 (version bump to 4.5.0)
#
# Plan item of docs/plan-revision-2026-09.md §3 "Cambio B" and its "Notes":
# "Bump minor a 4.5.0 + entrada en CHANGELOG.md". The bump is mandated because
# this change touches scripts/orchestration/antz-flow.sh and
# agents/prompts/orchestrator.prompt, whose rendered content install.sh
# embeds; the versioning rule requires VERSION and CHANGELOG.md to move in the
# same change, and the plan's sequence fixes B = 4.5.0.
#
# Layer: VERSION and CHANGELOG.md only. install.sh is not edited by this
# change; the new script/prompt content reaches installed copies through the
# normal `./install.sh --all` re-render (a re-run, not an edit). docs
# (AGENTS.md, CLAUDE.md, docs/) are out of this sub-spec's scope and need no
# bump.
#
# Grade: minor, per the versioning rule — this is a behavior change to the
# flow script and to the orchestrator's routing (the rendered agent bodies
# change), not a non-behavioral wording tweak (patch), and it changes no
# workflow contract, marker format, access model, directory layout, or
# install location (not major). The four flow subcommands, the probe's output
# vocabulary, the release machine lines, and the receipt grammar all survive.
#
# All scenarios are ADD against spdd/specs/versioning.md (the bump precedent
# is bump440-*, merged there from change fix-orchestrator-flow); no existing
# id in that domain is modified. No tag is created by any role: v4.5.0 is the
# human's commit-time follow-up.

Feature: the flow-script-guards change bumps VERSION to 4.5.0 with a matching CHANGELOG entry

  # ADD - bump450-01: VERSION reads exactly 4.5.0 and CHANGELOG.md gains the
  # matching dated [4.5.0] section above [4.4.0], with every earlier entry
  # byte-untouched.
  Scenario: bump450-01
    Given "VERSION" and "CHANGELOG.md" as merged for version 4.4.0
    When the bump lands
    Then "VERSION" reads exactly "4.5.0" — the version value with one trailing
      newline as its only content — and agrees with the newest topmost
      CHANGELOG entry
    And "CHANGELOG.md" gains a dated "## [4.5.0] - <date>" section above
      "## [4.4.0]", in the file's Keep a Changelog style (category headings
      with bold lead-in bullets)
    And the "## [4.4.0]" section and every entry below it are byte-for-byte
      unchanged

  # ADD - bump450-02: the [4.5.0] entry describes the change and states the
  # minor grade with its versioning-table justification.
  Scenario: bump450-02
    When the reader reads the "## [4.5.0]" section
    Then it describes the flow script's mechanical slug validation
      ("state=bad_slug", non-destructive), the new-flow tree guard
      ("state=tree_dirty" only when the change dir is absent and the marker
      branch would be newly created, skipped on resume), and the advisory
      "dirty=yes" resume line
    And it describes the orchestrator prompt wiring (the step-1 ensure
      instructions, the latch, and the Report Format now name the new states)
      and the rewritten/added flow-suite tests (including the scripts
      byte-unchanged guard re-scoped off antz-flow.sh)
    And it states the grade as minor, not patch and not major, naming the
      behavior change to the flow script and orchestrator routing (not the
      wording-only patch) and the surviving workflow contract, marker format,
      access model, directory layout, install locations, four subcommands,
      probe output vocabulary, release machine lines, and receipt grammar (not
      major)
    And it states that install.sh itself is untouched and the bump reaches
      installed copies only through the normal "./install.sh --all" re-render,
      and that no role creates the v4.5.0 tag (it is the human's commit-time
      follow-up)
