# antz

Three-role spec-driven development workflow (specifier / coder / verifier) as portable agent definitions. See `CLAUDE.md` / `AGENTS.md` for the workflow itself.

Installed agent names are prefixed (`antz-specifier`, `antz-coder`, `antz-verifier`) to avoid colliding with other agents you may already have.

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
