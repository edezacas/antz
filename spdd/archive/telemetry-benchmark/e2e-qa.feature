# Domain: e2e-qa — telemetry-benchmark
#
# End-to-end QA for the benchmark harness, expressed at the user-visible CLI
# level: running N repetitions, reading the report, forcing clients, baseline
# comparison. Scenarios benchqa-01..04 and benchqa-06 are fully executable
# (dry-run client, report mode). benchqa-05's real-client half is a
# live-session scenario judged by the mechanism it exercises, per the repo's
# established e2e convention (a role session cannot make a real LLM call's
# outcome deterministic) -- the verifier observes one real repetition live and
# judges the rest by the pinned contract.

  Background:
    Given a checkout of antz with this change applied
    And an isolated environment (sandboxed HOME and temp output paths) so QA
      never touches the real "~/.claude" or "~/.config/opencode" and never
      writes outside its temp space

# ADD - benchqa-01: the user's headline workflow -- run the benchmark with
# the dry-run client for 3 repetitions and read the report.
Scenario: benchqa-01
  When the user runs "sh bench/antz-bench.sh --client dryrun --repetitions 3
    --jsonl <temp>/results.jsonl"
  Then the exit status is 0
  And "<temp>/results.jsonl" holds exactly 3 lines, each a complete telemetry
    record (every schema field present, outcome "approved")
  And the printed report shows the dryrun group with n=3, an outcome
    distribution counting 3 approved, and statistics for wall_clock_ms,
    tokens_input, and cost_usd
  And each repetition left an auditable run dir under the results area

# ADD - benchqa-02: detection and forcing at the CLI level -- nothing
# detected is a loud refusal; --client dryrun works with no client installed.
Scenario: benchqa-02
  When the user runs the bench with a PATH stripped of client CLIs and no
    client config directories present
  Then the run refuses with a non-zero exit, the message names --client as
    the escape hatch, and no results file is written
  When the user then runs "sh bench/antz-bench.sh --client dryrun --jsonl
    <temp>/forced.jsonl" under the same stripped environment
  Then the exit status is 0, one record is written, and no real client was
    needed at any point

# ADD - benchqa-03: the baseline workflow -- compare this run against the
# previous run's JSONL and read the deltas.
Scenario: benchqa-03
  Given a first dry-run invocation wrote "<temp>/baseline.jsonl" (3
    repetitions)
  When the user runs a second dry-run invocation with the same flags plus
    "--baseline <temp>/baseline.jsonl", writing "<temp>/current.jsonl"
  Then the exit status is 0 and "<temp>/current.jsonl" holds 3 fresh records
  And the printed report contains a baseline comparison section showing the
    baseline mean and median beside the current ones with signed deltas for
    the dryrun group
  And the baseline file is byte-identical before and after the comparison

# ADD - benchqa-04: every outcome class is reachable and recordable through
# the dry-run client, including the harness kill.
Scenario Outline: benchqa-04
  When the user runs "sh bench/antz-bench.sh --client dryrun --dryrun-outcome
    <outcome> --timeout <deadline> --jsonl <temp>/o.jsonl"
  Then the exit status is 0
  And "<temp>/o.jsonl" holds exactly one record whose outcome is "<outcome>"
  And the run dir carries the matching evidence: the timeout marker and a
    non-null error_note for "timeout", the client's exit artifact for
    "error", the flow artifacts in the fixture repo for the artifact-based
    outcomes

  Examples:
    | outcome       | deadline |
    | approved      | 60       |
    | rejected      | 60       |
    | blocked       | 60       |
    | open-question | 60       |
    | error         | 60       |
    | timeout       | 2        |

# ADD - benchqa-05: a real client repetition measures the checkout under
# test end to end (live-session scenario; executed live by the verifier
# against one installed client, the rest judged by mechanism per the repo's
# e2e convention).
Scenario: benchqa-05
  When the user runs "sh bench/antz-bench.sh --client <client> --repetitions
    1 --model <model> --jsonl <temp>/real.jsonl" with a real installed client
  Then the exit status is 0 and "<temp>/real.jsonl" holds exactly one record
    with client "<client>", model_pinned "<model>", a non-null wall_clock_ms
    and session_id, a non-null outcome, and the run dir carries the client's
    raw stdout / stderr / exit artifacts
  And the measurement never wrote to the real "~/.claude" or
    "~/.config/opencode": the agents that ran came from the sandbox rendered
    from this checkout

# ADD - benchqa-06: the report works standalone on any previous run's JSONL,
# with no client and no fixture.
Scenario: benchqa-06
  Given a results JSONL from any earlier invocation
  When the user runs "sh bench/antz-bench.sh report --jsonl <temp>/old.jsonl"
    on a machine with no client CLIs
  Then the exit status is 0 and the printed report aggregates that file's
    records (per-client groups, statistics, outcome distribution)
  And no client was launched, no fixture materialized, and
    "<temp>/old.jsonl" is byte-identical before and after
