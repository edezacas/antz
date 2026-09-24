# Install

antz is five agents, two skills and one `/antz` command. Pick your client and
follow its adapter.

| Client | Read |
|---|---|
| pi | [adapters/pi.md](adapters/pi.md) |
| Claude Code | [adapters/claude.md](adapters/claude.md) |
| OpenCode | [adapters/opencode.md](adapters/opencode.md) |
| other | none yet — [the shipped adapters](adapters) are the spec for the next one |

To have an agent do it, hand it this:

> Clone https://github.com/edezacas/antz, read `INSTALL.md`, then do what
> `adapters/<your client>.md` says.

## What goes where

| Source | What it becomes |
|---|---|
| [`agents/*.md`](agents) | the five subagents |
| [`skills/antz-clarify/`](skills/antz-clarify), [`skills/antz-tdd/`](skills/antz-tdd) | the two skills |
| [`prompts/antz.md`](prompts/antz.md) | the `/antz` command |
| [`extensions/antz-subagent.ts`](extensions/antz-subagent.ts) | pi only — skip it on every other client |

Copy the agent and skill **bodies byte for byte**. The only thing you write is the
frontmatter, and each adapter has it ready to paste, one block per agent.
`prompts/antz.md` is the one file whose text is edited per client, because it names
the client's dispatch tool.

`INSTALL.md` and [`adapters/`](adapters) are for the install. `install.sh` copies
neither.

## Verify

- every file exists at the target path;
- the agent name matches the filename — `name:` on pi and Claude Code, the
  filename itself on OpenCode;
- the body is byte-identical to the source;
- a `model:` line you pinned before a reinstall is still there;
- the permissions in the installed file match the adapter's block.

pi's path is smoke-testable as is: `./install.sh --dir "$(mktemp -d)"`, twice, then
`--uninstall`.
