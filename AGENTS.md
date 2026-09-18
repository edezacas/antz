# antz

## Overview
Portable workflow definitions for the pi coding agent: a vague prompt becomes a
spec-clarified, TDD-built, verified feature, with one point of human contact (clarify). It
ships markdown — five subagents, two skills, one slash command — plus the one extension that
dispatches them. `install.sh` copies those four directories, not this file: antz is never the
base, it runs inside foreign repos.

`README.md` is the design of record; `TODO.md` holds the open gaps.

## Design principle
**Steps and a few rules. Nothing else.** A step ("chain antz-tester into antz-implementer")
stays; a shape ("report exactly these three lines", a `Seam:` field) does not. Prefer a rule
the model applies with judgement over a contract it satisfies literally, and ask whether a
better model would make it unnecessary. Agent files stay 9–13 lines and `prompts/antz.md`
~33; a change that pushes those up needs a reason, not a reflex.

## Stack
Markdown with YAML frontmatter — everything except `extensions/antz-subagent.ts`, the one
file of code, which imports pi's SDK only: no runtime, no build step. pi 0.85.x.
`prompts/<name>.md` and `skills/<name>/SKILL.md` are pi built-ins and `extensions/*.ts` is
pi's auto-discovery path, but `agents/<name>.md` is the extension's own convention, not pi
core.

## Commands
- Install (user scope, then `/reload` in pi):
  `curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | bash`.
  Uninstall with `--uninstall`. It never reads stdin, so every choice is a flag: from a
  checkout it copies that tree, alone it clones `--ref` (default `master`). Smoke check it in
  a scratch dir with `./install.sh --dir "$(mktemp -d)"`, twice, then `--uninstall`.
- Run it from inside a target repo: `/antz "<prompt>"`.

The artifacts are prompts: no build, lint or unit tests, and verification is manual — install,
run `/antz` against a sandbox repo, read `.antz/` mid-flight and `docs/decisions/` after.
Only `eval/` covers the repair loop, as a rate over `RUNS` runs rather than a gate, and it
grades what is installed in `~/.pi/agent` (`eval/README.md`).

## Structure
- `prompts/antz.md` — the slash command: routes on `.antz/` and runs every phase.
- `agents/` — scout (recon) → planner (plan) → tester → implementer per task → verifier.
- `skills/antz-clarify/` — the spec phase, the only one that talks to the user.
- `skills/antz-tdd/` — red/green rules shared by antz-tester and antz-implementer.
- `extensions/antz-subagent.ts` — dispatch: single, parallel (max 4), or chain.

## Gotchas
- Intermediates are numbered and referenced by name: `00-recon.md`, `01-spec.md`,
  `02-plan.md`. Renaming one breaks the chain.
- Artifacts are written in English; clarify asks its questions in the user's language.
- The verifier's verdict lives in the orchestrator's context, never on disk, so a restart
  between the verdict and the repair re-runs the whole chain. Deliberate: the alternative is
  an on-disk verdict format.
- Children dispatch in-process, each its own `AgentSession`, so the frontmatter bites:
  `tools:` is enforced, `model:` is pinned. They load no extensions, so nothing recurses, and
  their `details` feed a panel the model never sees — `content` is what the orchestrator
  reads.
- `install.sh` resolves its target the way `getAgentDir()` does — `--dir`, then
  `$PI_CODING_AGENT_DIR`, then `~/.pi/agent` — and a reinstall preserves a local `model:`.
