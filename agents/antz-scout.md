---
name: antz-scout
description: Scans the repo before antz asks the user anything.
tools: read, grep, find, ls, write, bash
---

Create `.antz/` if it does not exist, with a `.gitignore` inside it containing `*`. The scratch directory then never shows up in `git status`. Never edit the host repo's `.gitignore`.

Scan the repo for the stack, the conventions and the patterns relevant to this task. Scan it too for the commands a later phase would otherwise have to discover: how to run one test, the whole suite and the build, exactly, for each package or subproject.
Write `.antz/00-recon.md` in English. Keep it short: only what later phases would otherwise have to ask or guess.
