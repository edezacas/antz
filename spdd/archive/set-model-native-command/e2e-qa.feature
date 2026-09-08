Feature: End-to-end QA - configuring an agent's model from inside Claude Code or OpenCode
  # Operates through the real product UI: install.sh's CLI for setup, and
  # the installed slash commands typed inside a live Claude Code or
  # OpenCode session (their flags are a UI affordance of that native
  # command, not an internal API call). Every scenario below is tagged ADD.

  Background:
    Given a local checkout of the antz repo
    And clean, empty "$HOME/.claude/agents", "$HOME/.claude/commands",
      "$HOME/.config/opencode/agents", and "$HOME/.config/opencode/commands"
      directories
    And the user has already run "./install.sh --all", installing all 4
      agents plus the "/antz" and "/antz-set-model" commands for both
      clients, with no "model:" line anywhere

  # ADD - e2e-qa-01: install.sh alone still never configures a model
  # (regression guard on existing behavior), and the new command is present
  # for both clients after that same install.
  Scenario: e2e-qa-01
    When the user runs "./install.sh --all" again
    Then all 8 installed agent files (4 agents x 2 clients) still contain no "model:" line
    And "~/.claude/commands/antz-set-model.md" and "~/.config/opencode/commands/antz-set-model.md" are both present

  # ADD - e2e-qa-02: configuring a single agent from inside Claude Code is
  # visible on exactly that agent/client file, and nowhere else.
  Scenario: e2e-qa-02
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" contains the line "model: opus"
    And "~/.claude/agents/antz-specifier.md", "antz-verifier.md", and "antz-orchestrator.md" (Claude Code) contain no "model:" line
    And "~/.config/opencode/agents/antz-coder.md" contains no "model:" line
    And Claude Code's reply confirms the change

  # ADD - e2e-qa-03: configuring the same agent for both clients takes one
  # invocation inside each client, each with a value valid for that
  # client's own model-identifier syntax.
  Scenario: e2e-qa-03
    When the user, in a Claude Code session, runs "/antz-set-model --agent verifier --model opus"
    And the user, in an OpenCode session, runs "/antz-set-model --agent verifier --model anthropic/claude-opus-4-5"
    Then "~/.claude/agents/antz-verifier.md" contains the line "model: opus"
    And "~/.config/opencode/agents/antz-verifier.md" contains the line "model: anthropic/claude-opus-4-5"

  # ADD - e2e-qa-04: clearing a previously configured model reverts that
  # agent/client to the client's own default (no "model:" line).
  Scenario: e2e-qa-04
    Given the user has already run "/antz-set-model --agent orchestrator --model opus" in a Claude Code session
    When the user, in that same Claude Code session, runs "/antz-set-model --agent orchestrator --clear"
    Then "~/.claude/agents/antz-orchestrator.md" contains no "model:" line

  # ADD - e2e-qa-05: a later install.sh run (e.g. to pick up a version
  # update) silently reverts a configured model, since install.sh's own
  # rendering has no concept of "model:" -- an accepted, documented
  # interaction carried over unchanged from the retired set-model.sh -- but
  # leaves the "/antz-set-model" command itself installed and usable.
  Scenario: e2e-qa-05
    Given the user has already run "/antz-set-model --agent coder --model opus" in a Claude Code session
    When the user runs "./install.sh --claude" again
    Then "~/.claude/agents/antz-coder.md" contains no "model:" line
    And "~/.claude/commands/antz-set-model.md" is still installed

  # ADD - e2e-qa-06: re-invoking the command after such a revert restores
  # the configuration.
  Scenario: e2e-qa-06
    Given the user has already run "/antz-set-model --agent coder --model opus" in a Claude Code session
    And the user has already run "./install.sh --claude" again, reverting it
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder --model opus" again
    Then "~/.claude/agents/antz-coder.md" contains the line "model: opus"

  # ADD - e2e-qa-07: invoking the command for an agent that isn't installed
  # for that client yet (e.g. its file was manually removed after install)
  # fails clearly instead of creating a partial file. Note: unlike the
  # retired set-model.sh, it is no longer possible to hit this via "install
  # never ran at all" -- /antz-set-model itself would not be an available
  # command in that case, since install.sh installs it together with the
  # four role agents in the same run.
  Scenario: e2e-qa-07
    Given "~/.claude/agents/antz-coder.md" was manually deleted after install
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder --model opus"
    Then the reply explains that "coder" must be installed for "claude" first
    And no file is created at "~/.claude/agents/antz-coder.md"
