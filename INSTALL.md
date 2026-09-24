# Install

antz is five agents, three skills and one `/antz` command. Pick your client and
follow its adapter.

| Client | Read |
|---|---|
| pi | [adapters/pi.md](adapters/pi.md) |
| Claude Code | [adapters/claude.md](adapters/claude.md) |
| OpenCode | [adapters/opencode.md](adapters/opencode.md) |
| other | none yet — [the shipped adapters](adapters) are the spec for the next one |

What the machine needs first is in [Requirements](README.md#requirements). The
three skills are installed with `npx skills add`, which needs Node.js >= 22.20.

To have an agent do it, hand it this:

> Clone https://github.com/edezacas/antz, read `INSTALL.md`, then do what
> `adapters/<your client>.md` says.

## What goes where

| Source | What it becomes |
|---|---|
| [`agents/*.md`](agents) | the five subagents |
| [`skills/antz-*/`](skills) | the three skills, a separate global install: `npx skills add edezacas/antz -g` |
| [`prompts/antz.md`](prompts/antz.md) | the `/antz` command |
| [`extensions/antz-subagent.ts`](extensions/antz-subagent.ts) | pi only — skip it on every other client |

Copy the agent and command **bodies byte for byte**. The only thing you
write is the frontmatter, and each adapter has it ready to paste, one block per
agent. `prompts/antz.md` names no dispatch tool, so it is copied as it is: Claude
Code takes the whole file, OpenCode drops only `argument-hint:`.

The three skills are not copied by hand: one global `npx skills add edezacas/antz -g`
detects the clients you have and links them to a single shared copy in `~/.agents/skills`,
with a symlink per client that needs one. `install.sh` does not touch them.

`INSTALL.md` and [`adapters/`](adapters) are for the install. `install.sh` copies
neither.

## Verify

- every agent, the command and the extension exist at the target path;
- the agent name matches the filename — `name:` on pi and Claude Code, the
  filename itself on OpenCode;
- the body is byte-identical to the source, the `/antz` command included;
- `npx skills list -g -a <client>` lists the three skills;
- a `model:` line you pinned before a reinstall is still there;
- the permissions in the installed file match the adapter's block.

pi's path is smoke-testable as is: `./install.sh --dir "$(mktemp -d)"`, twice, then
`--uninstall`. It installs no skills, so nothing escapes the scratch directory.
