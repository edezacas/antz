# antz

## Overview
Portable workflow definitions for coding agents: a vague prompt becomes a spec-clarified,
TDD-built, verified feature, with one point of human contact (clarify). `README.md` is the
design of record; antz installs into a client, never into the repo it later runs in.

## Design principle
**Steps and a few rules. Nothing else.** A step ("chain antz-tester into antz-implementer")
stays; a shape ("report exactly these three lines", a `Seam:` field) does not. Prefer a rule
the model applies with judgement over a contract it satisfies literally, and ask whether a
better model would make it unnecessary. Agent files stay 9–13 lines and `prompts/antz.md` 32;
a change that pushes those up needs a reason, not a reflex. An adapter's guide is the install
steps and nothing else: the per-client detail lives in its `frontmatter/`, never in prose.

## Stack
Markdown and bash: no runtime, no build step. `prompts/<name>.md` and `skills/<name>/SKILL.md`
are pi built-ins and `extensions/*.ts` is pi's auto-discovery path, but `agents/<name>.md` is
the extension's own convention, not pi core.

## Commands
- Install (user scope, then `/reload` in pi):
  `curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/pi/install.sh | bash`,
  or a wrapper from a checkout; `--uninstall` takes it back out. Smoke check any client in a
  scratch dir, twice, then `--uninstall`: `./adapters/pi/install.sh --dir "$(mktemp -d)"`.
- The three skills are global and separate: `npx skills add edezacas/antz -g`.
- Run it from inside a target repo: `/antz "<prompt>"`.
- The flow is verified by hand (install, `/antz` in a sandbox, read `.antz/` mid-flight) and by
  four instruments: `./eval/prompts.sh` and `./eval/dispatch.sh` are free and deterministic,
  `./eval/agents.sh` reads any session, `./eval/run.sh` grades a batch of the repair loop.
  `eval/README.md` has them all.

## Structure
A new client is an `adapters/<client>/` directory — its `README.md`, its `install.sh` wrapper,
its `frontmatter/<agent>.yaml` — plus its target and preflight in `adapters/install.sh`.

## Gotchas
- `prompts/antz.md` stays tool-free — no dispatch tool, no `name:` — so one body serves all
  three clients. `prompts.sh` fails if a tool creeps back in.
- Only `prompts/`, `agents/`, `skills/` and `extensions/` reach a client: a rule written only in
  `AGENTS.md`, `README.md` or `eval/` has changed nothing. A change to the flow names which of the
  four it edits, and why, before anything is installed or paid for.
- The attempt cap does not survive a resume, on purpose: a run that resumes at step 5 starts its
  three attempts again.
- Claude Code and OpenCode are verified in a scratch dir, which is as far as "the body
  arrived byte for byte" goes; only pi's install has run for real.
- OpenCode: a subagent waiting on approval hangs with no output, because `external_directory`
  and `doom_loop` default to `ask`. `opencode --auto` approves everything not explicitly
  denied; where a subagent's own rules are ignored, put the `allow`s in `opencode.json`.

## Open

What is left to decide or to confirm, none of it blocking a run.

- **The bounded verifier round is still open.** A second real run (bluplat, 2026-10-02, 2 h, 14 tasks)
  spent 48 turns / 435 s in one round and PASSed on the first try, well under the 102 turns that
  motivated the change — but no repair round ever ran, so the cap that makes a round bounded was never
  reached, and 48 exceeds the "couple of dozen" the rule names. Close it with a run whose verifier
  repairs after blaming a side, read back with `./eval/agents.sh --summary <session.jsonl>`.
- **Whether a dispatch may run in the background**, so the orchestrator's turn is free while
  children work and the live panel has a surface of its own. Explored and designed, not
  implemented: `docs/background-subagents.md` has the API seams, the design, what it breaks and the
  two decisions it is waiting on. Nothing blocks a run either way.
