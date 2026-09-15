# Domain: bench-schema
# Change: telemetry-benchmark (sub-spec 2 of 6)
#
# Goal: one common telemetry schema -- the JSONL record -- that every client
# adapter normalizes into and every consumer (report, baseline) reads. A
# client-agnostic harness lives or dies on this contract: unavailable fields
# are explicitly null, never zero, never missing, so a comparison across
# clients, runs, and antz versions never mistakes "not reported" for
# "reported as nothing".

## Contract
- One JSON object per run, appended to the results JSONL. The field set is
  closed and pinned; field order is pinned for diff stability.
- Outcome is classified from disk artifacts in the materialized fixture repo
  (client-agnostic), with a pinned precedence, never from the client's
  conversational output.
- Runner-owned fields vs adapter-owned fields are disjoint: adapters report
  telemetry through the key=value collect contract (bench-adapter); the
  runner assembles the record, measures wall clock, classifies the outcome,
  and counts artifacts.

## Feature: the common telemetry record

  Background:
    Given the bench harness with the dry-run client selected
    And the schema's pinned field set, in pinned order: run_id, timestamp,
      client, antz_version, scenario, repetition, model_pinned, wall_clock_ms,
      outcome, verifier_rejections, subspecs_declared, subspecs_receipted,
      slug, exit_code, error_note, client_version, client_duration_ms,
      tokens_input, tokens_output, tokens_reasoning, tokens_cache_read,
      tokens_cache_write, cost_usd, turns, tool_calls, subagent_delegations,
      models_used, session_id

  # ADD - schema-01: one complete JSON object per run -- the field set is
  # closed, every field present exactly once, in the pinned order.
  Scenario: schema-01
    When the runner completes repetitions and appends records to the results
      JSONL file
    Then the file holds exactly one JSON object per line, one line per
      repetition
    And every line carries exactly the pinned field set -- every field once,
      none missing, no extra field -- in the pinned order
    And the line is valid JSON (each record parses standalone)

  # ADD - schema-02: metric semantics and the null/zero distinction.
  Scenario: schema-02
    When a record's fields are checked against the metric semantics
    Then "wall_clock_ms" is harness-measured, always present and >= 0 (never
      null), even for a timed-out or failed run
    And "client_duration_ms" is the client-reported duration or null when the
      client reports none
    And each of "tokens_input", "tokens_output", "tokens_reasoning",
      "tokens_cache_read", "tokens_cache_write", "cost_usd", "turns",
      "tool_calls", "subagent_delegations" is null when unavailable, and a
      non-null value is >= 0 -- a null is never emitted as 0 and a true 0 is
      never emitted as null
    And "models_used" is null, or the distinct client-reported model
      identifiers comma-joined
    And "slug" is null, or the observed change-dir slug(s) comma-joined when
      the flow created more than one

  # ADD - schema-03: the outcome vocabulary and its precedence, classified
  # from disk artifacts only.
  Scenario: schema-03
    When the runner classifies a repetition's outcome from the materialized
      fixture repo
    Then the outcome is one of: approved, rejected, blocked, open-question,
      timeout, error
    And classification is evaluated in this precedence order, first match
      wins (a "receipt" is an "NN-*.result" file in the change dir; the
      refusal is any change-dir artifact carrying a line-start "BLOCKED: "):
      | order | outcome       | disk evidence in the fixture repo                        |
      | 1     | approved      | any directory exists under "spdd/archive/"               |
      | 2     | blocked       | a receipt "result=blocked" line, or the refusal marker   |
      | 3     | rejected      | "REJECTED.md" exists in the change dir                   |
      | 4     | open-question | "OPEN_QUESTIONS.md" exists in the change dir             |
      | 5     | timeout       | the harness deadline fired and killed the client process |
      | 6     | error         | none of the above                                        |
    And no outcome ever derives from the client's textual output -- only from
      the repo's artifacts and the harness's own kill record

  # ADD - schema-04: the artifact counters are observations, never telemetry.
  Scenario: schema-04
    When a record's counters are checked against the fixture repo's artifacts
    Then "verifier_rejections" is the number of "## Rejection " headings in
      the change dir's "REJECTED.md", and 0 when that file is absent
    And "subspecs_declared" is the number of "NN-*.feature" files in the
      change dir, and 0 when there is no change dir
    And "subspecs_receipted" is the number of "NN-*.result" files in the
      change dir, and 0 when there is no change dir
    And each counter is a present integer >= 0 -- never null

  # ADD - schema-05: a failed run still yields a complete record -- the JSONL
  # is never missing a line and never carries a partial record.
  Scenario: schema-05
    When a repetition's client fails (non-zero exit, no usable telemetry, no
      flow artifacts)
    Then the repetition still appends exactly one record
    And that record's outcome is "error", its telemetry fields
      (client_duration_ms, tokens_*, cost_usd, turns, tool_calls,
      subagent_delegations, models_used, session_id) are null, its
      "exit_code" carries the client's exit code, and its "error_note" is
      non-null and states the brief reason
    And "error_note" is non-null exactly when the outcome is "error" or
      "timeout", and null otherwise

## Invariants
- Null beats zero: an unreported metric is null; a reported zero is zero. The
  distinction is load-bearing for cross-client comparison.
- Totals are never silently partial: if part of a run's usage cannot be
  attributed (see bench-clients), the affected totals are null, not a
  plausible-looking undercount.
- Outcome classification reads only the fixture repo's artifacts and the
  harness's own kill record -- never the client's prose.

## Out of scope
- Extending the field set for client-specific extras (a future change extends
  the schema; this one pins it closed).
- Any interpretation of the numbers beyond what the report domain defines.
