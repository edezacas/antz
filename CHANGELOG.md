# Changelog

All notable changes to the antz agent definitions (`agents/prompts/`, `agents/meta/`) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/): patch for
non-behavioral wording tweaks, minor for behavior changes, major for breaking
changes to the workflow contract (directory layout, access model, etc).

## [1.0.0] - 2026-09-08

### Added
- Fourth role, `orchestrator` (`agents/prompts/orchestrator.prompt`, `agents/meta/orchestrator.yaml`), sequencing `specifier -> coder -> verifier` for one change. Its entire Process is a stateless reconciliation routine: every invocation reconstructs the full picture from `spdd/` alone (numbered sub-spec filenames, scenario-id test tags, `BLOCKED:` stubs, `REJECTED.md` entry count — see the `0.3.0`-`0.5.0` entries above) and takes the one next action needed, so it can resume after any interruption with no memory of what it already did.

### Changed
- `access` gains a third value, `orchestrateonly` (readonly plus a delegation capability), used only by `orchestrator`. This breaks the previously-documented binary `readonly`/`readwrite` access contract, hence the major bump — `specifier`, `coder`, and `verifier` keep their existing `readonly`/`readwrite` access unchanged.

### Known Limitations
- On Claude Code, the orchestrator's delegation to `specifier`/`coder`/`verifier` is scoped by a prompt-level rule ("What you don't do"), not by the tool grant — see `CLAUDE.md` Gotchas.

## [0.5.0] - 2026-09-08

### Added
- Verifier now appends one numbered entry to `spdd/changes/<change-slug>/REJECTED.md` on each rejection (never overwriting), recording the reported blockers and, per blocker, the sub-spec it traces to or an explicit note that it doesn't trace to a single sub-spec.

### Changed
- Verifier's Input Rule now supports a whole-change invocation form: when invoked without a named sub-spec, it verifies every sub-spec with code present instead of stopping, flagging any unimplemented sub-specs in the report.

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
