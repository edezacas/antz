# antz

## Overview
`antz` defines a three-role, spec-driven development (SPDD) workflow: **specifier** writes behavior specs, **coder** implements one sub-spec at a time, **verifier** validates and merges. No application code lives here yet — this repo *is* the agent definitions, kept client-agnostic so they can be installed into Claude Code, OpenCode, or other agent runners.

## Stack
- Plain text/YAML, split by concern: prompt body (client-agnostic) vs. metadata (name/description/access), rendered by `install.sh` into each client's native frontmatter.
- No build system, package manager, or runtime — nothing to compile. `install.sh` is a POSIX `sh` script (works via `curl | sh`, no bash-only syntax).

## Structure
- `agents/prompts/{specifier,coder,verifier}.prompt` — the role instructions verbatim (no frontmatter, no client-specific syntax). This is the single source of truth for behavior.
- `agents/meta/{specifier,coder,verifier}.yaml` — `name`, `description`, `access` (`readonly` or `readwrite`) per role. `access` is the abstract capability a generator maps to each client's tool/permission model (e.g. Claude Code `tools:` list, OpenCode `permission:` block + `mode`).
- `spdd/{changes,specs,archive}/` — not present yet; created on first run of the workflow (specifier creates `spdd/changes/<slug>/`; verifier creates/updates `spdd/specs/` and `spdd/archive/`).

## Gotchas
- Strict directory ownership: coder only reads `spdd/changes/` and must never touch `spdd/specs/` or `spdd/archive/`; verifier merges into specs and archives changes, but never overwrites a domain spec file wholesale (merge scenario-by-scenario, ADD/MODIFY/REMOVE).
- Open questions from the specifier live at the fixed path `spdd/changes/<change-slug>/OPEN_QUESTIONS.md`. Its mere presence — not its contents — is a hard stop: the coder must not implement anything in that change while the file exists. The specifier only creates it when something is genuinely blocked, and must delete it once every question is resolved; a stale file blocks work that's no longer actually blocked.
- coder handles exactly one sub-spec per session — if handed a full multi-layer plan, it's supposed to refuse and ask for a single sub-spec.
- `specifier`/`verifier` are `access: readonly` (no edit/write capability); `coder` is `access: readwrite` (the only role that modifies files). Keep this mapping in mind when generating client-specific frontmatter — it's the safety boundary the whole workflow depends on.

## Client Integration
- Neither `agents/prompts/` nor `agents/meta/` is itself a Claude Code or OpenCode subagent file — `install.sh` renders each `<name>.prompt` + `<name>.yaml` pair into the frontmatter each client needs (Claude Code: `name`/`description`/`tools:`; OpenCode: `description`/`mode`/`permission:`) and installs to that client's global agents directory. `access: readonly` maps to no edit/write capability; `access: readwrite` maps to full edit access — see `install.sh` for the exact mapping.
- Files `install.sh` writes carry an `antz:generated` marker comment inside the frontmatter; re-running it overwrites those in place but backs up (`.bak.<timestamp>`) any pre-existing file with the same name that lacks the marker, rather than clobbering it.
- `install.sh` works both from a local checkout (reads `agents/` directly) and via `curl | sh` (fetches from `RAW_BASE` in the script, currently GitHub `master`) — keep that URL in sync if the default branch or repo location changes.
- Installed agent names carry an `antz-` prefix (`antz-specifier`, `antz-coder`, `antz-verifier`, set via `name:` in `agents/meta/*.yaml`) — deliberately, so they don't collide with a user's own or another package's generically-named `specifier`/`coder`/`verifier` agents. Source files under `agents/prompts/` and `agents/meta/` keep the unprefixed role names; only the rendered/installed name is prefixed.
