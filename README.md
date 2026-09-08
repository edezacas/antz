# antz

Three-role spec-driven development workflow (specifier / coder / verifier) as portable agent definitions. See `CLAUDE.md` / `AGENTS.md` for the workflow itself.

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
