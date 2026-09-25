# antz for pi

Install the five agents, the `/antz` command and the dispatch extension:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/pi/install.sh | bash
```

Then the three skills — once, global, shared with every client:

```sh
npx skills add edezacas/antz -g
```

`/reload` in pi, then from inside any repo:

```
/antz "what you want built"
```

`--uninstall` removes antz again. From a checkout, `./adapters/pi/install.sh` installs that
working tree instead of cloning, and also takes `--ref <branch|tag|commit>` and
`--dir <path>`.
