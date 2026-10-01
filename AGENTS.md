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

- **The attempt cap does not cover a task that gets cut.** It counts attempts on the same task,
  so splitting one turns it into new tasks that the cap has never seen. Counting per test file
  would close it, at the cost of one more number for the orchestrator to carry.
- **Four changes rest on one real run** (2026-09-29, 12 tasks, 5 h 30, followed by 2 h of repair
  by hand): a bounded verifier round, the recon naming the run commands, "never grind", and a
  task of one capability and one seam. The fixture cannot provoke any of them, and `eval/README.md`
  says so next to what it did measure. To close them, run `/antz` in a real repo and read the
  session back with `./eval/agents.sh --summary <session.jsonl>`: the verifier well under 102
  turns, no reads under `.antz/` from a tester or an implementer, and `.antz/03-verdict.md`
  written when a round fails.
- **Judged against, and left alone**: merging `antz-tester` into `antz-implementer` (the split is
  what makes the test's independence a fact rather than a discipline) and a cheaper verifier
  model (its problem was the size of the round, not its price).
