# antz

## Overview
`antz` defines a three-role, spec-driven development (SPDD) workflow as agent prompt definitions: **specifier** writes behavior specs, **coder** implements one sub-spec at a time, **verifier** validates and merges. No application code lives here yet — this repo *is* the agent definitions, kept independent of any one agent framework's frontmatter format.

## Stack
- Prompt bodies and metadata are split so the same definitions can target multiple agent frameworks: plain text prompt files, plus small YAML metadata files (`name`, `description`, `access`).
- No build system, package manager, or runtime — nothing to compile. `install.sh` (POSIX `sh`, runnable via `curl | sh`) renders these into each detected framework's native subagent file and installs it globally (`~/.claude/agents/`, `~/.config/opencode/agents/`).

## Structure
- `agents/prompts/{specifier,coder,verifier}.prompt` — the role instructions verbatim, with no framework-specific syntax.
- `agents/meta/{specifier,coder,verifier}.yaml` — `name`, `description`, and `access` (`readonly`/`readwrite`) per role. `access` is what a framework-specific generator maps onto that framework's own tool/permission model.
- `spdd/{changes,specs,archive}/` — not present yet; created on first run of the workflow (specifier creates `spdd/changes/<slug>/`; verifier creates/updates `spdd/specs/` and `spdd/archive/`).

## Gotchas
- Strict directory ownership: the coder role only reads `spdd/changes/` and must never touch `spdd/specs/` or `spdd/archive/`; the verifier role merges into specs and archives changes, but never overwrites a domain spec file wholesale (merge scenario-by-scenario, ADD/MODIFY/REMOVE).
- The coder role handles exactly one sub-spec per session — if handed a full multi-layer plan, it's supposed to refuse and ask for a single sub-spec.
- Open questions from the specifier live at the fixed path `spdd/changes/<change-slug>/OPEN_QUESTIONS.md`. Its mere presence — not its contents — is a hard stop: the coder must not implement anything in that change while the file exists. The specifier only creates it when something is genuinely blocked, and must delete it once every question is resolved; a stale file blocks work that's no longer actually blocked.
- Installed agent names carry an `antz-` prefix (`antz-specifier`, `antz-coder`, `antz-verifier`) to avoid colliding with generically-named agents from other sources. Source files under `agents/prompts/` and `agents/meta/` keep the unprefixed role names.
