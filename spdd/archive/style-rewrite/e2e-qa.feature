# Change: style-rewrite — end-to-end QA suite (one file per change dir — the
# archived practice, pinned at specifier.prompt level).
#
# Operates at the product's real UI: the artifacts a user can open and read
# (the installed agent bodies produced by install.sh's CLI, VERSION/
# CHANGELOG.md, AGENTS.md/CLAUDE.md, and the role prompt sources), plus
# install.sh's own CLI affordances (--all, --check). No internal API calls —
# there are none. The user-visible outcome of a style-only change is that the
# rewritten prose is what gets rendered and installed, the machine surfaces
# survive verbatim, and the version/docs surface tells the patch story.
#
# All three scenarios are fully runnable by the verifier during Integration
# Verification (no live agent sessions are required: a style change's behavior
# IS the text).

Feature: a user sees the style rewrite through the installed agents, the docs, and the 4.7.1 surface

  # ADD - e2e-style-01: installing renders the rewritten bodies with every
  # machine surface intact.
  Scenario: e2e-style-01
    Given the working tree carrying the style-rewrite edits, uncommitted
    When the user runs "./install.sh --all"
    Then each installed role body renders from the rewritten prompt without
      error, for both clients' agents directories
    And the installed antz-coder body carries the receipt duty under a
      "## Receipt" heading that also holds the closing-block list (the
      orphaned Output bullets are gone), and its report closes with the
      three-line grammar (status= / ids= / results=) stated once
    And the installed antz-specifier body states the Entities/Operations
      table rule in the two-line positive form, with no "you may optionally
      include" / "never mandatory" stacking
    And the installed antz-verifier body states the REJECTED.md entry duty as
      a short list headed by the literal "## Rejection <n>" rule
    And the installed antz-orchestrator body routes on rejected_count with
      the short `rejected_count=1` row and the relay bullet list, and the
      dedup law as a lead sentence plus a two-exception list
    And every installed body still carries the machine surfaces verbatim:
      "test_command=", "id=<feature>-<index> result=<green|skip|blocked>
      reason=", "state=", "gate=", "class=", "receipt=", "rejected_count=",
      and the closing-block vocabularies (done/blocked, approved/rejected,
      spec_complete, and the six flow statuses)
    And each installed body states the mirror clause exactly once

  # ADD - e2e-style-02: the version surface tells the patch story.
  Scenario: e2e-style-02
    Given the working tree carrying the style-rewrite edits, uncommitted
    When the user opens VERSION and CHANGELOG.md
    Then VERSION reads 4.7.1 and the topmost CHANGELOG entry is the dated
      "## [4.7.1]" section describing the style rewrite as patch — wording
      only, semantics intact — above the [4.7.0] entry
    And after "./install.sh --all", a subsequent "./install.sh --check"
      reports the installed copies up to date (the embedded version matches
      the source VERSION), with no files written by --check

  # ADD - e2e-style-03: the editing rule is visible where the user maintains
  # the prompts.
  Scenario: e2e-style-03
    Given the working tree carrying the style-rewrite edits, uncommitted
    When the user opens AGENTS.md and CLAUDE.md's Gotchas sections and the
      three role prompt sources
    Then both docs carry the identical gotcha bullet stating that the
      "## Working Root" section is triplicated across the specifier, coder,
      and verifier prompts on purpose (per-prompt autonomy) and that every
      future edit must touch all three sites
    And the three prompt files' "## Working Root" sections are byte-identical
      to each other, so the rule the docs state is true of the sources
    And the prompts use one spelling per concept — `sub-spec`, `<slug>`,
      `client`, `working root` — with no "change-slug" placeholder remaining
