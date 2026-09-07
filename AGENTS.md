# antz

## Overview
`antz` defines a three-role, spec-driven development (SPDD) workflow as agent prompt definitions: **specifier** writes behavior specs, **coder** implements one sub-spec at a time, **verifier** validates and merges. No application code lives here yet — this repo *is* the agent definitions.

## Stack
- Plain Markdown with YAML frontmatter (`name`, `description`, `tools`) describing each agent's role and allowed tools.
- No build system, package manager, or runtime — nothing to compile or install.

## Structure
- `agents/specifier.md` — turns a natural-language request into Gherkin sub-specs + an e2e QA suite under `spdd/changes/<slug>/`. Read-only role.
- `agents/coder.md` — implements exactly one sub-spec from `spdd/changes/`. The only role allowed to edit/write files.
- `agents/verifier.md` — checks the coder's work against the sub-spec's Gherkin scenarios, then merges into `spdd/specs/` and archives to `spdd/archive/`. Read-only role.
- `spdd/{changes,specs,archive}/` — not present yet; created on first run of the workflow (specifier creates `spdd/changes/<slug>/`; verifier creates/updates `spdd/specs/` and `spdd/archive/`).

## Gotchas
- Strict directory ownership: the coder role only reads `spdd/changes/` and must never touch `spdd/specs/` or `spdd/archive/`; the verifier role merges into specs and archives changes, but never overwrites a domain spec file wholesale (merge scenario-by-scenario, ADD/MODIFY/REMOVE).
- The coder role handles exactly one sub-spec per session — if handed a full multi-layer plan, it's supposed to refuse and ask for a single sub-spec.
- These three roles are a standalone split; if the agent framework you're running under has its own built-in spec/plan/implement/verify pipeline, treat this repo's roles as a separate, independent workflow rather than mapping them onto it.
