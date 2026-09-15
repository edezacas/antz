# Domain: bench-clients
# Change: bench-opencode-provider-config (sub-spec 1 of 1)
#
# Goal: the benchmark can measure OpenCode models whose provider is declared
# in the host's "opencode.json" -- not only models whose key lives in
# "auth.json" -- and the OpenCode credential reaches the sandbox from the
# path the client actually reads. Everything here is verified against real
# client behavior (opencode v1.18.31 on this host):
#
# - OpenCode reads credentials from its data dir,
#   "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json", and provider
#   config from "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json";
#   both roots relocate with XDG_DATA_HOME / XDG_CONFIG_HOME (verified via
#   "opencode debug paths" with and without the XDG vars set).
# - A custom provider ("nan", npm "@ai-sdk/openai-compatible" with a baseURL
#   and a models list) is declared in "opencode.json" only -- it is not in
#   "auth.json". Without that file in the sandbox OpenCode cannot resolve the
#   model and every repetition ends "outcome=error" (reproduced: an empty
#   sandbox errors on "nan/deepseek-v4-flash"; the same sandbox with
#   "opencode.json" copied in answers with a proper step_finish and tokens).
# - The runner's call site drifted: "bench/antz-bench.sh" copies "auth.json"
#   from the config dir, while clients-03 and its owning test
#   (tests/bench-harness_test.sh test_clients_03) already pin the data dir.
#   Even "opencode-go/*" (key in "auth.json") cannot authenticate in the
#   sandbox today.
# - install.sh never writes "opencode.json" (verified: no match), so a carry
#   that lands after the render cannot collide with the render's backup rules.
# - "bench_sandbox_copy_credentials" (bench/lib.sh) already implements the
#   discipline the carry needs -- copy when the source exists, skip when it
#   does not, make the destination read-only, never touch the source -- so
#   the carry reuses that discipline verbatim; no new helper semantics.

## Contract
- Per repetition, the OpenCode preparation copies TWO host files read-only
  into the sandbox's matching locations, mirroring the existing credential
  discipline (source bytes and location never touched; absence skipped rather
  than fabricated; the sandbox copy made non-writable):
  the credential "auth.json" from the real data dir
  ("${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json") to the
  sandbox's data-dir location, and the provider config "opencode.json" from
  the real config dir ("${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json")
  to the sandbox's config-dir location. "Real" means where the host's client
  actually reads the file: the XDG-relocated root when the runner's
  environment sets it, the documented HOME default otherwise.
- The carry is always-on (no flag, no env var) and byte-faithful: the sandbox
  sees the host's file, not a curated subset. Rationale in the change README.
- The Claude path is unchanged: one credential copy from the real config dir.

## Feature: the host client files a measurement carries into the sandbox

  Background:
    Given the antz checkout under test staged with its bench tree
    And a controlled runner home carrying no client state by default
    And a recording stub OpenCode CLI on the runner's PATH that answers the
      adapter contract (--version, run, export) and, on each run invocation,
      records beside itself what it sees inside the sandbox: the existence,
      bytes, and writability of the OpenCode credential and provider-config
      paths under its relocated HOME, XDG_CONFIG_HOME, and XDG_DATA_HOME
    And the runner invoked through the isolated funnel with its environment
      pinned to the test world (its HOME is the runner home; its PATH
      carries no real client CLIs)

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
- The host's real client files are read-only to a measurement: every carry
  lands inside the sandbox and is made non-writable there; a measurement
  never writes the host's config or data.
- Absence is skipped, never fabricated: a host without a file yields a run
  without it, and the client's own failure surfaces as the record's error
  outcome.
- The carry is byte-faithful: no filtering, no rewriting, no fabrication of
  provider entries the host did not declare.
- No new CLI surface and no record-schema change: the carry is a preparation
  detail of each repetition's sandbox, not a measurement result.

## Out of scope
- Carrying anything beyond the single "opencode.json" (plugins, node_modules,
  package.json, tui.json, or "opencode.jsonc" config variants) -- the
  diagnosed need is the provider block; anything else stays invisible to the
  sandbox, exactly as today.
- A Claude-side config carry (settings.json and friends): Claude's credential
  path already works and no drift is diagnosed there.
- Gating the carry behind a flag or env var (decided always-on; rationale in
  the change README).
- Record fields or run-dir artifacts describing the carry (the credentials
  are not audited into run dirs either; the mirror stays exact).
- The client-detection predicate: it keeps matching the literal
  "$HOME/.config/opencode" / "$HOME/.claude" per bench-runner.
