# Change: style-rewrite — sub-spec 03 of 07 (the verifier's REJECTED.md
# entry sentence becomes a short list).
#
# Implements the verifier-side half of Cambio D (docs/plan-revision-2026-09.md
# §3): the 100-130-word "On Rejection" sentence in
# agents/prompts/verifier.prompt — one run-on sentence with nested
# parentheticals describing the REJECTED.md entry mechanics — is broken into a
# short list. The rejection contract is unchanged: the literal `## Rejection
# <n>` heading, the append-never-overwrite rule, the via-Bash mechanism, and
# the per-blocker attribution duty all survive verbatim in meaning. No suite
# pins this sentence today (verified), so the sub-spec adds its own pins.
#
# Known intermediate red: after this sub-spec lands,
# tests/skills-activation-prompts_test.sh's prompts-06 verifier-half pins fail
# until sub-spec 04 re-scopes them (same documented mid-change state as
# sub-spec 02's).
#
# Declared destination domain: role-surfaces.

Feature: the verifier's rejection-entry duty is a short list with the same contract

  Background:
    Given "agents/prompts/verifier.prompt" whose "## On Rejection" section
      opens with a single 100-130-word sentence covering, in nested
      parentheses: appending (never overwriting) one entry to
      "spdd/changes/<change-slug>/REJECTED.md" via Bash, the exact literal
      "## Rejection <n>" heading the orchestrator's probe counts, and the
      reported-blockers content
    And no test suite pinning that sentence's strings today (verified:
      tests/roles_test.sh, tests/rolechecks_test.sh, and
      tests/orchestrator-sessionguards_test.sh pin other verifier prose)

  # MODIFY - verifier-01: the rejection-entry sentence becomes a short list
  # carrying the same contract.
  Scenario: verifier-01
    When the "## On Rejection" opening bullet is rewritten as a lead line
      plus a short list
    Then the lead line states the duty: before reporting, append (never
      overwrite) one entry to the change's REJECTED.md, via Bash
    And the list carries, one item each: the entry's heading line reading
      exactly "## Rejection <n>" and nothing else (`<n>` = 1 for the first
      entry, incrementing by one per further entry); the reason it must be
      literal (the orchestrator's probe script counts this exact heading, not
      just numbered in spirit); and the content that follows the heading (the
      reported blockers — severity, evidence, offending scenario — the same
      content already in the Report Format)
    And the section's second bullet (naming the sub-spec each blocker traces
      to, or stating that it doesn't trace to a single sub-spec) is
      unchanged
    And no item carries nested parentheticals deeper than one level — the
      single 100-130-word sentence is gone

  # ADD - verifier-02: the new pins live with the verifier-suite home and the
  # rejection contract stays machine-countable.
  Scenario: verifier-02
    When tests/roles_test.sh is extended in the same change with test
      functions named after this sub-spec's ids (verifier-01 and
      verifier-02) and runs
    Then the new pins require the lead-line duty, the exact-heading item, the
      probe-counts reason, and the blockers-content item inside the
      "## On Rejection" extract, and refuse the old run-on sentence's
      nesting shape (the strings "and nothing else (`<n>` = 1 for the first
      entry in the file, incrementing by one per further entry) — the
      orchestrator's probe script counts this exact heading, so it must be
      literal, not just numbered in spirit. Put the reported blockers" no
      longer appear as one line)
    And tests/orchestrator-status-probe_test.sh passes unmodified — the
      probe's "## Rejection <n>" counting is script behavior, untouched by
      this prose rewrite
    And the extended suite exits 0

### Invariants
- The rejection contract is unchanged: one entry per rejection, appended
  never overwritten, headed by the literal machine-countable
  "## Rejection <n>" line, blockers on the following lines, per-blocker
  attribution (sub-spec trace or explicit non-attribution).
- The closing-block bullet in the verifier's "## Report Format" section is
  unchanged by this sub-spec (its mirror clause is already stated once; the
  skills-line tail is sub-spec 04's edit).
- agents/prompts/specifier.prompt, agents/prompts/coder.prompt,
  agents/prompts/orchestrator.prompt, agents/meta/*, install.sh, and
  scripts/orchestration/* are byte-unchanged by this sub-spec.

## Out of scope
- The skills-line tail removal and the skills-suite re-scope (sub-spec 04).
- The orchestrator's rejection routing (step 4's table and the dedup guard —
  sub-spec 05): the verifier-side authoring format and the orchestrator-side
  counting/routing are independent surfaces.
