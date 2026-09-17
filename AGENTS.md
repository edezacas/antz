# antz

## Overview
Portable workflow definitions for the pi coding agent: they turn a vague prompt into a
spec-clarified, TDD-built, verified feature, with a single point of human contact (the
clarify phase). What ships is markdown — subagents, two skills, one slash command —
copied into `~/.pi/agent/`; antz is never the base, it runs inside foreign repos.

## Stack
- Markdown with YAML frontmatter — the only real artifact here.
- pi 0.85.x (installed: 0.85.1). `prompts/<name>.md` and `skills/<name>/SKILL.md` are pi
  built-ins; `agents/<name>.md` is the `subagent` extension's convention, not pi core.
- `bash` + coreutils for install. No runtime, no package manager, no build step.

## Commands
Install (user scope — makes antz available in every project), then `/reload` in pi:

`cp -r agents/* ~/.pi/agent/agents/ && cp -r skills/* ~/.pi/agent/skills/ && cp -r prompts/* ~/.pi/agent/prompts/`

The `agents/` half only does something once the `subagent` extension is installed (see
Gotchas) — pi core has no sub-agents.

Use, from inside a target repo: `/antz "<prompt>"`.

There is no build, test, lint, or CI. Verification is manual: install, run `/antz` against
a sandbox repo, and read what it writes (`<repo>/.antz/`, then `docs/decisions/<slug>.md`).

## Structure
- `prompts/antz.md` — the slash command; orchestrates every phase.
- `agents/` — pi subagents: `antz-scout`, `antz-planner`, `antz-tester`, `antz-implementer`, `antz-verifier`.
- `skills/antz-clarify/` — the inquiry phase; the only phase that talks to the user.
- `skills/antz-tdd/` — red/green rules shared by antz-tester and antz-implementer.
- `README.md` — the design of record for this repo.

Flow: antz-scout (recon) → clarify (spec) → antz-planner (plan) → antz-tester→antz-implementer
per task → antz-verifier, once, after every task is green. Independent tasks may run in
parallel (max 4).

Per target project: `<repo>/.antz/` is scratch space (gitignore it); the only artifact
meant to survive is `docs/decisions/<slug>.md`, written by antz-verifier on PASS.

## Gotchas
- Intermediates are numbered and referenced by name in the prompts: `00-recon.md`,
  `01-spec.md`, `02-plan.md`, `03-verification-report.md`. Renaming one breaks the chain.
- Every artifact is written in English, but clarify asks its questions in the user's
  language. Don't switch the files to the user's language or vice versa.
- `antz-verifier` runs once, never per task, and its repair loop stops after 3 failed attempts
  per task — on the 4th it leaves `.antz/` as-is and reports instead of retrying.
- `docs/decisions/<slug>.md` is one living document per domain, not an append-only log:
  antz-verifier folds in what's new and drops what no longer holds.
- The `model:` frontmatter is deliberate — antz-scout cheap/fast, antz-tester and
  antz-implementer capable, antz-verifier a different model family from antz-implementer
  so they don't share blind spots. Omitting the line inherits the session's model.
- That choice needs auth: only `nan/*` models are usable in this environment
  (`~/.pi/agent/models.json` holds the only provider key), so the pinned
  `anthropic/claude-haiku-4-5` and `openai/gpt-5.1` fail to dispatch with "No API key
  found" until you `/login` those providers or repoint the `model:` lines.
- `agents/` is not pi core: the `subagent` extension is what discovers
  `~/.pi/agent/agents/*.md` and exposes the dispatch tool. With it missing, `/antz` has
  no antz-scout to run.
- Install needs `~/.pi/agent/agents/` to exist first (it does not here): the `cp` into a
  missing target fails, and since the three copies are chained with `&&`, that abort
  means skills and prompts never copy either. `mkdir -p ~/.pi/agent/agents` first.
- Installing clobbers: `prompts/*` overwrites `~/.pi/agent/prompts/antz.md`, and
  `skills/*` overwrites the generic user-level `~/.pi/agent/skills/tdd/SKILL.md` with
  antz's narrower seam-focused TDD rules.
- This repo is the successor to the elaborate phase/partition/`antzspec/` flow in the
  sibling `../antz` repo (installed at `~/.pi/agent/antz/`). Do not port that machinery —
  partitions, fact gates, ledgers — back in; the simplification is the point.
