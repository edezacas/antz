# Change: orchestrator-fast-path — sub-spec 07 (end-to-end QA suite, verifier-owned)
#
# The e2e QA suite for the whole change. It operates at the real product
# UI: install.sh's own CLI, the repo's files as a user reads/runs them, and
# live agent sessions via /antz (live-session halves are judged by the
# mechanism they exercise, per the repo's established e2e convention; ids
# the coder cannot automate get explicit SKIP stubs). The coder never
# implements or runs this suite.

Feature: e2e — the user-visible workflow across extraction, render, guards, receipts, and bump

  Background:
    Given a local checkout of the antz repo with the change applied in its
      working tree (nothing committed, per the no-commit law)
    And clean, empty "~/.claude/agents", "~/.claude/commands",
      "~/.config/opencode/agents", and "~/.config/opencode/commands"
      directories (or a temp HOME standing in for them)

  # ADD - e2e-01: the render path is observable end-to-end: a fresh install
  # renders the orchestrator with the three scripts embedded, byte-equal to
  # the source files, and installs nothing beyond the pre-change set.
  Scenario: e2e-01
    When the user runs "./install.sh --all" from the checkout
    Then all installed files carry the "antz:generated version=4.3.0"
      marker in the unchanged format
    And both clients' installed "antz-orchestrator" bodies contain, at the
      three script fences, content byte-identical to the current
      "scripts/orchestration/antz-flow.sh", "antz-probe.sh", and
      "antz-skills.sh" files, with no "# antz-include:" line surviving
    And running the extracted flow script from the installed copy ("sh
      <tempfile> discover" inside the repo) prints the same machine lines
      as running "sh scripts/orchestration/antz-flow.sh discover" directly
    And no standalone script, CLI, hook, or plugin was installed anywhere
      beyond the four agents plus "/antz" and "/antz-set-model" per client

  # ADD - e2e-02: the scripts are runnable files now — the documented
  # affordance works straight from the source tree, and the unit suites
  # test the files.
  Scenario: e2e-02
    When the user runs the three script suites
      ("./tests/antz-flow_test.sh",
      "./tests/orchestrator-status-probe_test.sh",
      "./tests/orchestrator-skills-block_test.sh")
    Then all three pass, reading "scripts/orchestration/" files directly
    And inside any git repository, "sh scripts/orchestration/antz-flow.sh
      discover" prints the same "candidate=..." machine lines the prompt
      documents for the extracted temp-file invocation
    And "sh -n" passes for each of the three files

  # ADD - e2e-03: a live orchestrated flow produces receipts and mirrors
  # them in reports; the orchestrator classifies without running the unit
  # suite.
  Scenario: e2e-03
    Given the user runs "/antz" with a change request that yields at least
      one sub-spec
    When each coder session for a sub-spec finishes
    Then "spdd/changes/<flow slug>/NN-<feature>.result" exists, carrying a
      "test_command=" line and one "id=... result=..." line per declared
      scenario id
    And the coder session's report ends with the closing block
      ("status=" / "ids=" / "results=") whose tokens match the receipt
    And the orchestrator's own report closes with its block, its
      "results=" naming each sub-spec's done/blocked/in_progress
      classification derived from the receipts (stated as read from disk,
      not from running the unit suite)
    And when every sub-spec is done, the verifier is delegated with no
      orchestrator unit-suite run in between

  # ADD - e2e-04: the guards are observable in a live flow: a stopped
  # session stays stopped; a twice-rejected change is never retried again.
  Scenario: e2e-04
    Given the user runs "/antz" with a change whose sub-spec refuses with a
      "BLOCKED:" reason at the planning stage
    Then the flow stops with the "BLOCKED:" reason relayed, and the
      orchestrator's session makes no further delegation of any kind
      (report states the stop and the resume action)
    When (in a separate flow) the verifier rejects the change twice, each
      rejection appending its "## Rejection <n>" entry
    Then after the second entry the orchestrator stops for good, reporting
      both entries verbatim, with no third coder or verifier invocation in
      that session

  # ADD - e2e-05: the 4.3.0 bump is observable through install.sh's own CLI
  # affordances.
  Scenario: e2e-05
    Given the user's machine has the pre-change antz installed (marker
      version "4.2.1")
    When the user reads "VERSION" and the top of "CHANGELOG.md", then runs
      "./install.sh --check"
    Then "VERSION" reads "4.3.0", the top section is "[4.3.0] - <date>"
    And "--check" reports the installed-to-source drift for both detected
      clients and prints the "[4.3.0]" entry, writing nothing
    When the user runs "./install.sh --all"
    Then every installed file is stamped "antz:generated version=4.3.0",
      and a fresh "--check" reports "already up to date (antz 4.3.0)" for
      both clients

### Invariants
- The suite operates at the UI: install.sh's CLI, the repo's files, and
  live /antz sessions — no internal API calls (there are none); script
  invocations shown are the same temp-file/file affordances the prompts
  themselves document.
- Live-session halves (e2e-03, e2e-04) may be judged by the mechanism they
  exercise where a role cannot spawn a live client session, per the repo's
  established e2e convention; their ids still get explicit SKIP stubs in
  the coder's unit suite.

## Out of scope
- Any internal-API-level check (none exists in this repo).
- The worktree-branch sibling variant.

## Relevant files
- "install.sh" — the CLI affordance for e2e-01 and e2e-05.
- "scripts/orchestration/*" — the runnable-file affordance for e2e-02.
- "tests/*" — the suites e2e-02 runs.
- "spdd/changes/<flow slug>/" — the receipts and reports e2e-03/e2e-04
  observe.
