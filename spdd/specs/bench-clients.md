# Domain: bench-clients

Real client adapters, sandbox/isolation, model pinning, subagent attribution.

## Contract
- Per repetition, one sandbox: fresh HOME / XDG_CONFIG_HOME / XDG_DATA_HOME /
  CLAUDE_CONFIG_DIR under temp space; the checkout under test is rendered
  into it with install.sh; credentials and provider config are copied in
  read-only (Claude: credential only; OpenCode: credential from the data
  dir plus provider config from the config dir); the client process runs
  under a minimal allowlist environment.
- Model pinning: the runner's --model value is forwarded to the client and
  recorded; the client-reported models actually used are recorded alongside.
- Attribution: telemetry totals cover the primary session and all delegated
  (subagent) sessions when the client's artifacts expose them; anything
  unattributable nulls the affected totals rather than undercounting.

## Feature: real client adapters, sandboxed measurement, and model pinning

  Background:
    Given the antz checkout under test staged for rendering
    And a recording stub client placed on PATH that logs its argv and
      environment and emits canned output
    And a fresh sandbox directory tree under temp space

  # ADD - clients-01: one sandbox per repetition; the client process sees a
  # minimal environment and can write nowhere else.
  Scenario: clients-01
    When the runner prepares one repetition's sandbox
    Then it creates fresh directories inside temp space for HOME,
      XDG_CONFIG_HOME, XDG_DATA_HOME, and CLAUDE_CONFIG_DIR
    And the client process runs under a minimal allowlist environment (PATH,
      HOME, TMPDIR, the sandbox variables, and the pinned-model variable) --
      no ANTHROPIC_*, CLAUDE_*, or OPENCODE_* variable from the invoking
      shell passes through
    And a canary file planted beside each sandbox root is untouched and no
      file appears outside the sandbox tree while the stub client runs

  # ADD - clients-02: the measured antz is the checkout under test, rendered
  # into the sandbox -- never the user's global install.
  Scenario: clients-02
    When the runner prepares the sandbox for a selected client
    Then it runs the staged checkout's install.sh for that client with the
      sandbox environment, so the sandbox's agents directory and scripts
      libdir are populated from the checkout
    And the installed specifier agent in the sandbox carries the checkout's
      VERSION in its antz:generated marker
    And the installed orchestrator body references the sandbox's libdir path
      (no "__ANTZ_SCRIPTS_DIR__" placeholder survives) -- so the flow the
      client runs is the checkout's flow

  # ADD - clients-03: credentials are copied read-only into the sandbox;
  # originals are never touched; absence is not fabricated.
  Scenario: clients-03
    When the runner prepares the sandbox with real client credentials present
      for a client
    Then the credential file (Claude: ".credentials.json" under the real
      config dir; OpenCode: "auth.json" under the real data dir) is copied
      into the matching sandbox location, and the original's bytes and
      location are unchanged afterwards
    And when the credential file is absent, the copy step is skipped, the run
      still proceeds, and the client's own failure surfaces as the record's
      error outcome -- no credential is ever fabricated

  # ADD - clients-04: the Claude adapter's invoke shape, pinned via a
  # recording stub.
  Scenario: clients-04
    When the Claude adapter invokes a repetition against the recording stub
    Then the stub's recorded argv carries: the print (headless) flag with the
      request text, the agent selection naming "antz-orchestrator", the
      single-result JSON output format, a permission auto-approval flag (the
      client's documented non-interactive mode), and --model exactly when a
      model is pinned
    And the stub runs with its working directory at the fixture repo and the
      sandbox environment from clients-01
    And the run dir afterwards holds the stub's stdout, stderr, and exit code
      under the pinned artifact names

  # ADD - clients-05: the Claude adapter's collect -- result JSON plus the
  # isolated transcript, with subagent attribution.
  Scenario: clients-05
    When the Claude adapter collects from a run dir holding a canned single-
      result JSON (usage, total_cost_usd, duration_ms, num_turns,
      session_id, modelUsage) and a canned session transcript whose sidechain
      entries carry additional token usage and tool_use blocks
    Then the telemetry keys report: tokens and cost covering the primary and
      the sidechain (delegated) usage the transcript exposes, turns from the
      result's turn count, client_duration_ms from the result's duration,
      session_id from the result, and models_used from the result's per-model
      usage keys
    And tool_calls counts the tool_use invocations across primary and
      sidechain transcript entries
    And with no transcript present, tool_calls is null and the token totals
      come from the result alone -- nothing crashes, nothing is invented

  # ADD - clients-06: the OpenCode adapter's invoke shape, pinned via a
  # recording stub.
  Scenario: clients-06
    When the OpenCode adapter invokes a repetition against the recording stub
    Then the stub's recorded argv carries: the run subcommand with the request
      text, the agent selection naming "antz-orchestrator", the JSON event
      output format, a permission auto-approval flag, and the model flag with
      the pinned model exactly when one is pinned
    And the stub runs with its working directory at the fixture repo and the
      sandbox environment from clients-01

  # ADD - clients-07: the OpenCode adapter's collect -- run events plus parent
  # and child session exports, with subagent attribution.
  Scenario: clients-07
    When the OpenCode adapter collects from a run dir holding canned JSON
      run events (carrying the session id) and the sandbox serves canned
      exports: a parent session whose task tool parts name two child session
      ids, and exports for both children
    Then the telemetry keys report: tokens and cost summed over the parent
      and both child exports, client_duration_ms from the parent export's
      time fields, models_used from the distinct exported model identifiers,
      session_id from the run events, tool_calls counting tool parts across
      parent and children, and subagent_delegations counting the task tool
      parts
    And when one child's export is unavailable, the affected token, cost, and
      tool_call totals are null (never a silently partial sum), while
      subagent_delegations still counts the observed task parts and
      models_used keeps the exports that succeeded

  # ADD - clients-08: model pinning is forwarded and recorded on both sides.
  Scenario: clients-08
    When a repetition runs with a pinned model value
    Then the record's model_pinned is that value and the stub client received
      it (clients-04 / clients-06)
    And when no model is pinned, model_pinned is null and no model flag is
      passed
    And models_used is null exactly when the client reported no models, and
      otherwise the distinct client-reported identifiers comma-joined

  # ADD - clientconfig-01: the OpenCode credential is sourced from the real
  # data dir -- a file at the pre-fix config-dir path is ignored.
  Scenario: clientconfig-01
    Given the runner home holds "auth.json" under its ".local/share/opencode"
      data dir and a decoy "auth.json" under ".config/opencode" (the pre-fix
      source path), with distinguishable bytes
    When the runner runs one forced OpenCode repetition (--client opencode)
    Then the sandbox the client ran in carried the credential at the
      sandbox's data-dir location with the data-dir file's bytes
    And no credential exists at the sandbox's config-dir location -- the
      decoy was never copied
    And both host files keep their bytes and locations after the run

  # ADD - clientconfig-02: the host's OpenCode provider config reaches the
  # sandbox read-only and byte-faithful.
  Scenario: clientconfig-02
    Given the runner home holds an "opencode.json" under its
      ".config/opencode" config dir declaring a custom provider
    When the runner runs one forced OpenCode repetition (--client opencode)
    Then the sandbox the client ran in carried that file at the sandbox's
      config-dir location with byte-identical content
    And the carried copy carries no write permission for the client
    And the host file keeps its bytes and location after the run

  # ADD - clientconfig-03: absent host files are skipped, never fabricated;
  # the run still completes and records.
  Scenario: clientconfig-03
    When the runner runs one forced OpenCode repetition (--client opencode)
      from the default runner home holding neither a credential nor a
      provider config
    Then the run exits 0 and the results JSONL holds exactly one record
    And the sandbox the client ran in carried neither file -- nothing was
      fabricated

  # ADD - clientconfig-04: the sourcing follows the real dirs -- an
  # XDG-relocated runner environment is honored.
  Scenario: clientconfig-04
    Given the runner's environment sets XDG_CONFIG_HOME and XDG_DATA_HOME to
      test dirs that hold the provider config and the credential under their
      "opencode" subdirectories
    When the runner runs one forced OpenCode repetition (--client opencode)
    Then the sandbox the client ran in carried both files with the bytes of
      the XDG-relocated sources
    And no file was copied from the HOME-default locations, which hold
      nothing
    And the sources keep their bytes and locations after the run

## Invariants
- The sandbox is the only writable world for the client process: the user's
  real config, data, and the antz checkout are never written by a measurement.
- The measured flow is the checkout under test's flow: agents and libdir come
  from the staged install, never from the machine's global antz.
- Telemetry totals cover the whole flow (primary + delegated sessions) when
  the client exposes them; partial coverage nulls the affected fields.
- Model is pinned or recorded -- a run without a recorded model is
  uninterpretable, so both sides of the contract are mandatory.
