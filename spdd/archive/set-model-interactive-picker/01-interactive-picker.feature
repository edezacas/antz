Feature: /antz-set-model offers an interactive model picker when --model/--clear are omitted
  # Layer: the rendered command body per client (one artifact, parameterized by
  # client -- see README.md for why this is not split further). Covers (a) the
  # command file install.sh renders for each client (updated argument-hint,
  # embedded alias vocabulary / enumeration instructions, pre-flight ordering),
  # (b) the command-level invocation contract (fail-fast validation, preserved
  # non-interactive bypass, the new interactive flow), and (c) the client-
  # specific option source and question mechanism. The embedded POSIX script is
  # NOT re-specced: it is unchanged in behavior; only its command-level
  # packaging changes. Scenarios are tagged ADD or MODIFY against
  # spdd/specs/set-model.md; the mapping table at the end of this file tells
  # the verifier exactly what to merge.

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
    And the embedded script inside each rendered copy is unchanged in
      behavior: it accepts "--agent <role>" with exactly one of
      "--model <value> | --clear", writes the value verbatim with no
      validation, and remains the sole authority for the file edit

  ## Command file rendering (install.sh renders the updated body)

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

  ## Scenarios modified in spdd/specs/set-model.md (MODIFY)

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

  ## Merge mapping for spdd/specs/set-model.md (for the verifier)

  # | Location in spdd/specs/set-model.md                            | Action | Superseded by / note                                                     |
  # |-----------------------------------------------------------------|--------|--------------------------------------------------------------------------|
  # | Scenario set-model-cmd-09                                        | MODIFY | Replace with the script-level Scenario Outline above (both rows keep      |
  # |                                                                  |        | their existing unit tests); command-level "neither" -> interactive        |
  # |                                                                  |        | picker (picker-cmd-08..13 + client groups), "both" -> picker-cmd-05.      |
  # | Scenario command-install-01                                      | MODIFY | Replace with the version in this file (new argument-hint, picker body).   |
  # | Shared contracts: "Exactly one of --model <value> / --clear is   | MODIFY | Becomes "at most one"; neither given -> interactive picker (see README    |
  # | required (never zero, never both)"                               |        | Command argument contract).                                               |
  # | Shared contracts: sentence "A no-argument or interactive         | REMOVE | Superseded by the Picker contract in this change's README.                |
  # | follow-up flow ... is out of scope"                              |        |                                                                           |
  # | Out of scope: bullet "A no-argument, conversational/interactive  | REMOVE | Now in scope: it is the headline behavior of this change.                 |
  # | fallback that asks follow-up questions..."                       |        |                                                                           |
  # | Goal/Origin prose                                                | MODIFY | Mention the interactive picker as a new way to PRODUCE the --model value; |
  # |                                                                  |        | the embedded script's behavior and the verbatim-value contract are        |
  # |                                                                  |        | unchanged.                                                                |
  # | set-model-cmd-01..08, set-model-cmd-10..12,                      | none   | Unchanged; all outcomes still hold (explicit-flag invocations never       |
  # | command-install-02..05, Invariants, e2e-qa-01..07                |        | trigger the picker; the script is untouched).                             |
  # | Shared contracts: Model value contract                           | none   | Unchanged in rule; extended source note: picker-sourced values follow the |
  # |                                                                  |        | same verbatim contract (see README Shared contracts).                     |

  ### Invariants
  See README.md Invariants (shared across this whole change).
