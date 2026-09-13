# Change: style-rewrite — sub-spec 04 of 07 (the skills-mandate lines stop
# restating the mirror principle; the skills suite follows).
#
# Completes the mirror-clause dedup of Cambio D (docs/plan-revision-2026-09.md
# §3): the skills-mandate lines in coder.prompt's "## Output" and
# verifier.prompt's "## Report Format" each end with the same tail the
# closing-block bullet already states ("never an input to any routing state or
# count: any orchestrator re-routing decision is made from disk state, not
# from it") — one of the ~10 mirror-clause repetitions the plan counted. The
# tails are removed; the lines keep their mandatory-reporting rule; the
# principle stays stated once per prompt (at the closing-block mirror
# statement) and stays documented for the skills line in the governing docs
# gotcha, which is untouched. tests/skills-activation-prompts_test.sh's
# prompts-06 pins are re-scoped loudly, splitting the per-role halves so each
# role's pins match its own prompt's final shape.
#
# This sub-spec depends on sub-spec 02 (the coder's closing-block list already
# lives under "## Receipt") and sub-spec 03 (the verifier's tail removal is
# the last edit to that line's neighborhood). It retires the intermediate red
# both documented.
#
# Declared destination domain: skills-activation.

Feature: each skills-mandate line is mandatory-reporting only; the mirror principle is stated once per prompt

  Background:
    Given "agents/prompts/coder.prompt"'s "## Output" skills bullet and
      "agents/prompts/verifier.prompt"'s "## Report Format" skills bullet,
      each ending "...and never an input to any routing state or count: any
      orchestrator re-routing decision is made from disk state, not from it."
    And tests/skills-activation-prompts_test.sh's prompts-06 test requiring
      "never an input to any routing state or count" and "disk state" inside
      both roles' report-section extracts — the pins that went red with
      sub-specs 02 and 03
    And AGENTS.md and CLAUDE.md carrying the skills-activation gotcha whose
      last sentence states the transparency-line principle ("a transparency
      line only, never a routing input") — pinned by
      tests/skills-activation-docs_test.sh and untouched by this sub-spec

  # MODIFY - skillsline-01: the coder's skills bullet keeps the
  # mandatory-reporting rule and drops the duplicated mirror tail.
  Scenario: skillsline-01
    When the coder's skills bullet is reworded
    Then it still states that the report says which skills were activated (by
      name) or that none matched — a mandatory line, never silently omitted
    And it no longer ends with the mirror tail: the strings "never an input
      to any routing state or count" and "any orchestrator re-routing
      decision is made from disk state" no longer appear in the "## Output"
      section

  # MODIFY - skillsline-02: the verifier's skills bullet gets the same edit.
  Scenario: skillsline-02
    When the verifier's skills bullet is reworded
    Then it still states that the report says which skills were activated (by
      name) or that none matched — a mandatory line, never silently omitted
    And it no longer ends with the mirror tail: the strings "never an input
      to any routing state or count" and "any orchestrator re-routing
      decision is made from disk state" no longer appear in the "## Report
      Format" skills bullet

  # ADD - skillsline-03: the mirror principle is now stated exactly once per
  # prompt, at the closing-block mirror statement.
  Scenario: skillsline-03
    When each of the four prompts is read whole
    Then the string "never an input to any routing state or count" appears
      exactly once in each of specifier.prompt, coder.prompt,
      verifier.prompt, and orchestrator.prompt
    And the string "disk state" appears exactly once in coder.prompt and
      verifier.prompt
    And in coder.prompt and verifier.prompt the single occurrence lives in
      the closing-block mirror statement, not in a skills bullet

  # MODIFY - skillsline-04: the skills suite follows, loudly and per role.
  Scenario: skillsline-04
    When tests/skills-activation-prompts_test.sh is updated in the same
      change and runs
    Then prompts-06's single test is split into per-role halves (coder and
      verifier), each named with its scenario id so a failure maps back
    And each half keeps, in its role's report-section extract, the
      mandatory-line pins ("skills were activated", "by name", "none
      matched", "never silently omitted") and moves the not-a-routing-input
      pins to whole-prompt single-occurrence counts of "never an input to any
      routing state or count" and "disk state" per skillsline-03
    And the suite's other tests — the additive-only windows (self-retiring
      against the changed prompts), prompts-01..05 and prompts-07's
      Skills-section pins — pass unmodified
    And tests/skills-activation-docs_test.sh passes unmodified: the docs
      gotcha's "a transparency line only, never a routing input" sentence
      stays, so the skills line's principle remains documented even though
      the prompt states it once
    And both suites exit 0

### Invariants
- The skills-mandate semantics are intact: activation is still reported by
  name or as none matched, mandatorily, never silently omitted.
- The mirror principle's once-per-prompt statement absorbs the tails' meaning:
  no role's conversational output — the block or the skills line — is a
  routing input; the docs gotcha keeps saying so for the skills line.
- The closing-block vocabularies, the delegation skills block, and every
  machine-line format are unchanged.
- agents/prompts/specifier.prompt, agents/prompts/orchestrator.prompt,
  agents/meta/*, install.sh, and scripts/orchestration/* are byte-unchanged
  by this sub-spec.

## Out of scope
- The docs gotcha bullets (AGENTS.md/CLAUDE.md) — byte-unchanged here; the
  only docs edit in this change is sub-spec 06's additive editing-rule bullet.
- The closing-block mirror statements themselves (sub-spec 02's shape, already
  landed).
