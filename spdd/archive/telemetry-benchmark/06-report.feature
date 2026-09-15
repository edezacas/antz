# Domain: bench-report
# Change: telemetry-benchmark (sub-spec 6 of 6)
#
# Goal: the aggregate report -- count, mean, median, min, max, p95 per metric,
# grouped per client, with outcome distribution and an optional baseline
# comparison -- computed from any conforming JSONL, standalone, without
# launching any client. The report is what turns runs into the cross-version /
# cross-client answer the change exists for.

## Contract
- "sh bench/antz-bench.sh report --jsonl <file> [--baseline <baseline.jsonl>]"
  computes aggregates and prints a human-readable report; it is the same
  report the run mode prints at the end of a run.
- Statistics are pinned (nearest-rank p95, standard median, arithmetic mean);
  nulls are excluded from statistics, and an all-null metric reports nulls --
  never fabricated zeros.
- Grouping is per client; each group names the distinct pinned models seen.

## Feature: the aggregate report and baseline comparison

  Background:
    Given a conforming JSONL file with known records: for the client
      "dryrun", five repetitions with wall_clock_ms of 100, 200, 300, 400,
      and 1000; tokens_input of 1000, 2000, 3000, 4000, 5000; cost_usd of
      0.01, 0.02, null, 0.04, 0.05; and outcomes approved (x3), error (x1),
      timeout (x1); plus one record for the client "stub" with wall_clock_ms
      500
    And the report mode is invoked standalone:
      "sh bench/antz-bench.sh report --jsonl <file>"

  # ADD - report-01: the report computes the pinned statistics per client,
  # excluding nulls and never crashing on them.
  Scenario: report-01
    When the report is generated
    Then it groups by client and prints, for each client group: the record
      count, the distinct model_pinned values seen, the outcome distribution
      (each outcome with its count), and for each report metric
      (wall_clock_ms, client_duration_ms, tokens_input, tokens_output,
      tokens_reasoning, tokens_cache_read, tokens_cache_write, cost_usd,
      turns, tool_calls, subagent_delegations) the statistics n, mean,
      median, min, max, p95
    And a metric whose values are all null in the group prints null
      statistics instead of zeros, and a metric with no values at all is
      reported as absent without failing the report
    And the report prints the total record count across groups

  # ADD - report-02: the statistic definitions are pinned and deterministic.
  Scenario: report-02
    When the report's dryrun group is checked against the known values
    Then wall_clock_ms reads exactly: n=5, mean=400, median=300, min=100,
      max=1000, p95=1000 (nearest rank: the ceil(0.95 * n)-th of the sorted
      values)
    And tokens_input reads exactly: n=5, mean=3000, median=3000, min=1000,
      max=5000, p95=5000
    And cost_usd reads exactly: n=4 (the null excluded), mean=0.03,
      median=0.03, min=0.01, max=0.05, p95=0.05 (sorted 0.01, 0.02, 0.04,
      0.05; the 4th value)
    And the stub group carries n=1 with wall_clock_ms mean=median=min=max=p95
      =500
    And the same input file always produces the same report text

  # ADD - report-03: baseline comparison prints signed deltas for metrics
  # present on both sides, and names gaps instead of inventing deltas.
  Scenario: report-03
    When the report is generated with --baseline naming a second conforming
      JSONL whose dryrun group has a different wall_clock_ms mean
    Then the report prints, for each client and metric present on both
      sides: the baseline mean and median beside the current ones, with a
      signed delta (current minus baseline, printed with its sign)
    And a client or metric that exists on only one side is reported as
      absent on the other side -- never as a zero or null delta
    And the baseline file is only ever read -- it is not rewritten, moved, or
      appended to

  # ADD - report-04: report mode is standalone -- no client, no fixture, no
  # sandbox, any conforming input.
  Scenario: report-04
    When the report mode runs on a machine with no client CLIs installed and
      no fixture materialized
    Then it exits 0, launches no client and no adapter, and writes nothing
      except its report output
    And it accepts any conforming JSONL regardless of which antz version,
      client mix, or repetition count produced it -- including a baseline
      file recorded on another machine

## Invariants
- The report reads only its --jsonl and --baseline inputs; it never writes
  either.
- Nulls are excluded, absent is absent: the report never converts a gap into
  a number.
- The report's metric list is the pinned closed set from the schema domain.

## Out of scope
- Charts, HTML, or machine-readable report output beyond the JSONL itself
  (the JSONL is the machine interface).
- Significance testing, variance, or any statistic beyond the pinned six.
- Auto-baselines (reading the previous run's file implicitly) -- comparison is
  always explicit via --baseline.
