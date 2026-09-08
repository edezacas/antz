# Changelog

All notable changes to the antz agent definitions (`agents/prompts/`, `agents/meta/`) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/): patch for
non-behavioral wording tweaks, minor for behavior changes, major for breaking
changes to the workflow contract (directory layout, access model, etc).

## [0.4.0] - 2026-09-08

### Changed
- Coder now tags every test's name with its scenario's `<feature>-<index>` id (not just a comment), writes an explicit `skip`/`pending` stub for a scenario it won't automate instead of omitting it silently, and checks for already-passing/skipped tests before planning so a resumed session doesn't redo finished work.
- When coder refuses or escalates a sub-spec instead of finishing it, it now leaves a stub reasoned `BLOCKED: <why>` (scenario-scoped, or tagged with the sub-spec's first scenario id if refused at the planning stage) instead of leaving no trace on disk.

## [0.3.0] - 2026-09-08

### Changed
- Specifier now prefixes sub-spec filenames with a numeric dependency-order index (`01-api.feature`, `02-client.feature`, ...), so implementation order is readable from a plain directory listing without a separate ordering file.

## [0.2.0] - 2026-09-08

### Added
- Coder and verifier now refuse to run against the wrong workflow state instead of silently proceeding: missing `spdd/changes/<change-slug>/`, a sub-spec not found in it, an unresolved `OPEN_QUESTIONS.md`, or (verifier only) a sub-spec with no coder implementation yet all produce an explicit stop-and-report instead of best-effort work.

## [0.1.0] - 2026-09-08

### Added
- Three-role SPDD workflow: `specifier`, `coder`, `verifier` agent prompts and metadata.
- `OPEN_QUESTIONS.md` convention: its presence at `spdd/changes/<slug>/OPEN_QUESTIONS.md` blocks the coder until the specifier resolves and removes it.
- `install.sh` renders `agents/prompts/` + `agents/meta/` into Claude Code and OpenCode native subagent files, installed globally with an `antz-` name prefix to avoid collisions.
