# Change: orchestrator-fast-path — sub-spec 01 (build layer, no behavior change)
#
# The orchestrator prompt (agents/prompts/orchestrator.prompt) currently
# embeds three POSIX sh scripts verbatim inside fenced blocks, each uniformly
# indented by three spaces:
#   - antz-flow.sh  — the flow's git plumbing (the first 3-space bare fence,
#     carrying the "# antz-flow.sh" marker comment; tests/antz-flow_test.sh
#     extracts it mechanically)
#   - the status probe (the "```sh" fence; tests/orchestrator-status-probe_test.sh
#     extracts it mechanically)
#   - antz-skills.sh — the delegation skills-block derivation (carrying the
#     "# antz-skills.sh" marker comment; tests/orchestrator-skills-block_test.sh
#     extracts it marker-to-fence-close)
#
# This sub-spec moves the script bodies into real source files under
# scripts/orchestration/ and replaces each fenced body in the prompt with a
# single include marker that install.sh substitutes at render time (sub-spec
# 02). No behavior change: the files are byte-equal dedents of the current
# snippets, and the rendered orchestrator body stays byte-identical to the
# pre-change render (pinned by sub-spec 02).
#
# Shared contract with 02 (include markers): in agents/prompts/orchestrator.prompt,
# each of the three script fences' bodies is exactly one line of the form
#   # antz-include: scripts/orchestration/<name>.sh
# where <name> is antz-flow, antz-probe, or antz-skills. install.sh replaces
# each such line with the verbatim content of the named file when rendering
# the antz-orchestrator agent for either client, and never leaves a marker
# line in any rendered body.

Feature: scriptsource — the orchestrator's three embedded scripts become source files

  Background:
    Given "agents/prompts/orchestrator.prompt" embeds three POSIX sh scripts
      in fenced blocks (the antz-flow.sh flow script, the status probe, and
      antz-skills.sh), each fenced body uniformly indented by three spaces
    And no "scripts/" directory exists in the repo

  # ADD - scriptsource-01: the three source files exist, keep their script
  # header/usage comments, and parse as POSIX sh.
  Scenario: scriptsource-01
    When the repository is inspected after this sub-spec's implementation
    Then "scripts/orchestration/antz-flow.sh" exists
    And "scripts/orchestration/antz-probe.sh" exists
    And "scripts/orchestration/antz-skills.sh" exists
    And "sh -n" exits 0 for each of the three files
    And each file keeps the header comment its embedded counterpart carries
      in the prompt (the "# antz-flow.sh" / probe / "# antz-skills.sh" usage
      header, including its temp-file usage line "sh <tempfile> ...")

  # MODIFY - scriptsource-02: the files are byte-equal dedents of the current
  # fenced snippets (against the flow-branch invariant that the flow script
  # "stays the prompt's first 3-space-indented bare fence" and the
  # skills-activation invariant that antz-skills.sh "remains a
  # temp-file-executed POSIX sh snippet embedded in the prompt" — both
  # superseded by this move; the verifier merges those invariants
  # accordingly). Change-time verification, like descmatch-04: extracted
  # from the pre-change prompt and compared, not a permanent regression test.
  Scenario: scriptsource-02
    Given the pre-change orchestrator.prompt at the flow's base commit
    When each of its three fenced snippets is extracted and its uniform
      three-space indentation prefix removed
    Then each dedented snippet is byte-for-byte identical to the
      corresponding file under "scripts/orchestration/" (flow script ↔
      antz-flow.sh, "```sh" probe ↔ antz-probe.sh, skills snippet ↔
      antz-skills.sh)
    And the pre-existing script-level behavior suites pass unchanged when
      pointed at the files instead of the extracted snippets

  # MODIFY - scriptsource-03: the prompt's script fences now carry exactly
  # one include-marker line each; every other byte of the prompt (prose,
  # bullets, tables, the flow-law wording) is unchanged.
  Scenario: scriptsource-03
    When the reader reads "agents/prompts/orchestrator.prompt" after this
      sub-spec
    Then each of the three script fences' bodies is exactly the single line
      "# antz-include: scripts/orchestration/antz-flow.sh",
      "# antz-include: scripts/orchestration/antz-probe.sh", or
      "# antz-include: scripts/orchestration/antz-skills.sh", in the same
      position its fenced script previously occupied
    And the fence style itself is unchanged (the flow fence stays the first
      3-space-indented bare fence; the probe stays the "```sh" fence)
    And every line of the prompt outside those three fenced bodies is
      byte-for-byte unchanged

  # ADD - scriptsource-04: the extraction is scoped to the orchestrator
  # prompt — nothing else moves (transient change-time guard).
  Scenario: scriptsource-04
    When the diff of this sub-spec's implementation against the flow's base
      commit is inspected
    Then it touches only "scripts/orchestration/" (three new files) and the
      three fenced bodies of "agents/prompts/orchestrator.prompt"
    And "agents/prompts/specifier.prompt", "agents/prompts/coder.prompt",
      "agents/prompts/verifier.prompt", "agents/meta/" (all four), and
      "install.sh" are byte-for-byte unchanged by this sub-spec

### Invariants
- The scripts' runtime contract is untouched: still POSIX sh, still
  save-to-temp-file and `sh <tempfile> ...`, still nothing installed as a
  standalone CLI, hook, or plugin (the files are repo source, never
  installed anywhere).
- Behavior of the three scripts is unchanged: every existing script-level
  assertion keeps holding against the files.
- The prompt remains framework-neutral: the include markers carry no
  client-specific syntax, so the same body still renders into both clients.

## Out of scope
- Any change to install.sh's rendering or injection (sub-spec 02).
- Any change to the scripts' behavior, subcommands, output shapes, or law
  wording (the branch-marked flow law and no-commit law are untouched).
- Any change to tests/ here (sub-spec 03 switches them to the files).

## Relevant files
- "agents/prompts/orchestrator.prompt" — the three fenced bodies become
  include markers (shared contract above).
- "scripts/orchestration/antz-flow.sh", "scripts/orchestration/antz-probe.sh",
  "scripts/orchestration/antz-skills.sh" — new source files, dedents of the
  current snippets.
- "tests/antz-flow_test.sh", "tests/orchestrator-status-probe_test.sh",
  "tests/orchestrator-skills-block_test.sh" — the extractors these replace
  are the byte-equality reference for scriptsource-02.
