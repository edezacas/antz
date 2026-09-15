# Law notes

Supplementary detail for `AGENTS.md`. The policy docs state the law; this file
holds the exact enumerations and the design reasoning that would otherwise
bloat them. Where the reasoning is already owned by a spec or a prompt, this
file points there instead of restating it.

## Skills discovery

Discovery belongs to the client: the specifier, coder, and verifier use their
session's skill-listing capability, so neither the prompts nor the orchestrator
keep a skills path list, and no skills list is ever passed in a delegation
message. Matching is always by each skill's own description, never by name, and
activation means reading the matched `SKILL.md` in full. antz adds no skill
mechanism of its own — no registry file, no enumeration script, no refresh
hook, plugin, or CLI — and `install.sh` never mutates user configuration for
this.

## `/antz` client mechanism

`/antz` installs to `~/.claude/commands/antz.md`,
`~/.config/opencode/commands/antz.md`, and `~/.pi/agent/prompts/antz.md`. On
Claude Code the command body runs in the main session (which already has the
`Agent` tool) and explicitly delegates the request to the `antz-orchestrator`
subagent. On OpenCode the command's `agent: antz-orchestrator` frontmatter
(with no `subtask`) switches the session to that `mode: primary` agent natively
instead of spawning it as a nested subagent. On Pi the command is a prompt
template that also runs in the main session and delegates through the
pi-subagents `subagent` tool: `antz-orchestrator`'s Pi frontmatter names
`edit`/`write` and `subagent` in its strict `tools:` allowlist. The writer
tools are pass-through grants, not authority — pi-subagents intersects a
child's tool plan with the delegating session's *available* builtins, so a
readonly orchestrator would silently strip `edit`/`write` from the
`specifier`/`coder`/`verifier` it spawns (they would fall back to writing
through `bash`). The "never writes anything itself" rule stays prompt-level,
the same accepted boundary Claude Code's unscoped `Agent` grant relies on.

## Pi subagent shape

Pi defines a subagent as a markdown file at `~/.pi/agent/agents/<name>.md` with
YAML frontmatter, and a slash command as a prompt template at
`~/.pi/agent/prompts/<name>.md` (`$ARGUMENTS` is the injection point). Tool
names are lowercase (`read`, `grep`, `find`, `ls`, `bash`, `edit`, `write`),
and the delegation tool is `subagent` (pi-subagents). Custom agents start from
a clean system prompt by default, so antz's Pi renders opt into
`inheritProjectContext: true` (the target repo's `AGENTS.md`/`CLAUDE.md`) and
`inheritSkills: true` for the readwrite roles (the roles' `## Skills` sections
read the client's own catalog; without it the catalog is a silent no-op).
`defaultContext: fresh` keeps the roles' disk-derived-state law intact, and
`systemPromptMode: replace` makes the role prompt the whole system prompt.

## Claude Code delegation asymmetry (accepted limitation)

A subagent's `tools:` list is a strict, enforced allowlist, so the `Skill`
grant is real. But the parenthesized `Agent(name, ...)` form only scopes
spawning for an agent running as the main thread via `claude --agent`; it is
silently ignored for a subagent. `antz-orchestrator` is always a subagent
(invoked via `/antz` or auto-delegation), so on Claude Code staying within the
three role agents is a prompt-level instruction, not a tool-enforced boundary.
This is a known, accepted platform limitation, not a bug to fix later; a user's
`permissions.deny` in `settings.json` is the documented hard-block, but that
lives outside any file `install.sh` writes.

## Where the design reasoning lives

- Mode selection, the no-probe/no-receipt rationale, and the delegation
  contract: `docs/orchestrator.md`.
- Flow script states, layout, and the `REJECTED.md` heading:
  `spdd/specs/flow.md`.
- Rendering, the marker, and the backup policy:
  `spdd/specs/install-render.md`.
- Versioning and the single-source policy file: `spdd/specs/versioning.md`.
- The suite's runner and laws: `spdd/specs/test-runner.md`.
- Per-release history: `CHANGELOG.md`.
