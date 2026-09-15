# Domain: bench-runner

The runner CLI: modes, flags, detection/forcing, repetition loop, outputs,
exit contract, hermetic-suite law.

## Contract
- Two modes: the default run mode (repetitions + report) and the standalone
  "report" mode (bench-report). The runner never spawns a client in report
  mode.
- Client selection mirrors install.sh's detection predicate, evaluated against
  the real host; --client forces one client past detection. The dry-run client
  is selectable only explicitly.
- Exit code 0 means "every repetition produced a record"; outcome values are
  data, not failures. Non-zero exits are harness-internal failures.

## Feature: the benchmark runner CLI

  Background:
    Given the bench tree with "bench/antz-bench.sh" runnable via "sh
      bench/antz-bench.sh"
    And the fixture, the adapters, and the record schema as specced

  # ADD - runner-01: the CLI surface is documented on -h and refuses unknown
  # flags.
  Scenario: runner-01
    When the runner is invoked with -h (and again with --help)
    Then the usage text documents both modes (default run mode and "report"),
      every flag (--client, --repetitions, --model, --timeout, --baseline,
      --jsonl, --dryrun-outcome), their defaults, and the exit contract
    And an invocation with an unknown flag prints the usage to stderr and
      exits non-zero

  # ADD - runner-02: client selection mirrors install.sh's predicate;
  # forcing bypasses detection; no client is a loud refusal.
  Scenario: runner-02
    Given the detection predicate: a client is detected when its CLI is on
      PATH or its global config directory exists (Claude: "claude" on PATH or
      "~/.claude"; OpenCode: "opencode" on PATH or "~/.config/opencode"),
      evaluated against the real host environment, independent of any sandbox
    When the runner runs with no --client on a host where both clients are
      detected (stub CLIs on PATH)
    Then every detected client runs the full repetition count, and the dry-run
      client runs for none of them
    And with --client <name>, exactly that client runs -- even when detection
      would not select it (the forcing contract)
    And with no --client on a host where nothing is detected, the runner
      refuses loudly (naming --client as the escape hatch), exits non-zero,
      and writes no records

  # ADD - runner-03: N sequential repetitions, each fully isolated, errors
  # never abort the loop.
  Scenario: runner-03
    When the runner runs <n> repetitions for a client
    Then the repetitions run sequentially, each with a freshly materialized
      fixture repo and a freshly prepared sandbox
    And each repetition appends exactly one record to the results JSONL, in
      run order, with "repetition" counting from 1
    And a repetition that errors or times out appends its record and the
      remaining repetitions still run

  # ADD - runner-04: outputs and exit contract.
  Scenario: runner-04
    When the runner completes a run mode invocation
    Then the records are written to the --jsonl path, defaulting to a fresh
      "bench/results/bench-<UTC timestamp>.jsonl" (the results directory
      created on demand)
    And the aggregate report is printed to stdout at the end of the run
    And the runner exits 0 exactly when every repetition produced a record --
      a run whose repetitions all ended in outcome "error" or "timeout" still
      exits 0, because the outcomes are measurements
    And a harness-internal failure (a forced client whose adapter does not
      detect as usable; an unmaterializable fixture; an unwritable output
      path) exits non-zero before any record is written

  # ADD - runner-05: every repetition leaves an auditable run dir.
  Scenario: runner-05
    When the runner completes a run mode invocation of at least two
      repetitions
    Then each repetition has left a run dir under the results area holding at
      least the recorded request copy, the client's raw stdout / stderr /
      exit artifacts, the collect keys, and the timeout marker when the
      deadline fired
    And the run dirs are disjoint across repetitions and across separate
      invocations, and each record identifies its repetition

  # ADD - runner-06: the real bench never runs under the test suite -- the
  # owning suite stays hermetic via the dry-run client and report mode.
  Scenario: runner-06
    When "sh tests/run_all.sh" executes on a machine with no client CLIs and
      no credentials
    Then the bench's owning suite ("tests/bench-harness_test.sh") is picked up
      by the runner's mechanical tests/*_test.sh glob with no runner edit,
      and passes
    And the owning suite exercises only the dry-run client and report mode --
      it launches no real client, touches no network, and reads no real
      credential
    And no test in the suite invokes the bench's real-client path (no
      adapter-claude.sh / adapter-opencode.sh invocation against anything but
      recording stubs)

## Invariants
- One repetition = one fixture repo = one sandbox = one record; nothing is
  shared between repetitions.
- The runner measures wall clock itself; client-reported durations are
  recorded alongside, never substituted for the harness's own clock.
- Detection mirrors install.sh's predicate verbatim; the bench never installs
  into, reads from, or writes to the real client config for measurement
  purposes.
