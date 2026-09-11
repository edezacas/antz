# Change: skills-activation

## Goal

Fix the reported defect: installed antz agents never detect, activate, or
execute available skills. Exercised live in an Angular project: the antz-coder
session never loads the available `angular-conventions` skill before writing
Angular code (and similarly for any skill, and for the verifier's reviews),
including inside orchestrated `/antz` flows.

Root cause is twofold, both confirmed by reading the real files:

1. **No prompt awareness.** Not one of `agents/prompts/*.prompt`,
   `agents/meta/*.yaml`, `install.sh`, or any installed copy contains the
   string "skill" (verified by grep across all of them). The roles have no
   instruction to look for skills and no activation duty tied to what they
   are about to write or review.
2. **No Claude Code capability.** `install.sh`'s `claude_tools_for_access`
   renders `tools: Read, Grep, Glob, Bash, Edit, Write` for `readwrite` — the
   `Skill` tool is absent. On Claude Code, a subagent with an explicit
   `tools:` list can only invoke listed tools, so even a willing antz
   subagent could never call the Skill tool (framework docs are explicit:
   "If you also pass an explicit tools list, include `Skill` in that list so
   Claude can invoke skills" — code.claude.com/docs/en/agent-sdk/skills and
   /docs/en/sub-agents).

On OpenCode the capability already exists: the native skill tool is granted
to custom agents by default (no `tools: skill: false` and no
`permission.skill` deny in the rendered frontmatter or the user's
`~/.config/opencode/opencode.json`), so OpenCode's gap is layer 1 only.
This asymmetry justifies a render-side fix despite one neutral
`.prompt`/`.yaml` pair: the per-client mapping in `install.sh` is already
the sanctioned place where the two clients differ.

## Gentle-ai reconciliation (adopted vs. rejected)

The working pattern from `/home/edezacas/Projects/gentle-ai` (verified in
its `internal/assets/*/sdd-orchestrator.md` rendered assets and
`docs/skill-registry.md`) was reconciled against antz's constraints
(one neutral prompt pair, orchestrator delegate-only, all cross-role state
on disk, no invented CLI):

**Adopted (adapted):**
- **Pre-resolved delegation block** — every orchestrator role delegation
  carries a `## Skills to load before work` block with absolute SKILL.md
  paths, read in full by the delegated session ("paths, not summaries;
  SKILL.md is the runtime contract"). Adapted: antz has no persistent
  registry to read it from, so the orchestrator derives the listing
  statelessly at delegation time from the standard discovery directories
  (embedded-POSIX-sh convention, like `antz-flow.sh` and the status probe).
- **Mechanical, capped matching** — triggered by code context
  (extensions/paths) and task context (implementation/review/testing), best
  5 matches, deterministic alphabetical tie-break.
- **Resolution reporting** — the role's own Output report states which
  skills were activated by name, or that none matched. Adopted from
  gentle-ai's `skill_resolution` envelope, simplified (see rejections).
- Keep the native `Skill` tool grant on Claude readwrite (03-render) and
  the directory-read discovery fallback (01-prompts): the gentle-ai
  registry exists precisely because prolonged machinery lacks skill
  awareness; antz can get the tool granted and instruct the fallback, and
  bless both paths.

**Rejected:**
- **Persistent registry file** (`spdd/skill-registry.md` or equivalent) —
  antz has no binary, hooks, or plugin to refresh it, so it goes stale
  silently; per-delegation derivation replaces freshness maintenance
  entirely and matches the Governing rule (state on disk by the role that
  owns it, derived not cached).
- **Refresh automation at install time** (settings.json
  `UserPromptSubmit` hooks, OpenCode load-time plugins) — `install.sh` is a
  pure renderer; mutating user configuration is an unannounced side effect
  and antz-idiomatic antithesis.
- **Hardcoded per-agent skill instances** ("read
  `~/.claude/skills/<name>/SKILL.md`" baked into definitions) — antz roles
  are generic; the mechanism is specced, never instances.
- **`skill_resolution` status vocabulary as a routing input** — gentle-ai
  gates phases on the field; antz's orchestrator routes on disk state only.
  The adoption is a mandatory report line for transparency (prompts-06),
  never a state-machine input.

## Contract

- `agents/prompts/coder.prompt` and `agents/prompts/verifier.prompt` gain
  framework-neutral `## Skills` sections: discover before planning /
  verifying; activate every skill whose description matches the work
  (activation = read the full SKILL.md); honor pre-resolved delegation
  paths first; report the activated names (or "none") in the Output
  report. `agents/prompts/orchestrator.prompt` gains the
  pre-resolved-delegation-block duty (02-orchestrator, all role
  delegations, explicit none-matched line, nothing written to disk).
  The specifier prompt stays byte-for-byte unchanged.
- Mechanism-level enablement is unchanged: the Claude `readwrite` mapping
  gains `Skill`; the `readonly`/`orchestrateonly` mappings and the entire
  OpenCode render stay byte-for-byte unchanged.
- Docs: AGENTS.md and CLAUDE.md gain the identical skills-activation gotcha
  (including the adoption/rejection register and the delegation-block
  description), and the Client Integration readwrite bullet is corrected.
- Versioning: touches `agents/prompts/` and `install.sh` → tracked-path
  bump, **minor** → `VERSION` 4.2.0, matching `[4.2.0]` CHANGELOG entry.

## Sub-specs (dependency order)

| File | Feature | Scenarios |
|---|---|---|
| `01-prompts.feature` | prompts | prompts-01..07, e2e-prompts-01, e2e-prompts-02 |
| `02-orchestrator.feature` | orchestrator | orchestrator-01..04 |
| `03-render.feature` | render | render-01..04, e2e-render-01 |
| `04-docs.feature` | docs | docs-01..04, e2e-docs-01 |
| `05-bump.feature` | bump | bump-01, bump-02, e2e-bump-01 |

Each numbered file carries its own e2e QA suite in the same file (`e2e-*`
ids; SKIP stubs at unit level; verified live by the verifier). Dependency
order: `01` (the prompt duties) and `03` (the grant) are independent;
`02-orchestrator` composes on the preamble convention of the orchestrator
prompt; `04-docs` documents all three; `05-bump` artifacts consume the
final shape.

Against `spdd/specs/`: `render-01` (the readwrite tools string) and
`docs-03` (the Client Integration readwrite bullet) are MODIFY of
`spdd/specs/access-model.md`; everything else is ADD — no existing spec
domain covers role skills behavior, delegated skills blocks, or the
adoption/rejection register.

## Invariants

- One neutral `agents/prompts/<name>.prompt` + `agents/meta/<name>.yaml`
  pair per role, rendered into both clients; no client-specific syntax in
  any prompt body; the clients' divergence lives only in install.sh's
  existing per-client mapping.
- Access model intact: no new level; `readonly`/`orchestrateonly` mappings
  unmodified; marker format unchanged; renders deterministic from (prompt
  body, meta access, source VERSION).
- Governing rule intact: the delegation block is derived from disk at
  delegation time (never from a role's conversational report, never cached
  across changes); the roles' `skills` report line is transparency, not a
  routing input.
- Safety boundary intact: prompt-level path ownership per role,
  never-commits law untouched; the orchestrator writes nothing under
  `spdd/` and reads/follows no SKILL.md itself.
- Activated matching is keyed to each skill's own `description` (including
  its trigger language) — never to a hardcoded skill list.
- OpenCode keeps its native skill tool; antz adds or masks no per-agent
  skill permission there; user global permission intent is respected.
- No persistent registry, no refresh hooks/plugins/CLI anywhere; antz
  installs files, never mutates user configuration.
- After this change ships, `./install.sh --check` reports the drift to
  4.2.0; reinstalling overwrites the installed copies; no user
  hand-editing is ever required.

## Out of scope

- `agents/prompts/specifier.prompt` body (byte-for-byte guard, prompts-05).
- A persistent skill registry file; refresh automation of any kind
  (hooks, plugins, CLI refresh commands); install-time configuration
  mutation.
- `skill_resolution` status vocabulary as a contract field or routing
  input; cap/orchestration machinery beyond the 5-best-match block.
- Preloading skills by name (Claude `skills:` preloaded frontmatter field)
  or any embedded catalog of known skills.
- Authoring or editing any skill itself; per-role skill tools changes
  beyond render-01; the `worktree` branch variant and its historical docs.

## Relevant files

- `agents/prompts/coder.prompt`, `agents/prompts/verifier.prompt` — new
  `## Skills` sections (prompts-01..04, 06, 07) and `## Output` report
  line (prompts-06).
- `agents/prompts/orchestrator.prompt:133-138` — delegation preamble gains
  the "## Skills to load before work" block (orchestrator-01..04).
- `agents/prompts/specifier.prompt` — byte-for-byte guard.
- `install.sh:102-109` — `claude_tools_for_access` (`readwrite` branch
  gains `, Skill`; render-01, render-02); OpenCode render functions
  unchanged (render-03).
- `AGENTS.md`, `CLAUDE.md` — the new gotcha (docs-01, docs-02, docs-04)
  and the Client Integration bullets (docs-03).
- `VERSION`, `CHANGELOG.md` — the 4.2.0 bump (bump-01..02).
- `tests/access-model_test.sh` — the one-test-per-scenario-id harness
  pattern; `tests/installsh-posixsh_test.sh` — install.sh render test
  harness pattern.
- `spdd/specs/access-model.md` — the domain receiving the render/docs
  merges (MODIFY; verifier merges there, never overwrites).
- `/home/edezacas/Projects/gentle-ai/internal/assets/*/sdd-orchestrator.md`,
  `docs/skill-registry.md` — the pattern source, read-only reference.
