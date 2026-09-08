# Domain: set-model

## Origin
- Specced and delivered from change `set-model-native-command` as
  `/antz-set-model`, a client-native command installed by `install.sh`
  alongside the four role agents and `/antz`, for both Claude Code and
  OpenCode. Every scenario in this file reflects that command-based
  delivery. The change's scenarios and end-to-end QA are preserved for
  history in `spdd/archive/set-model-native-command/`, not reproduced here.

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
delivered to the command as `$ARGUMENTS`):
```
/antz-set-model --agent <specifier|coder|verifier|orchestrator> (--model <value>|--clear)
```
- `--agent` is required and must name one of the four role agents.
- Exactly one of `--model <value>` / `--clear` is required (never zero,
  never both).
- No client flag exists in this contract (see Client binding above).
- A no-argument or interactive follow-up flow (asking the user for missing
  fields turn by turn) is out of scope (see Out of scope).

**Model value contract** — for a given agent and the one client a given
command copy targets, either:
- *absent* — no `model:` line (the default until a user explicitly
  configures one), or
- a *non-empty string* — the exact value supplied to `--model`, written
  **verbatim** into that file's `model:` line. Never validated or translated
  against the target client's syntax; the user is responsible for supplying
  a value valid for the client they targeted.

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
  target file isn't antz-managed; unknown agent name; neither/both of
  `--model`/`--clear` given) and confirmation that no file was written.

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

  # command-install-01: install.sh installs the Claude Code copy with the
  # expected frontmatter shape, mirroring how it already installs /antz.
  Scenario: command-install-01
    Given a clean "~/.claude/commands" directory
    When the user runs "./install.sh --claude"
    Then "~/.claude/commands/antz-set-model.md" is created
    And its frontmatter contains the "antz:generated" marker with the current install.sh version
    And its frontmatter contains a "description:" field describing the command's purpose
    And its frontmatter contains "argument-hint: --agent <specifier|coder|verifier|orchestrator> (--model <value>|--clear)"
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

  # set-model-cmd-09: exactly one of --model/--clear is required.
  Scenario Outline: set-model-cmd-09
    When the installed "claude" copy of "/antz-set-model" is invoked with "--agent coder <extra-args>"
    Then the command's reply is a usage error
    And no file is written

    Examples:
      | extra-args              |
      |                         |
      | --model opus --clear    |

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
native command, not an internal API call).

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

## Out of scope
- Any change to `agents/prompts/*.prompt` (role instructions/behavior).
- Any change to the `access` field or its client-specific mapping functions.
- A shippable per-agent default model checked into `agents/meta/*.yaml`.
- Format validation or cross-client translation of a supplied model value.
- A no-argument, conversational/interactive fallback that asks follow-up
  questions when arguments are omitted or incomplete — the command requires
  explicit flags in `$ARGUMENTS` for deterministic, testable behavior.
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
