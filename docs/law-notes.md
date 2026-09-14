# Law notes

Supplementary detail for `AGENTS.md` / `CLAUDE.md`. The policy docs state the law; this file holds the exact enumerations and the design reasoning that would otherwise bloat them. Where the reasoning is already owned by a spec, a prompt, or the changelog, this file points there instead of restating it.

## Skills directories (fallback enumeration)

When a client has no skill tool, the coder and verifier enumerate the working root's and the user's standard skills directories and read the matched `SKILL.md` in full:

- `.agents/skills/`
- `~/.agents/skills/`
- `.claude/skills/`
- `~/.claude/skills/`
- `.opencode/skills/`
- `~/.config/opencode/skills/`

Matching is always by description, never by name. A delegation's `## Skills to load before work` block is derived mechanically from those directories at delegation time (best match first, alphabetical tie-break, at most five entries), with an explicit `Skills: none matched` line when nothing matches. No registry file is kept and no refresh hook, plugin, or CLI is introduced — freshness comes from per-delegation derivation, and `install.sh` never mutates user configuration for this.

## `/antz` client mechanism

`/antz` installs to `~/.claude/commands/antz.md` and `~/.config/opencode/commands/antz.md`. On Claude Code the command body runs in the main session (which already has the `Agent` tool) and explicitly delegates the request to the `antz-orchestrator` subagent. On OpenCode the command's `agent: antz-orchestrator` frontmatter (with no `subtask`) switches the session to that `mode: primary` agent natively instead of spawning it as a nested subagent.

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
