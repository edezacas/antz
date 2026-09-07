# antz

## Overview
`antz` defines a three-role, spec-driven development (SPDD) workflow as a set of Claude Code subagents: **specifier** writes behavior specs, **coder** implements one sub-spec at a time, **verifier** validates and merges. No application code lives here yet — this repo *is* the agent definitions.

## Stack
- Plain Markdown with YAML frontmatter (Claude Code subagent format: `name`, `description`, `tools`).
- No build system, package manager, or runtime — nothing to compile or install.

## Structure
- `agents/specifier.md` — turns a natural-language request into Gherkin sub-specs + an e2e QA suite under `spdd/changes/<slug>/`. Read-only tools (Read/Grep/Glob/Bash).
- `agents/coder.md` — implements exactly one sub-spec from `spdd/changes/`. Read/Grep/Glob/Bash/Edit/Write.
- `agents/verifier.md` — checks the coder's work against the sub-spec's Gherkin scenarios, then merges into `spdd/specs/` and archives to `spdd/archive/`. Read-only tools.
- `spdd/{changes,specs,archive}/` — not present yet; created on first run of the workflow (specifier creates `spdd/changes/<slug>/`; verifier creates/updates `spdd/specs/` and `spdd/archive/`).

## Gotchas
- Strict directory ownership: coder only reads `spdd/changes/` and must never touch `spdd/specs/` or `spdd/archive/`; verifier merges into specs and archives changes, but never overwrites a domain spec file wholesale (merge scenario-by-scenario, ADD/MODIFY/REMOVE).
- coder handles exactly one sub-spec per session — if handed a full multi-layer plan, it's supposed to refuse and ask for a single sub-spec.
- This is a distinct, standalone three-role split (specifier/coder/verifier), separate from this Claude Code installation's own `spdd-canvas`/`spdd-design`/`spdd-implement`/`spdd-verify` skills — don't conflate the two; the skills are a different (5-phase) pipeline that isn't defined by this repo.

## Claude Code Integration
- Files under `agents/` are Claude Code subagent definitions, invoked via the `Agent` tool with `subagent_type` matching the `name` field in frontmatter (e.g. `specifier`, `coder`, `verifier`).
- Each subagent's `tools:` frontmatter line is an allowlist — specifier and verifier are read-only (no Edit/Write); only coder can modify files.
