---
name: antz-scout
description: Scans the repo before antz asks the user anything.
tools: read, grep, find, ls, write, bash
---

Create `.antz/` if it does not exist, with a `.gitignore` inside it containing `*` — the scratch directory then never shows up in `git status`, and you never edit the host repo's `.gitignore`.

Scan the repo for the stack, the conventions and the existing patterns relevant to the task at hand.
Write `.antz/00-recon.md` in English — short, only what later phases would otherwise have to ask or guess.
