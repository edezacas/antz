# Domain: set-model

## Origin
- Specced and delivered from change `set-model-native-command` as
  `/antz-set-model`, a client-native command installed by `install.sh`
  alongside the four role agents and `/antz`, for both Claude Code and
  OpenCode. Every scenario in this file reflects that command-based
  delivery. The change's scenarios and end-to-end QA are preserved for
  history in `spdd/archive/set-model-native-command/`, not reproduced here.
  Change `set-model-interactive-picker` (merged 2026-09-08) then turned the
  command's no-flag form into an interactive model picker; its scenarios
  and e2e QA are likewise preserved in `spdd/archive/set-model-interactive-picker/`.

## Goal
`install.sh` never emits a `model:` field in any rendered agent file (Claude
Code or OpenCode) on its own — every agent runs on that client's own default
model until a user explicitly configures one. This domain covers
`/antz-set-model`, a command that lets a user configure a model **per agent,
per client** (specifier / coder / verifier / orchestrator, independently for
Claude Code and OpenCode) for an already-installed agent, without changing
what `install.sh`'s own agent-rendering logic installs or reports.

- **No new default.** By default, no agent has a configured model for any
  client — identical to before this feature. Model configuration is an
  additive capability a user opts into after installing, not a new shipped
  default.
- **The no-flag form is an interactive picker.** Invoking `/antz-set-model`
  with neither `--model` nor `--clear` opens the interactive model picker:
  the invoking session asks the USER which model to assign, via the
  client's native question mechanism (Claude Code: `AskUserQuestion` over
  an install-time-embedded alias vocabulary; OpenCode: models enumerated
  at invocation time via `opencode models` plus the `question` tool), then
  feeds the chosen value to the **same embedded script** as `--model`. The
  explicit-flag forms remain the non-interactive bypass; the embedded
  script's behavior and the verbatim-value contract are unchanged.
- **Two independent values, never one.** Claude Code's `model:` frontmatter
  takes a short alias (`sonnet`, `opus`, `haiku`, `inherit`); OpenCode's takes
  a `provider/model-id` slug (e.g. `anthropic/claude-sonnet-4-5`). These are
  never the same string. `/antz-set-model` doesn't need a `--claude`/
  `--opencode` flag to pick which one applies — each installed copy of the
  command is permanently scoped to the client it was installed for (see
  Client binding below).
- **`install.sh`'s own agent-rendering logic has no concept of `model:`.** It
  installs `/antz-set-model` itself (see Installation scenarios below), but
  the four role-agent files it renders never gain a `model:` line on their
  own, and `--check` stays keyed off version drift only, unaffected by any
  configured model.

## Shared contracts

**Client binding** — each installed copy of `/antz-set-model` is permanently
scoped to the client it was installed for: the Claude Code copy only ever
targets `~/.claude/agents/antz-<agent>.md` at Claude's frontmatter position
(immediately after `description:`, immediately before `tools:`); the
OpenCode copy only ever targets `~/.config/opencode/agents/antz-<agent>.md`
at OpenCode's position (immediately after `description:`, immediately before
`mode:`). The invoker never supplies a client flag or argument — which
client's copy of the command they ran already determines it.

**Command argument contract** (the text typed after the slash command,
delivered to the command as `$ARGUMENTS`; updated by
`set-model-interactive-picker`):
```
/antz-set-model --agent <specifier|coder|verifier|orchestrator> [--model <value>|--clear]
```
- `--agent` is required and must name one of the four role agents.
- `--model` and `--clear` are mutually exclusive; **at most one** may be
  given (never both).
- **Neither given → the interactive picker** (no longer a usage error): the
  invoking session asks the user which model to assign, per the picker-*
  scenarios below; the picker still requires a valid `--agent` and a passing
  file pre-flight before any question is asked.
- Usage errors (no question asked, no file written): unknown agent name;
  `--agent` missing (including an entirely empty invocation); `--agent` or
  `--model` given without its value; both `--model` and `--clear` given;
  unknown options or otherwise malformed arguments.
- No client flag exists in this contract (see Client binding above).

**Model value contract** — for a given agent and the one client a given
command copy targets, either:
- *absent* — no `model:` line (the default until a user explicitly
  configures one), or
- a *non-empty string* — the exact value supplied to `--model`, written
  **verbatim** into that file's `model:` line. Never validated or translated
  against the target client's syntax; the user is responsible for supplying
  a value valid for the client they targeted. This applies equally to a
  value sourced from the interactive picker (a listed alias, an enumerated
  `provider/model` id, or a free-form answer): the exact answer is written
  verbatim, never validated or translated. An empty or whitespace-only
  picker answer never reaches the script — it cancels the operation
  instead (nothing is written).

**Frontmatter position of `model:`** (this repo's own convention, fixed for
determinism, not dictated by either client):
| Client | Position |
|---|---|
| Claude Code | immediately after `description:`, immediately before `tools:` |
| OpenCode | immediately after `description:`, immediately before `mode:` |

**Target file / marker contract** — the target file (`~/.claude/agents/antz-<agent>.md`
or `~/.config/opencode/agents/antz-<agent>.md`) must already exist and carry
the `antz:generated` marker; otherwise the command fails without writing
anything, and explains why.

**Observable outcome contract** — the command's reply is natural language,
not spec'd byte-for-byte, but must state specific, checkable content:
- On success: which file changed and what its `model:` line now is (or that
  it was cleared).
- On failure: the specific reason (agent not installed for this client yet;
  target file isn't antz-managed; unknown agent name; both of
  `--model`/`--clear` given) and confirmation that no file was written.
  The script's own "neither" usage error survives only as a
  direct-invocation backstop (see set-model-cmd-09); at command level,
  neither flag opens the interactive picker.

## Feature: install.sh installs /antz-set-model, and invoking it configures or clears an agent's model

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

  # MODIFY - command-install-01: same scenario as the governing spec, with two
  # changes: the argument-hint now shows the --model/--clear group as optional
  # (the no-flag form is the interactive picker, not a missing-argument error),
  # and the body carries the picker instructions. Scoping and marker
  # assertions are unchanged. The corresponding unit test
  # (test_command_install_01) is updated to the new hint string.
  Scenario: command-install-01
    Given a clean "~/.claude/commands" directory
    When the user runs "./install.sh --claude"
    Then "~/.claude/commands/antz-set-model.md" is created
    And its frontmatter contains the "antz:generated" marker with the current install.sh version
    And its frontmatter contains a "description:" field describing the command's purpose, including that omitting --model/--clear opens an interactive picker
    And its frontmatter contains "argument-hint: --agent <specifier|coder|verifier|orchestrator> [--model <value>|--clear]"
    And its body contains the pre-flight and interactive-picker instructions for the "claude" client
    And its body still contains the embedded script and the relay rule (reply using exactly what the script printed)
    And its body is scoped to the "claude" client only -- it never references OpenCode's agent directory or frontmatter position

  # command-install-02: same for OpenCode, at OpenCode's own paths -- and,
  # unlike /antz, with no "agent:" frontmatter field, since this command
  # never delegates to any of the four antz-* role subagents.
  Scenario: command-install-02
    Given a clean "~/.config/opencode/commands" directory
    When the user runs "./install.sh --opencode"
    Then "~/.config/opencode/commands/antz-set-model.md" is created
    And its frontmatter contains the "antz:generated" marker with the current install.sh version
    And its frontmatter contains a "description:" field describing the command's purpose
    And its frontmatter contains no "agent:" field
    And its body is scoped to the "opencode" client only -- it never references Claude Code's agent directory or frontmatter position

  # command-install-03: re-running is idempotent, reusing install.sh's
  # existing marker-based overwrite-in-place convention.
  Scenario: command-install-03
    Given "~/.claude/commands/antz-set-model.md" already exists and carries the "antz:generated" marker
    When the user runs "./install.sh --claude" again
    Then "~/.claude/commands/antz-set-model.md" is overwritten in place
    And no ".bak.<timestamp>" file is created for it

  # command-install-04: a pre-existing, non-antz-managed file at the same
  # path is backed up rather than clobbered -- same mechanism install.sh
  # already applies to every other file it installs.
  Scenario: command-install-04
    Given a file exists at "~/.claude/commands/antz-set-model.md" that does not carry the "antz:generated" marker
    When the user runs "./install.sh --claude"
    Then the pre-existing file is backed up to "antz-set-model.md.bak.<timestamp>"
    And "~/.claude/commands/antz-set-model.md" is then installed fresh

  # command-install-05: plain, flag-less install.sh auto-detects and
  # installs this command for whichever client(s) are detected, exactly
  # like it already does for antz.md and the four role agents.
  Scenario: command-install-05
    Given only Claude Code is detected on this machine
    When the user runs "./install.sh" with no flags
    Then "~/.claude/commands/antz-set-model.md" is installed
    And no "~/.config/opencode/commands/antz-set-model.md" is created

  # The scenarios below were added by `set-model-interactive-picker` (all
  # tagged ADD): install.sh now renders the interactive-picker command body
  # per client, alongside the unchanged install-side scenarios above.

  # ADD - picker-render-01: the Claude Code copy embeds the full documented
  # alias vocabulary at install time (source:
  # https://code.claude.com/docs/es/model-config). All 8 values are embedded
  # even though only three become explicit question options (see
  # picker-claude-02) -- the embedded list is the stable vocabulary contract;
  # the explicit option subset is presentation constrained by the question
  # tool's 4-option schema cap. The list is refreshed only by re-running
  # install.sh; it is never queried at runtime.
  Scenario: picker-render-01
    When the user runs "./install.sh --claude"
    Then the body of "~/.claude/commands/antz-set-model.md" contains each of the values "best", "fable", "opus", "sonnet", "haiku", "sonnet[1m]", "opus[1m]", "opusplan"
    And the body states that this list is embedded and refreshed only by re-running install.sh, not queried at runtime
    And the body does not instruct the session to enumerate models at invocation time

  # ADD - picker-render-02: the OpenCode copy embeds no model catalog; it
  # instructs the session to enumerate models at invocation time via
  # "opencode models" run through the session's Bash tool.
  Scenario: picker-render-02
    When the user runs "./install.sh --opencode"
    Then the body of "~/.config/opencode/commands/antz-set-model.md" instructs running "opencode models" via the Bash tool to enumerate available "provider/model" ids
    And the body contains no embedded, hardcoded model list

  # ADD - picker-render-03: each copy instructs its own client's native
  # question mechanism, and the never-delegate rule is preserved verbatim in
  # both.
  Scenario: picker-render-03
    When the user runs "./install.sh --all"
    Then the body of "~/.claude/commands/antz-set-model.md" instructs asking the user via "AskUserQuestion" in this session
    And the body of "~/.config/opencode/commands/antz-set-model.md" instructs asking the user via the session's "question" tool
    And each body states that the command does not delegate to any of the four antz-* subagents

  # ADD - picker-render-04: the embedded script's exactly-one contract
  # survives untouched -- it is the backstop for direct (out-of-band)
  # invocation of the extracted temp file, and the reason every existing
  # script-level unit test keeps passing. The command body never invokes the
  # script without exactly one of --model/--clear.
  Scenario: picker-render-04
    When the user runs "./install.sh --claude"
    Then the embedded script in "~/.claude/commands/antz-set-model.md" still errors with a usage message when invoked with "--agent coder" (neither --model nor --clear)
    And the embedded script still errors with a usage message when invoked with "--agent coder --model opus --clear" (both)
    And the body instructs the session to invoke the script only with "--agent <agent> --model <chosen>" or "--agent <agent> --clear", never without one of the two

  # ADD - picker-render-05: the body states the fail-fast ordering: validate
  # arguments, confirm the target file exists and carries the marker, read the
  # current model: line -- all before any question is asked. This is the
  # unit-testable hook for the Ordering contract in README.md; the observable
  # behaviors are picker-cmd-01..05 below.
  Scenario: picker-render-05
    When the user runs "./install.sh --all"
    Then each client's command body instructs the session to, before asking any question, validate the arguments (unknown agent, missing --agent, dangling --agent/--model value, both --model and --clear, and unknown options are usage errors)
    And each body instructs the session to confirm the target file "antz-<agent>.md" exists and carries the "antz:generated" marker before asking
    And each body instructs the session to read the target file's current frontmatter "model:" line before asking
    And each body instructs the session to refuse with the failure reason, without asking any question, when validation or the file pre-flight fails

  ## Invocation (the installed command edits the target agent file)

  # set-model-cmd-01: adding a model to a Claude Code agent file that has
  # none yet. The line is inserted at this repo's fixed frontmatter position.
  Scenario: set-model-cmd-01
    Given "~/.claude/agents/antz-coder.md" exists and carries the "antz:generated" marker
    And its frontmatter has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" contains the line "model: opus"
    And that line appears immediately after the "description:" line and immediately before the "tools:" line
    And every other line in the file is byte-for-byte unchanged
    And the command's reply confirms "antz-coder" now has "model: opus"

  # set-model-cmd-02: same, for an OpenCode agent file, at OpenCode's fixed
  # position.
  Scenario: set-model-cmd-02
    Given "~/.config/opencode/agents/antz-verifier.md" exists and carries the "antz:generated" marker
    And its frontmatter has no "model:" line
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent verifier --model anthropic/claude-opus-4-5"
    Then "~/.config/opencode/agents/antz-verifier.md" contains the line "model: anthropic/claude-opus-4-5"
    And that line appears immediately after the "description:" line and immediately before the "mode:" line
    And every other line in the file is byte-for-byte unchanged
    And the command's reply confirms "antz-verifier" now has "model: anthropic/claude-opus-4-5"

  # set-model-cmd-03: replacing an already-configured model with a
  # different one.
  Scenario: set-model-cmd-03
    Given "~/.claude/agents/antz-coder.md" already has the line "model: opus"
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model sonnet"
    Then the file's frontmatter contains the line "model: sonnet" and not "model: opus"
    And that line appears at the same position as before
    And every other line in the file is byte-for-byte unchanged

  # set-model-cmd-04: clearing a configured model removes the line entirely.
  Scenario: set-model-cmd-04
    Given "~/.claude/agents/antz-coder.md" already has a "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --clear"
    Then the file's frontmatter contains no "model:" line
    And every other line in the file is byte-for-byte unchanged
    And the command's reply confirms the model was cleared

  # set-model-cmd-05: clearing when nothing is configured is a harmless
  # no-op.
  Scenario: set-model-cmd-05
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --clear"
    Then the file is byte-for-byte unchanged
    And the command's reply confirms there was no model configured to clear

  # set-model-cmd-06: refuses to act on an agent that isn't installed yet
  # for that client, rather than creating a partial or malformed file.
  Scenario: set-model-cmd-06
    Given no file exists at "~/.claude/agents/antz-coder.md"
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then the command's reply explains that "coder" must be installed for "claude" first (e.g. via install.sh)
    And no file is created

  # set-model-cmd-07: refuses to touch a same-named file that isn't
  # antz-managed, rather than silently overwriting or guessing.
  Scenario: set-model-cmd-07
    Given a file exists at "~/.claude/agents/antz-coder.md" that does not carry the "antz:generated" marker
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then the command's reply explains the file is not antz-managed
    And that file is left byte-for-byte unchanged

  # set-model-cmd-08: an unknown agent name is rejected before touching any
  # file.
  Scenario: set-model-cmd-08
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent bogus --model opus"
    Then the command's reply is a usage error naming the four valid agents
    And no file is written

  # MODIFY - set-model-cmd-09: the exactly-one rule survives at the EMBEDDED
  # SCRIPT level, which is what the existing unit tests exercise (they extract
  # the script and invoke it directly, so both rows below keep passing
  # untouched). At the COMMAND level, the "neither" row is no longer a usage
  # error -- it is the interactive picker (picker-cmd-08..13 and the client
  # groups above) -- while the "both" row remains a usage error
  # (picker-cmd-05). The verifier replaces the governing spec's set-model-cmd-09
  # with this script-level form and the pointer to the command-level
  # scenarios.
  Scenario Outline: set-model-cmd-09
    When the embedded script from the installed "claude" copy of "/antz-set-model" is invoked directly with "--agent coder <extra-args>"
    Then the script exits non-zero with a usage error
    And no file is written

    Examples:
      | extra-args           |
      |                      |
      | --model opus --clear |

  # set-model-cmd-10: invoking one client's copy never reads or writes the
  # other client's installed file for the same agent -- a structural
  # guarantee, since each copy is permanently scoped to its own client.
  Scenario: set-model-cmd-10
    Given both "~/.claude/agents/antz-coder.md" and "~/.config/opencode/agents/antz-coder.md" exist, neither with a "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" gains the line "model: opus"
    And "~/.config/opencode/agents/antz-coder.md" is byte-for-byte unchanged

  # set-model-cmd-11: invoking for one agent never touches another agent's
  # installed file.
  Scenario: set-model-cmd-11
    Given both "~/.claude/agents/antz-coder.md" and "~/.claude/agents/antz-specifier.md" exist, neither with a "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" gains the line "model: opus"
    And "~/.claude/agents/antz-specifier.md" is byte-for-byte unchanged

  # set-model-cmd-12: the supplied value is used verbatim -- this command
  # never validates or translates it against the target client's syntax.
  Scenario: set-model-cmd-12
    Given "~/.config/opencode/agents/antz-coder.md" exists and carries the "antz:generated" marker
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent coder --model not-a-real-model"
    Then the file's frontmatter contains the line "model: not-a-real-model" verbatim
    And the command's reply confirms success

  # The five sections below were added by `set-model-interactive-picker`
  # (all tagged ADD): the command-level interactive picker — shared
  # fail-fast ordering and bypass, the interactive flow, and each client's
  # option source and question mechanism.

  ## Argument validation and fail-fast ordering (shared by both clients)
  # These are command-level behaviors, observable only in a live client
  # session -- verified end-to-end (see e2e-qa.feature), not by the unit
  # script suite.

  # ADD - picker-cmd-01: an interactive-shaped request for an agent that isn't
  # installed for this client is refused BEFORE any question is asked -- the
  # user is never asked to pick a model for a request that cannot succeed.
  # Same refusal message as set-model-cmd-06.
  Scenario: picker-cmd-01
    Given no file exists at "~/.claude/agents/antz-coder.md"
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then the command's reply explains that "coder" must be installed for "claude" first (e.g. via install.sh)
    And no question is asked of the user
    And no file is created

  # ADD - picker-cmd-02: an interactive-shaped request targeting a file that
  # isn't antz-managed is refused before any question. Same refusal message
  # as set-model-cmd-07.
  Scenario: picker-cmd-02
    Given a file exists at "~/.claude/agents/antz-coder.md" that does not carry the "antz:generated" marker
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then the command's reply explains the file is not antz-managed
    And no question is asked of the user
    And that file is left byte-for-byte unchanged

  # ADD - picker-cmd-03: an unknown agent name is a usage error before any
  # question -- same usage error as set-model-cmd-08, and it applies to the
  # interactive form too (the picker requires a valid target agent).
  Scenario: picker-cmd-03
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent bogus" (no --model, no --clear)
    Then the command's reply is a usage error naming the four valid agents
    And no question is asked of the user
    And no file is written

  # ADD - picker-cmd-04: malformed arguments are usage errors before any
  # question. Note the empty-arguments row: --agent is still required, so an
  # empty invocation is a usage error, NOT the interactive picker.
  Scenario Outline: picker-cmd-04
    When the installed "claude" copy of "/antz-set-model" is invoked with "<arguments>"
    Then the command's reply is a usage error
    And no question is asked of the user
    And no file is written

    Examples:
      | arguments             |
      |                       |
      | --agent coder --bogus |
      | --agent coder --model |
      | --agent               |

  # ADD - picker-cmd-05: both --model and --clear together remains a usage
  # error before any question -- this is the surviving command-level half of
  # set-model-cmd-09 (see the MODIFY mapping for set-model-cmd-09 below).
  Scenario: picker-cmd-05
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus --clear"
    Then the command's reply is a usage error
    And no question is asked of the user
    And no file is written

  ## Non-interactive bypass (shared by both clients)

  # ADD - picker-cmd-06: when --model IS given, the command is unchanged: no
  # question is asked, the script runs with the given value, and the reply is
  # exactly the script's output. This preserves every outcome of
  # set-model-cmd-01..05, -10, -11, -12 (explicit-flag invocation) as the
  # scripted bypass.
  Scenario: picker-cmd-06
    Given "~/.claude/agents/antz-coder.md" exists and carries the "antz:generated" marker
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --model opus"
    Then no question is asked of the user
    And "~/.claude/agents/antz-coder.md" contains the line "model: opus" at the fixed frontmatter position
    And the command's reply is exactly what the script printed

  # ADD - picker-cmd-07: when --clear IS given, likewise no question is asked.
  Scenario: picker-cmd-07
    Given "~/.claude/agents/antz-coder.md" already has a "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder --clear"
    Then no question is asked of the user
    And the file's frontmatter contains no "model:" line
    And the command's reply is exactly what the script printed

  ## Interactive flow (shared shape; option source/mechanism per client below)

  # ADD - picker-cmd-08: the picker indicates the currently configured model.
  # The question text always states the current value (or that none is
  # configured); when the current value exactly equals an offered option's
  # value string, that option is marked as the current one. When the current
  # value is not among the offered options (e.g. a previously free-form value,
  # or "best"/"fable" on Claude Code), no option is marked but the question
  # text still names it. The current value is read from the target file's
  # frontmatter during the pre-flight, before asking.
  Scenario: picker-cmd-08
    Given "~/.claude/agents/antz-coder.md" already has the line "model: opus"
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then the user is asked which model to assign to "antz-coder"
    And the question text states that the currently configured model is "opus"
    And the offered option "opus" is marked as the current one

  # ADD - picker-cmd-09: with nothing configured, the question states that and
  # marks no option as current (per the agreed requirement, the indication
  # applies "if any" model is configured).
  Scenario: picker-cmd-09
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then the user is asked which model to assign to "antz-coder"
    And the question text states that no model is currently configured
    And no offered option is marked as the current one

  # ADD - picker-cmd-10: choosing a listed option feeds the chosen value to
  # the same embedded script as --model; the reply is exactly the script's
  # output (the relay rule is unchanged).
  Scenario: picker-cmd-10
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    And the user chooses the listed option "sonnet"
    Then the embedded script runs with "--agent coder --model sonnet"
    And "~/.claude/agents/antz-coder.md" contains the line "model: sonnet" at the fixed frontmatter position
    And the command's reply is exactly what the script printed (confirming "antz-coder" now has "model: sonnet")

  # ADD - picker-cmd-11: choosing the "revert to default (clear)" option maps
  # to the script's --clear; the reply is exactly the script's output,
  # including its nothing-to-clear no-op message when no model is configured.
  Scenario: picker-cmd-11
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    And the user chooses the "revert to default (clear)" option
    Then the embedded script runs with "--agent coder --clear"
    And the command's reply is exactly what the script printed (confirming there was no model configured to clear)

  # ADD - picker-cmd-12: a free-form answer is passed to the script verbatim,
  # unvalidated and untranslated -- the model value contract applies to the
  # picker as a value source exactly as it does to typed --model values.
  Scenario: picker-cmd-12
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    And the user answers with the free-form value "not-a-real-model"
    Then the embedded script runs with "--agent coder --model not-a-real-model"
    And "~/.claude/agents/antz-coder.md" contains the line "model: not-a-real-model" verbatim
    And the command's reply is exactly what the script printed

  # ADD - picker-cmd-13: dismissing the question, or answering with an empty
  # or whitespace-only value, cancels the operation: the script is never
  # invoked, nothing is written, and the reply states that nothing was
  # changed. A user who aborts the picker never gets a half-applied edit.
  Scenario: picker-cmd-13
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    And the user dismisses the question (or answers with an empty value)
    Then no file is written and the file is byte-for-byte unchanged
    And the command's reply states that nothing was changed

  ## Claude Code specifics (option source and question mechanism)

  # ADD - picker-claude-01: on Claude Code the question is asked with
  # AskUserQuestion in the invoking main session -- never from a subagent
  # (AskUserQuestion is a main-session tool), and the command never delegates
  # to any antz-* subagent before or after asking.
  Scenario: picker-claude-01
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then the invoking Claude Code main session asks the user via "AskUserQuestion"
    And no antz-* subagent is invoked at any point in the flow

  # ADD - picker-claude-02: presentation contract on Claude Code, within the
  # question tool's schema (2-4 explicit options per question, with a built-in
  # free-text row appended automatically). One question is asked; the explicit
  # options are the three stable family aliases plus the mandated clear
  # option; the remaining embedded vocabulary is named verbatim in the
  # question text so it can be entered free-form without typo risk; free-form
  # input is the tool's built-in free-text row, so no explicit option slot is
  # spent on a "type another value" entry. Rationale: README.md Resolved
  # specifier decisions 1-2.
  Scenario: picker-claude-02
    Given "~/.claude/agents/antz-coder.md" has no "model:" line
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then one "AskUserQuestion" question is asked offering exactly these explicit options, in this order: "sonnet", "opus", "haiku", "revert to default (clear)"
    And the question text names "best", "fable", "sonnet[1m]", "opus[1m]", and "opusplan" as further documented values that can be entered via free-form input
    And the user can enter any other value via the question tool's built-in free-text row, without a dedicated "type another value" option being listed

  # ADD - picker-claude-03: choosing the clear option on Claude Code maps to
  # the script's --clear (replacing the model: line with nothing), giving the
  # documented revert-to-default semantics.
  Scenario: picker-claude-03
    Given "~/.claude/agents/antz-coder.md" already has the line "model: opus"
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    And the user chooses the "revert to default (clear)" option
    Then "~/.claude/agents/antz-coder.md" contains no "model:" line
    And the command's reply is exactly what the script printed (confirming the model was cleared)

  ## OpenCode specifics (option source and question mechanism)

  # ADD - picker-opencode-01: on OpenCode the option list is enumerated at
  # invocation time: the session runs "opencode models" via its Bash tool and
  # offers the resulting "provider/model" ids as question options. Presentation
  # (grouping, prioritizing, e.g. the current session provider's models first)
  # is a prompt-level instruction, not a hard rule.
  Scenario: picker-opencode-01
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then the session runs "opencode models" via its Bash tool at invocation time
    And the user is asked, via the session's "question" tool, to choose from the enumerated "provider/model" ids
    And no antz-* subagent is invoked at any point in the flow

  # ADD - picker-opencode-02: the catalog can be large. The session may
  # filter, group, or paginate the presentation sensibly (prompt-level
  # guidance, not enforced by the script) -- but the free-form affordance and
  # the clear option must always remain offered, so no value is unreachable
  # even when the enumerated list is trimmed.
  Scenario: picker-opencode-02
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    And the enumerated catalog is too large to present in one question
    Then the session may present a filtered or grouped subset of the ids
    And the free-form "type another value" option and the "revert to default (clear)" option remain offered

  # ADD - picker-opencode-03: unlike Claude Code, OpenCode's agreed design
  # includes an EXPLICIT free-form option in the offered choices (no built-in
  # free-text row is assumed), alongside the clear option.
  Scenario: picker-opencode-03
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    Then the offered choices include an explicit "type another value" free-form option
    And the offered choices include the "revert to default (clear)" option

  # ADD - picker-opencode-04: if the enumeration fails or returns nothing
  # (e.g. no providers configured), the picker degrades instead of failing:
  # the question is still asked with the free-form and clear options only, and
  # the question text states that no models could be enumerated.
  Scenario: picker-opencode-04
    When the installed "opencode" copy of "/antz-set-model" is invoked with "--agent coder" (no --model, no --clear)
    And "opencode models" fails or returns no model ids
    Then the user is still asked via the "question" tool, with the question text stating that no models could be enumerated
    And the offered choices are the "type another value" free-form option and the "revert to default (clear)" option

### Invariants
- The command never invokes, wraps, or reimplements `install.sh`'s *agent*-
  rendering functions (`render_claude`/`render_opencode`/`install_file` as
  applied to role-agent files) — it edits an already-installed agent file's
  frontmatter directly and in place.
- Only the `model:` line (added, replaced, or removed) may differ before and
  after. The marker/version comment, `name`/`description`/`tools:` (Claude
  Code) or `description`/`mode`/`permission:` (OpenCode), and the prompt
  body are always byte-for-byte preserved.
- A file this command just edited keeps carrying the `antz:generated`
  marker, so a later plain `install.sh` run still recognizes it as
  antz-managed and overwrites it in place, silently dropping any configured
  model (`install.sh`'s rendering has no concept of `model:` at all) — the
  user re-invokes the command after such a run if they want to keep a
  custom model (see e2e-qa-05/06 below).
- `/antz-set-model` runs directly in whatever session/agent context invoked
  it (the main Claude Code session, or OpenCode's currently active agent) —
  unlike `/antz`, it never delegates to any of the four `antz-*` role
  subagents. If that session's active agent/mode lacks edit capability (e.g.
  a restricted OpenCode mode), the edit fails for reasons outside this
  command's control.
- Installing this command reuses `install.sh`'s existing `MARKER`/
  `install_file` backup-if-unmanaged convention; no new marker or backup
  mechanism is introduced.
- A change confined to `install.sh` does not touch `agents/prompts/` or
  `agents/meta/` and so does not require a `VERSION`/`CHANGELOG.md` bump —
  `install.sh --check`'s version-drift report stays keyed off the specifier
  agent file only, unaffected by this command's addition.

## End-to-end QA suite

Operates through the real product UI: `install.sh`'s own CLI for setup/
regression checks, and the installed slash commands typed inside a live
Claude Code or OpenCode session (their flags are a UI affordance of that
native command, not an internal API call). Ids e2e-qa-08..16 were added by `set-model-interactive-picker` and continue the series from 08.

  Background:
    Given a local checkout of the antz repo
    And clean, empty "$HOME/.claude/agents", "$HOME/.claude/commands",
      "$HOME/.config/opencode/agents", and "$HOME/.config/opencode/commands"
      directories
    And the user has already run "./install.sh --all", installing all 4
      agents plus the "/antz" and "/antz-set-model" commands for both
      clients, with no "model:" line anywhere

  # e2e-qa-01: install.sh alone still never configures a model (regression
  # guard on existing behavior), and the new command is present for both
  # clients after that same install.
  Scenario: e2e-qa-01
    When the user runs "./install.sh --all" again
    Then all 8 installed agent files (4 agents x 2 clients) still contain no "model:" line
    And "~/.claude/commands/antz-set-model.md" and "~/.config/opencode/commands/antz-set-model.md" are both present

  # e2e-qa-02: configuring a single agent from inside Claude Code is
  # visible on exactly that agent/client file, and nowhere else.
  Scenario: e2e-qa-02
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder --model opus"
    Then "~/.claude/agents/antz-coder.md" contains the line "model: opus"
    And "~/.claude/agents/antz-specifier.md", "antz-verifier.md", and "antz-orchestrator.md" (Claude Code) contain no "model:" line
    And "~/.config/opencode/agents/antz-coder.md" contains no "model:" line
    And Claude Code's reply confirms the change

  # e2e-qa-03: configuring the same agent for both clients takes one
  # invocation inside each client, each with a value valid for that
  # client's own model-identifier syntax.
  Scenario: e2e-qa-03
    When the user, in a Claude Code session, runs "/antz-set-model --agent verifier --model opus"
    And the user, in an OpenCode session, runs "/antz-set-model --agent verifier --model anthropic/claude-opus-4-5"
    Then "~/.claude/agents/antz-verifier.md" contains the line "model: opus"
    And "~/.config/opencode/agents/antz-verifier.md" contains the line "model: anthropic/claude-opus-4-5"

  # e2e-qa-04: clearing a previously configured model reverts that
  # agent/client to the client's own default (no "model:" line).
  Scenario: e2e-qa-04
    Given the user has already run "/antz-set-model --agent orchestrator --model opus" in a Claude Code session
    When the user, in that same Claude Code session, runs "/antz-set-model --agent orchestrator --clear"
    Then "~/.claude/agents/antz-orchestrator.md" contains no "model:" line

  # e2e-qa-05: a later install.sh run (e.g. to pick up a version update)
  # silently reverts a configured model, since install.sh's own rendering
  # has no concept of "model:" -- an accepted, documented interaction -- but
  # leaves the "/antz-set-model" command itself installed and usable.
  Scenario: e2e-qa-05
    Given the user has already run "/antz-set-model --agent coder --model opus" in a Claude Code session
    When the user runs "./install.sh --claude" again
    Then "~/.claude/agents/antz-coder.md" contains no "model:" line
    And "~/.claude/commands/antz-set-model.md" is still installed

  # e2e-qa-06: re-invoking the command after such a revert restores the
  # configuration.
  Scenario: e2e-qa-06
    Given the user has already run "/antz-set-model --agent coder --model opus" in a Claude Code session
    And the user has already run "./install.sh --claude" again, reverting it
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder --model opus" again
    Then "~/.claude/agents/antz-coder.md" contains the line "model: opus"

  # e2e-qa-07: invoking the command for an agent that isn't installed for
  # that client yet (e.g. its file was manually removed after install)
  # fails clearly instead of creating a partial file. Note: it is not
  # possible to hit this via "install never ran at all" -- /antz-set-model
  # itself would not be an available command in that case, since install.sh
  # installs it together with the four role agents in the same run.
  Scenario: e2e-qa-07
    Given "~/.claude/agents/antz-coder.md" was manually deleted after install
    When the user, in a Claude Code session, runs "/antz-set-model --agent coder --model opus"
    Then the reply explains that "coder" must be installed for "claude" first
    And no file is created at "~/.claude/agents/antz-coder.md"

  # e2e-qa-08..16 were added by `set-model-interactive-picker` (all tagged
  # ADD) and continue the id series from 08; e2e-qa-01..07 above remain
  # valid unchanged — every invocation there passes explicit flags, so it
  # never reaches the picker.

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

## Out of scope
- Any change to `agents/prompts/*.prompt` (role instructions/behavior).
- Any change to the `access` field or its client-specific mapping functions.
- A shippable per-agent default model checked into `agents/meta/*.yaml`.
- Format validation or cross-client translation of a supplied model value.
- Gracefully handling an invoking session/agent/mode that itself lacks
  edit/write capability — the command's failure in that case is whatever the
  client's own tool-permission error surfaces, not something this command
  detects or messages specially.
- A standalone, headless/CI-invokable script as an alternative or fallback
  to the client-native command — no such script exists in this domain.
- A `--all`-style affordance that would apply one value to both clients at
  once from a single invocation -- the two clients never share a valid
  value (see Shared contracts above), and each command copy is scoped to
  one client by construction.
- Making a configured model survive a later `install.sh` run automatically
  — explicitly accepted as unsupported (see Invariants above).

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/install.sh` — `set_model_script`
  and `render_set_model_command` (added by `set-model-native-command`)
  define the embedded, self-contained POSIX sh editing logic and the
  per-client command-file rendering; `install_file` and the `MARKER`
  constant provide the same backup-if-unmanaged convention used for every
  other installed file; the `--claude`/`--opencode`/flag-less install paths
  each call `render_set_model_command` alongside the existing role-agent and
  `/antz` installation.
- `/home/edezacas/Projects/edezacas/antz/tests/set-model-command_test.sh` —
  self-contained bash test harness, one test per scenario/example-row above,
  tagged with scenario ids in each test's reported name.
