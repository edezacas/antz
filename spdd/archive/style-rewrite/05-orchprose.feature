# Change: style-rewrite — sub-spec 05 of 07 (the orchestrator's two
# 100-130-word blocks become short lists).
#
# Implements the orchestrator-side half of Cambio D (docs/plan-revision-2026-09.md
# §3): step 4's `rejected_count=1` table row and the Session guards' dedup
# bullet in agents/prompts/orchestrator.prompt are each broken into a short
# list. Every contract is unchanged — the relay/retry/stop semantics, the
# exactly-two-exceptions enumeration, the no-ledger mechanism, the latch, the
# machine-line formats, and the four-table structure. The rewrite preserves
# every phrase the existing suites pin (tests/antz-flow_test.sh's flow-06 and
# orchestrator-06 structural pins, tests/orchestrator-sessionguards_test.sh's
# sessionguards-01/03/04 pins, tests/receipts_test.sh's receipts-09 pins), so
# those suites pass unmodified; this sub-spec adds its own shape pins.
#
# Declared destination domain: flow-branch.

Feature: the orchestrator's rejection routing and dedup law read as short lists

  Background:
    Given "agents/prompts/orchestrator.prompt" whose step 4 routes on
      rejected_count with a three-row table whose `rejected_count=1` row is a
      single 100-130-word cell, and whose Session guards' "**Dedup.**" bullet
      is a single 100-130-word sentence enumerating the two exceptions in
      nested parentheses
    And the structural pins that must survive: steps end at 6 with no step 7,
      exactly 14 fence lines with one ```sh fence, the four table headers
      ("| discover output | Meaning / action |", "| Output | Meaning |",
      "| `rejected_count` | Action |", "| release output | Meaning / action
      |"), and the Session guards block sitting between its bold heading and
      "## Report Format"

  # MODIFY - orchprose-01: the rejected_count=1 row becomes a short cell plus
  # a bullet list under the table, with the same routing.
  Scenario: orchprose-01
    When the `rejected_count=1` row's cell is shortened and the relay detail
      moves to a short bullet list directly under the step-4 table
    Then the row still reads as a routing instruction: read REJECTED.md's one
      entry from disk (from the working root, never from conversational
      memory) and relay each attributable blocker per the rules below
    And the list carries, one item each, the same three outcomes with the
      same meaning: relay each attributable blocker to the `coder` session
      for the sub-spec it names, unconditionally (a repeat relay just no-ops
      in `coder`, while an unrelayed one can burn the retry); with no
      non-attributable blocker in that entry, delegate the whole change to
      `verifier` once more, the one bounded retry, orchestrated; with any
      non-attributable blocker (not traceable to a single sub-spec —
      cross-feature coherence, an e2e QA step), stop and report instead,
      naming the resume action explicitly (the user resolves it, themselves
      or via a new `specifier` round, then invokes `verifier` directly — that
      manual pass is the bounded retry, never delegated by the orchestrator)
    And the rows for rejected_count=0 and rejected_count=2 are unchanged
    And the structure pins hold: still exactly four tables, 14 fence lines,
      one ```sh fence, steps ending at 6, and no new fenced block

  # MODIFY - orchprose-02: the dedup guard becomes a lead sentence plus a
  # short list, preserving every pinned phrase.
  Scenario: orchprose-02
    When the "**Dedup.**" bullet is rewritten as a lead sentence plus a short
      list inside the Session guards block
    Then the lead keeps the law and its mechanism: "Within one invocation",
      "the same (sub-spec, role) pair is never delegated twice", "once a
      pair has been delegated", "route by the existing state machine",
      "fresh classification from disk", "never by re-delegating that pair",
      "own account of the delegations it has already made", "nothing is
      written to disk", "a later orchestrator invocation starts with a clean
      slate", and "resume is a fresh session"
    And the list enumerates exactly two exceptions, both step 4's, one item
      each: "relaying each attributable blocker to the `coder` session for
      the sub-spec it names" with "at most one relay per pair per entry" and
      "a second entry stops the flow for good"; and "the one bounded
      whole-change `verifier` retry when a rejected entry holds only
      attributable blockers" with "bounded by `REJECTED.md`: the count
      reaching 2 stops the flow for good"
    And the close keeps "No third exception exists", "the specifier is never
      re-delegated within an invocation", and "persisting after the
      specifier delegation stops the session rather than re-delegating"
    And the guards' standing wording survives around the list: "prompt-level
      law", "regardless of what the tool grant technically allows",
      "never-delegate-outside-the-three-roles rule", "They add constraints
      only", and the string "single carve-out" stays absent
    And the "**Latch.**" bullet is byte-unchanged — the latch contract is not
      part of this rewrite

  # ADD - orchprose-03: the new shape pins live in the orchestrator-prose
  # suite, and the neighboring suites pass unmodified.
  Scenario: orchprose-03
    When tests/orchestrator-sessionguards_test.sh is extended in the same
      change with test functions named after this sub-spec's ids
      (orchprose-01, orchprose-02, orchprose-03) and runs
    Then the new pins assert the step-4 row-plus-list shape and the dedup
      lead-plus-list shape with the preserved phrases above, scoped to the
      step-4 and Session guards extracts
    And tests/antz-flow_test.sh passes unmodified (flow-06's dedup phrases,
      orchestrator-06's structural pins, and the four-table/fence/steps pins
      are all preserved by construction)
    And tests/receipts_test.sh passes unmodified (receipts-09's step-4
      strings — "without running the unit suite", "no \"final gate\"
      re-test", "the verifier's own e2e Integration Verification suite
      remains the independent gate" — live in the step-4 intro line, above
      the table, untouched)
    And tests/orchestrator-status-probe_test.sh passes unmodified (the probe
      script and its fence include marker are untouched)
    And every suite exits 0

### Invariants
- The dedup contract is unchanged: never delegate a (sub-spec, role) pair
  twice in one invocation; exactly two exceptions, both step 4's, each
  REJECTED.md-bounded; no third exception; per-invocation clean slate.
- The bounded-retry routing is unchanged: count 1 relays and retries once,
  non-attributable blockers stop, count 2 stops for good.
- The latch bullet, the machine-line formats (`rejected_count=`, `state=`,
  `gate=`, `class=`), the delegation-template lines, and the four-table
  structure are unchanged.
- agents/prompts/specifier.prompt, agents/prompts/coder.prompt,
  agents/prompts/verifier.prompt, agents/meta/*, install.sh, and
  scripts/orchestration/* are byte-unchanged by this sub-spec.

## Out of scope
- The latch's stop lists and the Report Format's stopped/waiting-user
  enumerations (pinned elsewhere; not 100-130-word sentences).
- The specifier's Report Format closing bullet and the orchestrator's
  Report Format closing bullet (the mirror clause is already stated once in
  each — nothing to dedup there).
