Feature: End-to-end QA - the interactive model picker, through real installs and real command invocations
  # Operates through the real product UI: install.sh's CLI for setup, and the
  # installed slash commands typed inside a live Claude Code or OpenCode
  # session (their flags are a UI affordance of that native command, not an
  # internal API call). Every scenario below is tagged ADD against
  # spdd/specs/set-model.md's e2e suite; its e2e-qa-01..07 remain valid
  # unchanged (every invocation there passes explicit flags, so it never
  # reaches the picker). Ids continue from the governing suite at 08.

  Background:
    Given a local checkout of the antz repo with this change's install.sh
    And clean, empty "$HOME/.claude/agents", "$HOME/.claude/commands",
      "$HOME/.config/opencode/agents", and "$HOME/.config/opencode/commands"
      directories
    And the user has already run "./install.sh --all", installing all 4
      agents plus the "/antz" and "/antz-set-model" commands for both
      clients, with no "model:" line anywhere

  # ADD - e2e-qa-08: the interactive picker happy path in Claude Code, from a
  # clean state: the question is shown (no explicit flags needed), the current
  # state is stated, and picking a listed alias writes it via the same
  # embedded script -- visible on exactly that agent/client file.
  Scenario: e2e-qa-08
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder" (no --model, no --clear)
    Then Claude Code shows one question offering the options "sonnet", "opus", "haiku", and "revert to default (clear)"
    And the question text states that no model is currently configured and names "best", "fable", "sonnet[1m]", "opus[1m]", "opusplan" as further enterable values
    And the user picks "sonnet"
    Then "~/.claude/agents/antz-coder.md" contains the line "model: sonnet"
    And "~/.claude/agents/antz-specifier.md", "antz-verifier.md", and "antz-orchestrator.md" (Claude Code) contain no "model:" line
    And "~/.config/opencode/agents/antz-coder.md" contains no "model:" line
    And Claude Code's reply confirms "antz-coder" now has "model: sonnet"

  # ADD - e2e-qa-09: the picker indicates the currently configured model, and
  # a free-form answer is written verbatim (regression of the model value
  # contract through the new source).
  Scenario: e2e-qa-09
    Given the user has already run "/antz-set-model --agent coder --model opus" in a Claude Code session
    When the user, in that same Claude Code session, runs "/antz-set-model --agent coder" (no --model, no --clear)
    Then the question text states that the currently configured model is "opus"
    And the offered option "opus" is marked as the current one
    And the user answers via the free-text row with "claude-opus-4-8"
    Then "~/.claude/agents/antz-coder.md" contains the line "model: claude-opus-4-8" verbatim
    And the reply confirms it

  # ADD - e2e-qa-10: choosing the clear option reverts the agent to the
  # client's own default (no "model:" line) -- the picker's path to the same
  # outcome as the explicit --clear flag.
  Scenario: e2e-qa-10
    Given the user has already run "/antz-set-model --agent orchestrator --model opus" in a Claude Code session
    When the user, in that same Claude Code session, runs "/antz-set-model --agent orchestrator" (no --model, no --clear)
    And the user picks "revert to default (clear)"
    Then "~/.claude/agents/antz-orchestrator.md" contains no "model:" line
    And the reply confirms the model was cleared

  # ADD - e2e-qa-11: dismissing the question cancels the whole operation --
  # nothing is written, and the session says so. A user who aborts the picker
  # never gets a half-applied edit.
  Scenario: e2e-qa-11
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder" (no --model, no --clear)
    And the user dismisses the question without answering
    Then "~/.claude/agents/antz-coder.md" contains no "model:" line
    And the reply states that nothing was changed

  # ADD - e2e-qa-12: fail-fast, no question for a doomed request -- an
  # interactive-shaped request for an uninstalled agent is refused outright
  # (human-observable: no question dialog appears), with no file created.
  # This is the observable pairing of set-model-cmd-06's outcome with the new
  # ordering contract.
  Scenario: e2e-qa-12
    Given "~/.claude/agents/antz-coder.md" was manually deleted after install
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder" (no --model, no --clear)
    Then the reply explains that "coder" must be installed for "claude" first
    And no question dialog was shown
    And no file is created at "~/.claude/agents/antz-coder.md"

  # ADD - e2e-qa-13: the OpenCode picker enumerates real models at invocation
  # time and always offers free-form plus clear; picking an enumerated id
  # writes it verbatim at OpenCode's fixed frontmatter position.
  Scenario: e2e-qa-13
    When the user, in an OpenCode session, runs "/antz-set-model --agent coder" (no --model, no --clear)
    Then the session runs "opencode models" and shows a question listing "provider/model" ids, plus a "type another value" free-form option and a "revert to default (clear)" option
    And the user picks "anthropic/claude-opus-4-5"
    Then "~/.config/opencode/agents/antz-coder.md" contains the line "model: anthropic/claude-opus-4-5"
    And the reply confirms it

  # ADD - e2e-qa-14: the OpenCode picker's clear option maps to the script's
  # --clear.
  Scenario: e2e-qa-14
    Given the user has already run "/antz-set-model --agent coder --model anthropic/claude-opus-4-5" in an OpenCode session
    When the user, in that same OpenCode session, runs "/antz-set-model --agent coder" (no --model, no --clear)
    And the user picks "revert to default (clear)"
    Then "~/.config/opencode/agents/antz-coder.md" contains no "model:" line
    And the reply confirms the model was cleared

  # ADD - e2e-qa-15: the non-interactive bypass is preserved end-to-end in
  # both clients: explicit --model invocations never show a question (whole-
  # suite regression guard for the preserved flag contract).
  Scenario: e2e-qa-15
    When the user, in a Claude Code session, runs "/antz-set-model --agent verifier --model opus"
    And the user, in an OpenCode session, runs "/antz-set-model --agent verifier --model anthropic/claude-opus-4-5"
    Then no question dialog was shown in either client
    And "~/.claude/agents/antz-verifier.md" contains the line "model: opus"
    And "~/.config/opencode/agents/antz-verifier.md" contains the line "model: anthropic/claude-opus-4-5"

  # ADD - e2e-qa-16: the updated command body actually reaches users through
  # the normal install path: re-running install.sh overwrites the previously
  # installed command copies in place (no backup, marker convention), and the
  # interactive picker then works in a fresh session.
  Scenario: e2e-qa-16
    Given both command files already exist from a previous install and carry the "antz:generated" marker
    When the user runs "./install.sh --all" again
    Then no ".bak.<timestamp>" files are created for either command file
    And the command bodies contain the pre-flight and interactive-picker instructions
    When the user, in a Claude Code session, then runs "/antz-set-model --agent coder" (no --model, no --clear)
    Then the interactive picker question is shown, offering the options "sonnet", "opus", "haiku", and "revert to default (clear)"
