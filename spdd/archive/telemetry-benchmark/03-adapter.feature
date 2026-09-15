# Domain: bench-adapter
# Change: telemetry-benchmark (sub-spec 3 of 6)
#
# Goal: the client-agnostic adapter contract -- detect / invoke / collect --
# plus the offline dry-run client that lets the harness's plumbing, outcome
# classification, and reporting be exercised hermetically. The real
# (LLM-invoking) bench is never executed by the test suite; the dry-run
# client is the suite's instrument.

## Contract
- Every adapter is a POSIX sh file "bench/adapter-<client>.sh" defining the
  same three functions; the runner sources exactly one adapter per run.
- "bench_detect" says whether the client is usable; "bench_invoke" launches
  the client headless as the orchestrator against the fixture repo and leaves
  raw artifacts in the run dir; "bench_collect" normalizes the artifacts into
  the schema's telemetry keys, null where unavailable.
- The dry-run adapter ("bench/adapter-dryrun.sh") is a mock client: no
  network, no credentials, no real binary, deterministic artifacts and
  telemetry, scripted outcome.

## Feature: the adapter contract

  Background:
    Given the bench tree with adapters under "bench/"
    And the runner selecting a client by sourcing exactly one
      "bench/adapter-<client>.sh"

  # ADD - adapter-01: one contract, three functions, one sourced adapter.
  Scenario: adapter-01
    When each "bench/adapter-<client>.sh" file is inspected
    Then every adapter defines "bench_detect", "bench_invoke", and
      "bench_collect", and defines no function outside that contract's
      namespace
    And "bench_detect" exits 0 and prints a non-empty version string when the
      client is usable, and exits non-zero when it is not
    And the runner sources exactly one adapter file per run and calls only
      that adapter's three functions

  # ADD - adapter-02: invoke launches the client headless as the orchestrator
  # and leaves auditable raw artifacts; the harness can enforce the deadline.
  Scenario: adapter-02
    When the runner invokes the adapter for one repetition with the
      materialized fixture repo, the request file, and the run dir
    Then the client process runs with its working directory at the fixture
      repo, its prompt taken from the request file, and the antz-orchestrator
      as its entry point
    And the invocation is non-interactive by construction: no login,
      permission, or trust prompt can block it
    And the run dir afterwards holds the raw client artifacts: the client's
      stdout ("client.stdout"), stderr ("client.stderr"), and exit code
      ("client.exit")
    And the adapter runs the client in its foreground so the harness's
      deadline kill applies to it

  # ADD - adapter-03: collect normalizes artifacts into the pinned telemetry
  # keys and makes no model call of its own.
  Scenario: adapter-03
    When the runner calls "bench_collect" with the run dir and the fixture
      repo after the client process has exited
    Then collect prints exactly the pinned telemetry keys, one "key=value"
      line each: client_version, client_duration_ms, tokens_input,
      tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write,
      cost_usd, turns, tool_calls, subagent_delegations, models_used,
      session_id
    And a value that is unavailable is the literal "null"
    And collect launches no agent session and makes no model call; read-only
      queries over the run's own sandbox artifacts (for example a local
      session export) are allowed

  # ADD - adapter-04: the dry-run client scripts every outcome class by
  # materializing the matching flow artifacts.
  Scenario Outline: adapter-04
    When the dry-run client is invoked with the scripted outcome
      "<outcome>"
    Then the invocation completes quickly (well under a second of real work),
      with no network access and no real client binary involved
    And the materialized fixture repo afterwards carries exactly the flow
      artifacts that make the runner classify the outcome as "<outcome>"
    And the resulting record's outcome is "<outcome>"

    Examples:
      | outcome       |
      | approved      |
      | rejected      |
      | blocked       |
      | open-question |
      | error         |
      | timeout       |

  # ADD - adapter-05: the dry-run client is deterministic yet varies its
  # telemetry per repetition, so aggregate math has something to aggregate.
  Scenario: adapter-05
    When the dry-run client runs the same scripted outcome twice with
      different repetition numbers
    Then both runs materialize byte-identical flow artifacts in their
      respective fixture repos
    And both runs report the same outcome and the same telemetry keys, while
      the telemetry values differ deterministically with the repetition
      number (tokens and cost scale with it), so an aggregate over N
      repetitions is distinguishable from an aggregate over one
    And the dry-run adapter reports a fixed non-empty "client_version"

  # ADD - adapter-06: the dry-run timeout script exercises the harness kill.
  Scenario: adapter-06
    When the dry-run client is invoked with the scripted outcome "timeout"
      under a deadline of a few seconds
    Then the dry-run process stays alive past the deadline and the harness
      kills it, leaving the run dir's timeout marker
    And the resulting record's outcome is "timeout", with a non-null
      "error_note", wall_clock_ms at least the deadline, and null client
      telemetry

  # ADD - adapter-07: the dry-run error script exercises the failed-client
  # path end to end.
  Scenario: adapter-07
    When the dry-run client is invoked with the scripted outcome "error"
    Then the dry-run process exits non-zero, writes no flow artifacts, and
      emits no telemetry
    And the resulting record's outcome is "error" with null telemetry, a
      non-null exit_code, and a non-null error_note

  # ADD - adapter-08: the bench tree stays POSIX and interpreter-free -- awk,
  # sed, and grep are the only parsing aids.
  Scenario: adapter-08
    When every "bench/*.sh" file is parsed with "sh -n" and scanned for
      interpreter invocations
    Then every file parses cleanly under POSIX sh
    And no file invokes python, python3, jq, node, perl, ruby, or any other
      non-POSIX interpreter
    And awk, sed, grep, sort, and other standard utilities are the only text
      tools used

## Invariants
- The dry-run client is always "detected" (it is the harness's own code) and
  is never auto-detected as a real client; it is selected only by explicit
  flag.
- The dry-run client's scripted artifacts are shapes the outcome
  classification reads (change dir, receipts, REJECTED.md, OPEN_QUESTIONS.md,
  archive), not a byte-portrait of any real client's output.
- Adapters never write outside the run dir and the sandbox (bench-clients).

## Out of scope
- A persisted mock of any real client's wire format (the dry-run client mocks
  the flow's artifacts and telemetry, not the client CLIs' JSON dialects --
  the real adapters' collect paths are pinned against canned fixtures in
  bench-clients).
- Any scheduling, retry, or parallelism inside an adapter.
