# antz

Spec-driven development workflow (specifier / coder / verifier) as portable agent definitions, plus an `orchestrator` role that sequences the three for one change and is the recommended entry point via `/antz`. See `CLAUDE.md` / `AGENTS.md` for the workflow itself, and `docs/orchestrator.md` for the design reasoning behind the orchestrator and its conventions.

Installed agent names are prefixed (`antz-specifier`, `antz-coder`, `antz-verifier`, `antz-orchestrator`) to avoid colliding with other agents you may already have.

## Why

AI coding agents are good at writing code and bad at remembering what the system is *supposed* to do. Without a persistent spec, intent gets re-derived from scratch every session, ambiguity surfaces after the code is written instead of before, and a small feature can quietly change behavior nobody meant to touch.

antz addresses that with:
- **Clarity before code** — `specifier` turns a request into concrete Gherkin scenarios before any code is written. A genuine ambiguity blocks implementation (`OPEN_QUESTIONS.md`) instead of getting guessed away.
- **Specs that persist** — `verifier` merges each shipped scenario into `spdd/specs/<domain>.md`, so the next session reads what the system actually does instead of re-deriving it from code or chat history.
- **Work split by dependency** — `specifier` breaks a feature into sub-specs that are each independently implementable and verifiable, ordered so dependencies come first.
- **Guarded automation** — the `orchestrator` runs specifier -> coder -> verifier end to end, but stops and reports whenever something needs a human call: an ambiguous change, an open question, a stuck sub-spec, or a rejection that doesn't trace back to a single sub-spec.

## Usage

Run `/antz <your request>` in Claude Code or OpenCode after installing. It delegates to `antz-orchestrator`, which sequences `specifier -> coder -> verifier` for one change, picking up correctly even if interrupted and resumed later. The three underlying roles remain directly invokable for manual/expert use.

## Agent Compatibility

Currently compatible with:
- Claude Code
- OpenCode

## Install

Renders the agent definitions under `agents/prompts/` + `agents/meta/` into native subagent files for whichever of Claude Code / OpenCode are detected, and installs them into that client's global agents directory (`~/.claude/agents/`, `~/.config/opencode/agents/`).

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh
```

Or, from a local checkout:

```sh
./install.sh            # auto-detect installed clients
./install.sh --claude    # force Claude Code only
./install.sh --opencode  # force OpenCode only
./install.sh --all       # force both
```

Re-running is safe: files this script generated are marked and get overwritten in place; a pre-existing, unrelated agent file with the same name is backed up (`<file>.bak.<timestamp>`) instead of being silently overwritten.

## Updating

```sh
./install.sh --check   # report whether an update is available, and what changed
./install.sh           # install it (re-run with the same flags you used before)
```

Each install embeds its `VERSION`; re-running reports the version jump and the relevant `CHANGELOG.md` entries.

Without a local checkout, run the same check remotely:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh -s -- --check
```

Or just fetch the current published version number:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/VERSION
```

## License

Code in this repository is licensed under [Apache-2.0](LICENSE)
