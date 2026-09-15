# Law notes

Supplementary detail for `AGENTS.md` / `CLAUDE.md`. The policy docs state the law; this file holds the exact enumerations and the design reasoning that would otherwise bloat them. Where the reasoning is already owned by a spec, a prompt, or the changelog, this file points there instead of restating it.

## Skills discovery

Discovery belongs to the client: the specifier, coder, and verifier use their session's skill-listing capability, so neither the prompts nor the orchestrator keep a skills path list. Matching is always by each skill's own description, never by name, and activation means reading the matched `SKILL.md` in full. antz adds no skill mechanism of its own — no delegation block, no enumeration script, no registry file, no refresh hook, plugin, or CLI — and `install.sh` never mutates user configuration for this.

## `/antz` client mechanism

`/antz` installs to `~/.claude/commands/antz.md`, `~/.config/opencode/commands/antz.md`, and `~/.pi/agent/prompts/antz.md`. On Claude Code the command body runs in the main session (which already has the `Agent` tool) and explicitly delegates the request to the `antz-orchestrator` subagent. On OpenCode the command's `agent: antz-orchestrator` frontmatter (with no `subtask`) switches the session to that `mode: primary` agent natively instead of spawning it as a nested subagent. On Pi the command is a prompt template that also runs in the main session and delegates through the pi-subagents `subagent` tool: `antz-orchestrator`'s Pi frontmatter names `subagent` in its strict `tools:` allowlist, which is what authorizes nested delegation there.

## Pi subagent shape

Pi defines a subagent as a markdown file at `~/.pi/agent/agents/<name>.md` with YAML frontmatter, and a slash command as a prompt template at `~/.pi/agent/prompts/<name>.md` (`$ARGUMENTS` is the injection point). Tool names are lowercase (`read`, `grep`, `find`, `ls`, `bash`, `edit`, `write`), and the delegation tool is `subagent` (pi-subagents). Custom agents start from a clean system prompt by default, so antz's Pi renders opt into `inheritProjectContext: true` (the target repo's `AGENTS.md`/`CLAUDE.md`) and `inheritSkills: true` for the readwrite roles (the roles' `## Skills` sections read the client's own catalog; without it the catalog is a silent no-op). `defaultContext: fresh` keeps the roles' disk-derived-state law intact, and `systemPromptMode: replace` makes the role prompt the whole system prompt.

## Claude Code delegation asymmetry (accepted limitation)

A subagent's `tools:` list is a strict, enforced allowlist, so the `Skill` grant is real. But the parenthesized `Agent(name, ...)` form only scopes spawning for an agent running as the main thread via `claude --agent`; it is silently ignored for a subagent. `antz-orchestrator` is always a subagent (invoked via `/antz` or auto-delegation), so on Claude Code staying within the three role agents is a prompt-level instruction, not a tool-enforced boundary. This is a known, accepted platform limitation, not a bug to fix later; a user's `permissions.deny` in `settings.json` is the documented hard-block, but that lives outside any file `install.sh` writes.

## Where the design reasoning lives

- Orchestrator sequencing, the `REJECTED.md` retry bound, the `BLOCKED:` colon, and the platform delegation scoping: `docs/orchestrator.md`.
- Access model and write surfaces: `spdd/specs/access-model.md`, `spdd/specs/role-surfaces.md`.
- Branch-marked flow, slug rules, and `ensure` states: `spdd/specs/flow-branch.md`.
- Receipts, classification, and the closing block: `spdd/specs/receipts.md`.
- Skills activation: `spdd/specs/skills-activation.md`.
- Versioning and why `install.sh` is tracked: `spdd/specs/versioning.md`.
- Per-release history, the no-commit migration, and the de-embed migration: `CHANGELOG.md`.
