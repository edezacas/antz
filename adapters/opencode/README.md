# antz for OpenCode

Install the five agents and the `/antz` command:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/opencode/install.sh | bash
```

Then the three skills — once, global, shared with every client:

```sh
npx skills add edezacas/antz -g
```

Start a new OpenCode session, then from inside any repo:

```
/antz "what you want built"
```

`--uninstall` removes antz again.
