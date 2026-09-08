# Changelog

All notable changes to the antz agent definitions (`agents/prompts/`, `agents/meta/`) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/): patch for
non-behavioral wording tweaks, minor for behavior changes, major for breaking
changes to the workflow contract (directory layout, access model, etc).

## [0.1.0] - 2026-09-08

### Added
- Three-role SPDD workflow: `specifier`, `coder`, `verifier` agent prompts and metadata.
- `OPEN_QUESTIONS.md` convention: its presence at `spdd/changes/<slug>/OPEN_QUESTIONS.md` blocks the coder until the specifier resolves and removes it.
- `install.sh` renders `agents/prompts/` + `agents/meta/` into Claude Code and OpenCode native subagent files, installed globally with an `antz-` name prefix to avoid collisions.
