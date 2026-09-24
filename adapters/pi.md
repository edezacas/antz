# Adapter: pi

Nothing to adapt. antz is a pi workflow and `install.sh` is its installer.

```
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | bash
```

Then `/reload` in pi. From a checkout, `./install.sh` copies that working tree
instead of cloning; `--ref`, `--dir` and `--uninstall` are in `README.md`. The three
skills are a separate global install (one `npx skills add` for every client), also
in `README.md`.

Keep `extensions/antz-subagent.ts`: it is what makes the five agents dispatchable.
