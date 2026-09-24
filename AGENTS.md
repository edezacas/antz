# antz

## Overview
Portable workflow definitions for the pi coding agent: a vague prompt becomes a
spec-clarified, TDD-built, verified feature, with one point of human contact (clarify). It
ships markdown — five subagents, three skills, one slash command — plus the one extension that
dispatches them. `install.sh` copies the pi artifacts, not this file: antz is never the base, it
runs inside foreign repos. The three skills are a separate, global `npx skills` install shared
with Claude Code and OpenCode. Clients with no installer get a guide instead:
`INSTALL.md` plus one `adapters/<client>.md` each.

`README.md` is the design of record; `INSTALL.md` is how a client other than pi gets antz.

## Design principle
**Steps and a few rules. Nothing else.** A step ("chain antz-tester into antz-implementer")
stays; a shape ("report exactly these three lines", a `Seam:` field) does not. Prefer a rule
the model applies with judgement over a contract it satisfies literally, and ask whether a
better model would make it unnecessary. Agent files stay 9–13 lines and `prompts/antz.md`
~33; a change that pushes those up needs a reason, not a reflex. An adapter is a guide —
paths, blocks to paste, a check — never a rationale.

## Stack
Markdown with YAML frontmatter — everything except `extensions/antz-subagent.ts`, the one
file of code, which imports pi's SDK only: no runtime, no build step. pi 0.85.x, and
`npx skills` (Node >= 22.20) only for the separate global skills install.
`prompts/<name>.md` and `skills/<name>/SKILL.md` are pi built-ins and `extensions/*.ts` is
pi's auto-discovery path, but `agents/<name>.md` is the extension's own convention, not pi
core.

## Commands
- Install (user scope, then `/reload` in pi):
  `curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | bash`.
  Uninstall with `--uninstall`. It never reads stdin, so every choice is a flag: from a
  checkout it copies that tree, alone it clones `--ref` (default `master`). Smoke check it in
  a scratch dir with `./install.sh --dir "$(mktemp -d)"`, twice, then `--uninstall`.
- Install the skills, global and once: `npx skills add edezacas/antz -g`. The CLI detects
  which clients are installed and links them to one shared copy in `~/.agents/skills`, with a
  symlink per client that needs one. Outside `install.sh` on purpose: the skills are shared,
  the pi artifacts are not.
- Run it from inside a target repo: `/antz "<prompt>"`.
- Install on Claude Code or OpenCode: read `INSTALL.md`, then `adapters/<client>.md`. Those
  are guide markdown for the agent doing the install, never copied by `install.sh`.

The artifacts are prompts: no build and no lint, and verification of the flow is manual —
install, run `/antz` against a sandbox repo, read `.antz/` mid-flight and `docs/decisions/`
after. `extensions/antz-subagent.ts` is the one file of code that is not prompt text, and
`eval/` has an instrument for each: `./eval/dispatch.sh` drives the tool with the pi SDK
stubbed — four shapes, concurrency cap, per-chain handoff, failure path, panel — free, in a
second, against the working tree; `./eval/run.sh` covers the repair loop and the shape
check as a rate over
`RUNS` runs and grades what is installed in `~/.pi/agent` (`eval/README.md`). The adapters
have no instrument: they are pi's copies seen through another client's frontmatter, so the
check that they landed is a shell snippet in each adapter, run by hand once.

## Structure
- `prompts/antz.md` — the slash command: routes on `.antz/` and runs every phase.
- `agents/` — scout (recon) → planner (plan) → tester → implementer per task → verifier.
- `skills/antz-clarify/` — the spec phase, the only one that talks to the user.
- `skills/antz-tdd/` — red/green rules shared by antz-tester and antz-implementer.
- `skills/antz-architecture/` — where code belongs and how it is shaped, shared by
  antz-tester, antz-implementer and antz-verifier.
- `INSTALL.md`, `adapters/` — the install guide for clients with no installer, one file per
  client; each holds the target paths, the frontmatter to paste per agent and how that client
  dispatches.
- `extensions/antz-subagent.ts` — dispatch: single, parallel (max 4), chain, or several
  chains at once (max 4 in flight).

## Gotchas
- Intermediates are numbered and referenced by name: `00-recon.md`, `01-spec.md`,
  `02-plan.md`. Renaming one breaks the chain.
- `prompts/antz.md` names no dispatch tool and carries no `name:` (pi takes the command name
  from the file), so its body is byte-identical on every client and the adapters only rewrite
  frontmatter. Naming a tool there puts the per-client edit back.
- Artifacts are written in English; clarify asks its questions in the user's language.
- The verifier's verdict lives in the orchestrator's context, never on disk, so a restart
  between the verdict and the repair re-runs the whole chain. Deliberate: the alternative is
  an on-disk verdict format.
- Children dispatch in-process, each its own `AgentSession`, so the frontmatter bites:
  `tools:` is enforced, `model:` is pinned. They load no extensions, so nothing recurses, and
  their `details` feed a panel the model never sees — `content` is what the orchestrator
  reads.
- `install.sh` resolves its target the way `getAgentDir()` does — `--dir`, then
  `$PI_CODING_AGENT_DIR`, then `~/.pi/agent` — and a reinstall preserves a local `model:`. It
  installs no skills: `--uninstall` still removes the pi copy, but the shared one in
  `~/.agents/skills` is `npx skills`' to remove.
