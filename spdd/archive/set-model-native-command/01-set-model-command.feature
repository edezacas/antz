Feature: install.sh installs /antz-set-model, and invoking it configures or clears an agent's model
  # Layer: the entire feature (no further split -- see README.md). Covers
  # (a) install.sh rendering/installing the new command file per client,
  # (b) the deterministic file-editing behavior that command triggers when
  # invoked, and (c) retiring the standalone set-model.sh script and its
  # test suite, which this command replaces outright (resolved decision --
  # see README.md; OPEN_QUESTIONS.md has been resolved and deleted). Every
  # "command-install-*" and "set-model-cmd-*" scenario below is tagged ADD
  # against spdd/specs/set-model.md. The "retire-set-model-01" scenario and
  # the REMOVE mapping table at the end of this file describe what that
  # spec's own existing scenarios lose.

  Background:
    Given the four agents "specifier", "coder", "verifier", "orchestrator"
    And the two clients "claude" (agent files under "~/.claude/agents/",
      commands under "~/.claude/commands/") and "opencode" (agent files
      under "~/.config/opencode/agents/", commands under
      "~/.config/opencode/commands/")
    And each installed agent file is named "antz-<agent>.md"
    And "model:" sits, for "claude", immediately after "description:" and
      immediately before "tools:"; for "opencode", immediately after
      "description:" and immediately before "mode:"
    And each client's installed copy of "/antz-set-model" is permanently
      scoped to that same client's own agent files -- the invoker never
      supplies a client flag or argument

  ## Installation (install.sh renders and installs the command file)

  # ADD - command-install-01: install.sh installs the Claude Code copy with
  # the expected frontmatter shape, mirroring how it already installs /antz.
  Scenario: command-install-01
    Given a clean "~/.claude/commands" directory
    When the user runs "./install.sh --claude"
    Then "~/.claude/commands/antz-set-model.md" is created
    And its frontmatter contains the "antz:generated" marker with the current install.sh version
    And its frontmatter contains a "description:" field describing the command's purpose
    And its frontmatter contains "argument-hint: --agent <specifier|coder|verifier|orchestrator> (--model <value>|--clear)"
    And its body is scoped to the "claude" client only -- it never references OpenCode's agent directory or frontmatter position

  # ADD - command-install-02: same for OpenCode, at OpenCode's own paths --
  # and, unlike /antz, with no "agent:" frontmatter field, since this
  # command never delegates to any of the four antz-* role subagents.
  Scenario: command-install-02
    Given a clean "~/.config/opencode/commands" directory
    When the user runs "./install.sh --opencode"
    Then "~/.config/opencode/commands/antz-set-model.md" is created
    And its frontmatter contains the "antz:generated" marker with the current install.sh version
    And its frontmatter contains a "description:" field describing the command's purpose
    And its frontmatter contains no "agent:" field
    And its body is scoped to the "opencode" client only -- it never references Claude Code's agent directory or frontmatter position

  # ADD - command-install-03: re-running is idempotent, reusing install.sh's
  # existing marker-based overwrite-in-place convention.
  Scenario: command-install-03
    Given "~/.claude/commands/antz-set-model.md" already exists and carries the "antz:generated" marker
    When the user runs "./install.sh --claude" again
    Then "~/.claude/commands/antz-set-model.md" is overwritten in place
    And no ".bak.<timestamp>" file is created for it

  # ADD - command-install-04: a pre-existing, non-antz-managed file at the
  # same path is backed up rather than clobbered -- same mechanism
  # install.sh already applies to every other file it installs.
  Scenario: command-install-04
    Given a file exists at "~/.claude/commands/antz-set-model.md" that does not carry the "antz:generated" marker
    When the user runs "./install.sh --claude"
    Then the pre-existing file is backed up to "antz-set-model.md.bak.<timestamp>"
    And "~/.claude/commands/antz-set-model.md" is then installed fresh

  # ADD - command-install-05: plain, flag-less install.sh auto-detects and
  # installs this command for whichever client(s) are detected, exactly
  # like it already does for antz.md and the four role agents.
  Scenario: command-install-05
    Given only Claude Code is detected on this machine
    When the user runs "./install.sh" with no flags
    Then "~/.claude/commands/antz-set-model.md" is installed
    And no "~/.config/opencode/commands/antz-set-model.md" is created

  ## Invocation (the installed command edits the target agent file)

  # ADD - set-model-cmd-01: adding a model to a Claude Code agent file that
  # has none yet. The line is inserted at this repo's fixed frontmatter
  # position.
  Scenario: set-model-cmd-01
    Given "~/.claude/agents/antz-coder.md" exists and carries the "antz:generated" marker
    And its frontmatter has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" contains the line "model: opus"
    And that line appears immediately after the "description:" line and immediately before the "tools:" line
    And every other line in the file is byte-for-byte unchanged
    And the command's reply confirms "antz-coder" now has "model: opus"

  # ADD - set-model-cmd-02: same, for an OpenCode agent file, at OpenCode's
  # fixed position.
  Scenario: set-model-cmd-02
    Given "~/.config/opencode/agents/antz-verifier.md" exists and carries the "antz:generated" marker
    And its frontmatter has no "model:" line
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent verifier --model anthropic/claude-opus-4-5"
    Then "~/.config/opencode/agents/antz-verifier.md" contains the line "model: anthropic/claude-opus-4-5"
    And that line appears immediately after the "description:" line and immediately before the "mode:" line
    And every other line in the file is byte-for-byte unchanged
    And the command's reply confirms "antz-verifier" now has "model: anthropic/claude-opus-4-5"

  # ADD - set-model-cmd-03: replacing an already-configured model with a
  # different one.
  Scenario: set-model-cmd-03
    Given "~/.claude/agents/antz-coder.md" already has the line "model: opus"
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model sonnet"
    Then the file's frontmatter contains the line "model: sonnet" and not "model: opus"
    And that line appears at the same position as before
    And every other line in the file is byte-for-byte unchanged

  # ADD - set-model-cmd-04: clearing a configured model removes the line
  # entirely.
  Scenario: set-model-cmd-04
    Given "~/.claude/agents/antz-coder.md" already has a "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --clear"
    Then the file's frontmatter contains no "model:" line
    And every other line in the file is byte-for-byte unchanged
    And the command's reply confirms the model was cleared

  # ADD - set-model-cmd-05: clearing when nothing is configured is a
  # harmless no-op.
  Scenario: set-model-cmd-05
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --clear"
    Then the file is byte-for-byte unchanged
    And the command's reply confirms there was no model configured to clear

  # ADD - set-model-cmd-06: refuses to act on an agent that isn't installed
  # yet for that client, rather than creating a partial or malformed file.
  Scenario: set-model-cmd-06
    Given no file exists at "~/.claude/agents/antz-coder.md"
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then the command's reply explains that "coder" must be installed for "claude" first (e.g. via install.sh)
    And no file is created

  # ADD - set-model-cmd-07: refuses to touch a same-named file that isn't
  # antz-managed, rather than silently overwriting or guessing.
  Scenario: set-model-cmd-07
    Given a file exists at "~/.claude/agents/antz-coder.md" that does not carry the "antz:generated" marker
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then the command's reply explains the file is not antz-managed
    And that file is left byte-for-byte unchanged

  # ADD - set-model-cmd-08: an unknown agent name is rejected before
  # touching any file.
  Scenario: set-model-cmd-08
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent bogus --model opus"
    Then the command's reply is a usage error naming the four valid agents
    And no file is written

  # ADD - set-model-cmd-09: exactly one of --model/--clear is required.
  Scenario Outline: set-model-cmd-09
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder <extra-args>"
    Then the command's reply is a usage error
    And no file is written

    Examples:
      | extra-args              |
      |                         |
      | --model opus --clear    |

  # ADD - set-model-cmd-10: invoking one client's copy never reads or
  # writes the other client's installed file for the same agent -- a
  # structural guarantee now, since each copy is permanently scoped to its
  # own client (see Background).
  Scenario: set-model-cmd-10
    Given both "~/.claude/agents/antz-coder.md" and "~/.config/opencode/agents/antz-coder.md" exist, neither with a "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" gains the line "model: opus"
    And "~/.config/opencode/agents/antz-coder.md" is byte-for-byte unchanged

  # ADD - set-model-cmd-11: invoking for one agent never touches another
  # agent's installed file.
  Scenario: set-model-cmd-11
    Given both "~/.claude/agents/antz-coder.md" and "~/.claude/agents/antz-specifier.md" exist, neither with a "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" gains the line "model: opus"
    And "~/.claude/agents/antz-specifier.md" is byte-for-byte unchanged

  # ADD - set-model-cmd-12: the supplied value is used verbatim -- this
  # command never validates or translates it against the target client's
  # syntax.
  Scenario: set-model-cmd-12
    Given "~/.config/opencode/agents/antz-coder.md" exists and carries the "antz:generated" marker
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent coder --model not-a-real-model"
    Then the file's frontmatter contains the line "model: not-a-real-model" verbatim
    And the command's reply confirms success

  ## Retirement of set-model.sh (this change replaces it entirely)

  # ADD - retire-set-model-01: the standalone script and its test suite are
  # deleted outright, per the user's resolved decision (Option A -- Replace,
  # see README.md) -- not kept alongside the new command, and not merely
  # deprecated or relocated in place.
  Scenario: retire-set-model-01
    Given a repo checkout with "set-model.sh" and "tests/set-model_test.sh"
      present, as delivered by the prior "configurable-agent-model" change
    When this change is implemented
    Then "set-model.sh" no longer exists at the repo root
    And "tests/set-model_test.sh" no longer exists
    And "/antz-set-model" (set-model-cmd-01 through set-model-cmd-12 above)
      is the only remaining way to configure or clear an agent's model --
      no standalone, headless/CI-invokable script remains

  ## Scenarios retired from spdd/specs/set-model.md (REMOVE)

  # The prior configurable-agent-model change's entire domain spec described
  # a standalone script, set-model.sh, invoked directly from a shell. This
  # change replaces that delivery mechanism outright (resolved user
  # decision -- Option A). Every scenario in spdd/specs/set-model.md is
  # tagged REMOVE at merge time; none are superseded via MODIFY, since the
  # CLI surface itself ("./set-model.sh --claude ...") no longer exists to
  # describe.

  # | Retired scenario id(s) in spdd/specs/set-model.md          | Superseded by (this change, ADD)                    |
  # |--------------------------------------------------------------|------------------------------------------------------|
  # | set-model-01 .. set-model-13                                  | set-model-cmd-01 .. set-model-cmd-12 above            |
  # | set-model.md's own End-to-end QA suite: e2e-qa-01 .. e2e-qa-07 | e2e-qa.feature's e2e-qa-01 .. e2e-qa-07               |

  # At merge time, spdd/specs/set-model.md's "Feature: set-model.sh --
  # configure or clear an already-installed agent's model" section, the
  # parts of its "Shared contracts" describing the set-model.sh CLI contract
  # specifically (the frontmatter-position table and model-value contract
  # carry forward unchanged in spirit, now owned by this change's Shared
  # contracts in README.md), and its own "End-to-end QA suite" section are
  # all removed. Its "Origin" and general per-agent/per-client goal framing
  # may be kept and updated by the verifier to describe /antz-set-model
  # instead of set-model.sh, or the whole file's content may end up
  # equivalent to this change's README.md + feature files -- the exact merge
  # mechanics are the verifier's call, not prescribed here.

### Invariants
See README.md Invariants (shared across this whole change).
