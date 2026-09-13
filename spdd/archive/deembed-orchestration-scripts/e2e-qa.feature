# Change: deembed-orchestration-scripts — end-to-end QA suite (verifier-owned)
#
# Operates through the real product UI: install.sh's own CLI for install /
# --check / upgrade affordances, the installed files as the user reads
# them, and the script invocations exactly as the installed bodies instruct
# them (paths and flags are UI affordances, not internal API calls). No
# role can spawn a live Claude Code / OpenCode session, so live-session
# halves follow the repo's established convention: judged by the mechanism
# they exercise, with the script-level half executed.

Feature: the de-embed as the user experiences it — installed scripts, path invocations, stable prefix, upgrade path

  Background:
    Given a local checkout of antz with the change applied
    And isolated HOME directories so QA never touches the real
      "~/.claude", "~/.config/opencode", or a real antz libdir
    And a fixture git repository (at least one commit) for flow-script
      invocations

  # ADD - e2e-qa-01: a fresh install puts sixteen marked files on disk —
  # the twelve client files plus the four libdir scripts — and --check
  # immediately agrees everything is up to date.
  Scenario: e2e-qa-01
    When the user runs "sh install.sh --all" with HOME set to an isolated
      empty directory
    Then the exit status is 0
    And the twelve client files exist (4 agents x 2 clients, plus both
      "antz.md" and both "antz-set-model.md" copies), each carrying an
      "antz:generated" marker whose embedded VERSION matches the repo's
      VERSION file
    And the four script files exist under "<HOME>/.config/antz/scripts/"
      ("antz-flow.sh", "antz-probe.sh", "antz-skills.sh",
      "antz-set-model.sh"), each carrying the same marker as a line-start
      header comment right after its shebang
    And no ".bak.<timestamp>" file was created anywhere
    When the user runs "sh install.sh --check" against that HOME
    Then the exit status is 0, nothing changes on disk, and the report
      says "already up to date" for both clients and for each of the four
      scripts

  # ADD - e2e-qa-02: the XDG resolution a user with a configured
  # XDG_CONFIG_HOME sees — scripts land under their root, and the rendered
  # bodies reference exactly that path.
  Scenario: e2e-qa-02
    When the user runs "sh install.sh --all" with XDG_CONFIG_HOME set to a
      non-default directory inside the isolated HOME tree
    Then the four script files exist under "<XDG_CONFIG_HOME>/antz/scripts/"
    And the installed "antz-orchestrator" bodies (both clients) and both
      "antz-set-model.md" command bodies reference the scripts only by
      that concrete resolved path
    And no installed file contains the literal token "__ANTZ_SCRIPTS_DIR__"
      or the string "antz-include"

  # ADD - e2e-qa-03: no embedded scripts anywhere, and the path invocation
  # the installed bodies print is the real thing — running the installed
  # flow script by the path the body prints produces the machine lines the
  # source script produces.
  Scenario: e2e-qa-03
    When the user reads the installed "antz-orchestrator.md" for either
      client and both installed "antz-set-model.md" copies
    Then no file carries any line from the three orchestration scripts or
      the set-model script (for example "state=no_git", "candidate=on-disk",
      or the set-model argument loop appear in none of them), and neither
      orchestration body instructs saving any script to a temp file
    And each orchestrator body's step-1 instruction shows the flow script's
      concrete libdir path
    When the flow script is invoked as that instruction shows —
      "sh \"<libdir>/antz-flow.sh\" discover" inside the fixture repository
    Then the output is the machine-line vocabulary, byte-identical to
      running "sh scripts/orchestration/antz-flow.sh discover" from the
      repo sources (same candidate= lines, same exit status)

  # ADD - e2e-qa-04: set-model through the installed pieces — the command
  # body's run instruction (script path + the copy's own client) performs
  # the same edit, refusal, and clear as before.
  Scenario: e2e-qa-04
    Given the e2e-qa-01 install in an isolated HOME
    When the set-model script is invoked exactly as the installed Claude
      command copy instructs — "sh \"<libdir>/antz-set-model.sh\" claude
      --agent coder --model opus"
    Then "<HOME>/.claude/agents/antz-coder.md" contains the line
      "model: opus" immediately after its "description:" line and
      immediately before its "tools:" line, with everything else
      byte-preserved
    When the script runs again with "--clear"
    Then the "model:" line is gone and the reply confirms the clear
    When the script runs with an unknown client argument, and again against
      a target file that lacks the "antz:generated" marker
    Then both runs are refused with the specific reason, and no file is
      written either time

  # ADD - e2e-qa-05: the upgrade path a pre-change user takes — --check
  # reports the client drift and the scripts as fresh installs, --all
  # restamps everything, nothing is lost.
  Scenario: e2e-qa-05
    Given a HOME holding a genuine pre-change (4.7.1-stamped) install of
      the twelve client files and no antz libdir
    When the user runs "sh install.sh --check" with the changed tree
    Then the report shows both clients drifting to 4.8.0 and prints the
      "[4.8.0]" CHANGELOG entry once, and reports each of the four scripts
      as a fresh install, writing nothing
    When the user runs "sh install.sh --all"
    Then the twelve client files are restamped in place (no backups), and
      the four scripts appear under "<HOME>/.config/antz/scripts/" with
      4.8.0 markers
    And a fresh "--check" reports already up to date for both clients and
      all four scripts

  # ADD - e2e-qa-06: the stable prefix a caching client experiences — the
  # same VERSION renders byte-identically, session after session.
  Scenario: e2e-qa-06
    When "sh install.sh --all" runs twice into two fresh isolated HOMEs
      with the unchanged repo VERSION
    Then the two HOME trees are byte-identical (verified recursively), so
      a client caching the rendered orchestrator system prompt sees a
      byte-stable prefix across sessions of the same installed version
    And the rendered orchestrator body contains no script lines, no
      temp-file instructions, and no per-run data — only the frontmatter
      marker version would change on a future VERSION bump, which is the
      accepted, documented invalidation
