# antz for Claude Code

Install the five agents and the `/antz` command:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/claude/install.sh | bash
```

Then the skill antz ships, optional but recommended. It is one global copy every client
shares.

```sh
npx skills add edezacas/antz -g
```

The flow is better with skills covering test-driven development and architecture.
[edezacas/agent-skills](https://github.com/edezacas/agent-skills) has both, and a skill you
already use for them does just as well.

```sh
npx skills add edezacas/agent-skills -g
```

Start a new Claude Code session, then from inside any repo:

```
/antz "what you want built"
```

`--uninstall` removes antz again.
