# Change: set-model-native-command

## Goal
The prior `configurable-agent-model` change added `set-model.sh`, a standalone
POSIX shell script the user runs directly from a terminal, separate from
`install.sh`, to configure or clear the `model:` frontmatter field of an
already-installed antz agent file. The user has since rejected that delivery
mechanism: they want the same capability exposed as a **command native to the
client itself** — a slash/native command inside Claude Code or OpenCode,
installed and invoked the same way `/antz` already is — not a script run
outside the client.

This change adds `/antz-set-model`: a command installed by `install.sh`
alongside the four role agents and `/antz`, for both Claude Code and
OpenCode, following the exact `render_*_command` / `install_file` pattern
`install.sh` already uses for `/antz`. Invoking it from inside a client edits
that client's own already-installed agent file's `model:` line in place —
the same file-editing contract `set-model.sh` already implements, just
triggered from inside the client instead of from a shell.

**Resolved scope (user decision — Option A, Replace):** `set-model.sh` and
its test suite are retired outright as part of this change, not kept
alongside the new command. `/antz-set-model` becomes the *only* way to
configure or clear an agent's model; no standalone, headless/CI-invokable
script remains after this change. `spdd/specs/set-model.md`'s existing
scenarios (all of which describe running `./set-model.sh` from a shell) are
fully superseded — see the REMOVE mapping in `01-set-model-command.feature`.

## Research: how a comparable external tool does this
Investigated `/home/edezacas/Projects/gentle-ai` per the user's request (a
separate, unrelated repo — its agent set and file layout don't transfer
literally, only the pattern). Findings:
- Its Pi integration (`docs/agents.md` "Model assignment command") exposes
  per-agent model selection through `/gentleman:models`, a **client-native
  slash command** invoked from inside Pi itself, which opens what the docs
  call "a Pi-native modal" and persists the result to `.pi/gentle-ai/models.json`
  plus per-agent overrides. This is the closest precedent to what the user is
  asking for: configuration happens as a command run inside the client, not a
  separate CLI/script the user runs outside it.
- Its OpenCode integration (`docs/opencode-profiles.md`) instead configures
  per-agent models through its own external Go CLI (`gentle-ai sync
  --profile name:provider/model`) or an interactive TUI (`gentle-ai`, a
  separate binary) — i.e. still an external tool, not a command run from
  inside OpenCode's own chat surface. Only *switching* between
  already-configured profiles happens inside OpenCode itself (pressing Tab).
- Neither Pi's "native modal" nor gentle-ai's Go TUI transfers literally:
  Claude Code and OpenCode custom commands have no modal/interactive-widget
  capability — a custom command is a markdown prompt body the invoking
  session's own model executes with its own tools, not a GUI. The applicable
  *pattern*, adapted to what these two clients actually support, is: a
  command installed into the client's own commands directory (this repo's
  `/antz` is already exactly that pattern), whose body performs the
  configuration directly using the invoking session's own tool access,
  reporting the result back as a normal reply — not a modal, and not a
  separate script the user has to run themselves outside the client.

## Sub-specs, in dependency order
1. `01-set-model-command.feature` — the entire feature: `install.sh` installs
   `/antz-set-model` for each client, invoking it edits that client's own
   already-installed agent file's `model:` line, and `set-model.sh` plus
   `tests/set-model_test.sh` are deleted as part of the same change (the
   `retire-set-model-01` scenario). Fully unblocked and fully specified: the
   `command-install-*`/`set-model-cmd-*` scenarios are tagged ADD against
   `spdd/specs/set-model.md`; `retire-set-model-01` and the REMOVE mapping
   table at the end of that file cover the retirement side.

There is no further layer split here, for the same reason the original
`set-model.sh` change didn't split further: a small, self-contained feature
with one observable behavior (parameterized by which of the two clients
installed/invoked it), not independently implementable or verifiable at a
finer grain. Deleting `set-model.sh` is part of that same atomic behavior
change (replacing one delivery mechanism with another for the same
capability), not a separable layer — it stays in this one sub-spec rather
than becoming a second, dependency-ordered file.

## Shared contracts

**Client binding (new, replaces the retired `--claude`/`--opencode` flag)** —
each installed copy of `/antz-set-model` is permanently scoped to the client
it was installed for: the Claude Code copy only ever targets
`~/.claude/agents/antz-<agent>.md` at Claude's frontmatter position
(immediately after `description:`, immediately before `tools:`); the
OpenCode copy only ever targets `~/.config/opencode/agents/antz-<agent>.md`
at OpenCode's position (immediately after `description:`, immediately before
`mode:`). The invoker never supplies a client flag or argument — which
client's copy of the command they ran already determines it. This is a
structural simplification made possible by the command now being installed
per-client (like `/antz` already is), not a value someone chose arbitrarily.

**Command argument contract** (the text typed after the slash command,
delivered to the command as `$ARGUMENTS`, preserving `set-model.sh`'s
existing, already-proven flag names for continuity):
```
/antz-set-model --agent <specifier|coder|verifier|orchestrator> (--model <value>|--clear)
```
- `--agent` is required and must name one of the four role agents.
- Exactly one of `--model <value>` / `--clear` is required (never zero,
  never both).
- No client flag exists in this contract (see Client binding above).
- A no-argument or interactive follow-up flow (asking the user for missing
  fields turn by turn) is explicitly out of scope for this change — see Out
  of scope.

**Model value contract** (unchanged from `spdd/specs/set-model.md`) — for a
given agent and the one client a given command copy targets, either:
- *absent* — no `model:` line (the default until a user explicitly
  configures one), or
- a *non-empty string* — the exact value supplied to `--model`, written
  **verbatim** into that file's `model:` line. Never validated or translated
  against the target client's syntax.

**Target file / marker contract** (unchanged) — the target file must already
exist and carry the `antz:generated` marker; otherwise the command fails
without writing anything, and explains why.

**Observable outcome contract** (new — replaces exit-code framing, since
there is no shell process visible to the user here): the command's reply is
natural language, not spec'd byte-for-byte, but must state specific,
checkable content:
- On success: which file changed and what its `model:` line now is (or that
  it was cleared).
- On failure: the specific reason (agent not installed for this client yet;
  target file isn't antz-managed; unknown agent name; neither/both of
  `--model`/`--clear` given) and confirmation that no file was written.

## Invariants
- The new command never invokes, wraps, or reimplements `install.sh`'s
  *agent*-rendering functions (`render_claude`/`render_opencode`/
  `install_file` as applied to role-agent files) — it edits an
  already-installed agent file's frontmatter directly and in place, the same
  file-editing contract `set-model.sh` already implemented.
- Only the `model:` line (added, replaced, or removed) may differ before and
  after. The marker/version comment, `name`/`description`/`tools:` (Claude
  Code) or `description`/`mode`/`permission:` (OpenCode), and the prompt
  body are always byte-for-byte preserved.
- A file this command just edited keeps carrying the `antz:generated`
  marker, so a later plain `install.sh` run still recognizes it as
  antz-managed and overwrites it in place, silently dropping any configured
  model (`install.sh`'s rendering has no concept of `model:` at all) — same
  accepted consequence already documented for the retired `set-model.sh`,
  carried over unchanged.
- `/antz-set-model` runs directly in whatever session/agent context invoked
  it (the main Claude Code session, or OpenCode's currently active agent) —
  unlike `/antz`, it never delegates to any of the four `antz-*` role
  subagents; none of the four is an appropriate owner for this ad hoc
  utility, and the invoking session already has the file-edit access needed.
  If that session's active agent/mode lacks edit capability (e.g. a
  restricted OpenCode mode), the edit fails for reasons outside this
  command's control — handling that gracefully is out of scope.
- Installing this command reuses `install.sh`'s existing `MARKER`/
  `install_file` backup-if-unmanaged convention; no new marker or backup
  mechanism is introduced.
- Per this repo's existing versioning policy, a change confined to
  `install.sh` plus deleting `set-model.sh`/`tests/set-model_test.sh` (as
  this one is) does not touch `agents/prompts/` or `agents/meta/` and so does
  not require a `VERSION`/`CHANGELOG.md` bump — `install.sh --check`'s
  version-drift report stays keyed off the specifier agent file only,
  unaffected by this command's addition or the script's removal.

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
- Keeping `set-model.sh` runnable alongside the new command for
  headless/CI/dotfiles use (the rejected Option B), or relocating/renaming it
  as a still-runnable "internal/advanced" tool (the rejected Option C) — the
  user's resolved decision is a full replacement (Option A): no standalone,
  headless way to configure a model remains after this change.

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/install.sh` — `render_claude_command`
  (line ~161) / `render_opencode_command` (line ~167) and `install_file`
  (line ~173) are the direct precedent to follow for a second command:
  same marker/version comment, same backup-if-unmanaged behavior via
  `install_file`. `render_claude`/`render_opencode` (lines ~145/~152 in the
  agent-rendering section) define the exact frontmatter shape/position
  conventions (`MARKER`, `description:`, `tools:`/`mode:`) this command's
  target files already follow and must keep preserving.
- `/home/edezacas/Projects/edezacas/antz/set-model.sh` — the existing,
  already-implemented file-editing logic (argument validation, marker check,
  `awk`-based frontmatter rewrite preserving position). Useful as reference
  for that logic while implementing `/antz-set-model` (e.g. its body may
  invoke this script's logic internally, or reimplement it fresh — an
  implementation choice, not mandated here) — but the file itself must not
  remain in the repo once this change is implemented (`retire-set-model-01`).
- `/home/edezacas/Projects/edezacas/antz/tests/set-model_test.sh` — the
  existing fixture-driven bash test harness for that logic. Same
  reference-while-implementing value as above; must also not remain in the
  repo once this change is implemented (`retire-set-model-01`).
- `/home/edezacas/Projects/edezacas/antz/spdd/specs/set-model.md` — the
  domain spec this change fully supersedes. Every scenario in it is tagged
  REMOVE — see the mapping table at the end of `01-set-model-command.feature`.
- `/home/edezacas/Projects/edezacas/antz/agents/meta/{specifier,coder,verifier,orchestrator}.yaml`
  — unaffected; no new field added for this change.

## End-to-end QA suite
See `e2e-qa.feature`. Operates through the real product UI: typing the
installed slash command inside a live Claude Code or OpenCode session, and
`install.sh`'s own CLI for setup/regression checks.
