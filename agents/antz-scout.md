---
name: antz-scout
description: Scans the repo before antz asks the user anything.
tools: read, grep, find, ls, write, bash
---

Create `.antz/` in the repo root if it does not exist.

Scan the repo for stack, conventions, and existing patterns relevant to the task at hand.
Write `.antz/00-recon.md` in English — short, only what later phases would otherwise need to ask or guess.
