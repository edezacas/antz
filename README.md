# antz

Autonomous dev workflow for coding agents. A vague prompt becomes a spec-clarified,
TDD-built, verified feature, and it only asks you questions once, during the clarify phase.
It runs on pi, Claude Code and OpenCode, one adapter each in [`adapters/`](adapters).

## Design principle

**Give the model steps and a few rules. Nothing else.**

The prompts say what each phase must achieve, never the shape of the answer. There are no
required output formats and no "reply with exactly these three lines". Formats are easy to
parse, but they replace the model's judgement, and when it has a better answer than the
format allows, the format still wins.

Before adding anything to `prompts/`, `agents/` or `skills/`, ask:

- **A step or a shape?** "Write the test, then the code" is a step, so keep it. "Reply with
  exactly these three lines" is a shape, so drop it.
- **A rule or a routine?** A rule is judgement the model applies, like `[x]` meaning done
  but not yet verified. A routine is a script it follows.
- **Would a better model make this unnecessary?** Then leave it out.

## Requirements

| What | Needed for |
|---|---|
| `bash` and `curl` | the one-line install |
| `git` | fetching antz when an installer is piped rather than run from a clone |
| pi, Claude Code or OpenCode | the client antz is installed into; pi's installer checks that `pi` is on `PATH` |
| Node.js >= 22.20, with `npx` | the one-time global skills install |

There is no build step and no `npm install`.

## Install

Pick your client. Its guide is the install and nothing else.

| Client | Guide |
|---|---|
| pi | [adapters/pi](adapters/pi/README.md) |
| Claude Code | [adapters/claude](adapters/claude/README.md) |
| OpenCode | [adapters/opencode](adapters/opencode/README.md) |

The five agents and the `/antz` command install at user scope, so antz is available in every
project with no per-repo setup, and `--uninstall` takes them back out. The three skills come
next, in the same guide, and they are one global copy every client shares.

To have an agent do the install, hand it this:

> Clone https://github.com/edezacas/antz and run `adapters/<your client>/install.sh` from
> that clone.

## Use, from inside any repo

```
/antz "add a way for agents to mark a lead as unresponsive after 3 failed contact attempts"
```

## Flow

`/antz "<prompt>"` reads what is already in `.antz/`, so a run can be resumed mid-flight. The
five agents are subagents, while routing, clarify, the `[x]` marking and the reporting happen
in the session you are in. Clarify has to run there because a subagent has no UI and could not
ask you anything.

```
                    /antz "<prompt>"       routes on what .antz/ already holds
                                |
                                v
                       .-----------------.  scans the repo: stack, conventions, patterns
                       |    antz-scout   |  -> .antz/00-recon.md
                       '-----------------'
                                |
                                v
   you <--- asks --->  .-----------------.  asks only what changes the acceptance criteria
  (the run's only      |   antz-clarify  |  -> .antz/01-spec.md
   question)           '-----------------'
                                |
                                v
                       .-----------------.  cuts the spec into small tasks, one test file each
                       |   antz-planner  |  Depends on, Touches -> .antz/02-plan.md
                       '-----------------'
                                |
                                v
          +---------------------+---------------------+
          |             per task (max 4)              |  independent tasks run in parallel
          |  .-------------.   .------------------.   |
      +-->|  | antz-tester |-->| antz-implementer |   |  a failing test, then the code to pass it
      |   |  '-------------'   '------------------'   |
      |   +---------------------+---------------------+
      |                         |
      |                         v
      |                .-----------------.  adjudicates the whole change once, every task green,
      |                |  antz-verifier  |  PASS -> docs/decisions/<slug>.md
      |                '-----------------'
      |                   |           |
      |                 FAIL        PASS
      |                   |           v
      |                             .antz/ deleted
      |                   |
      +-------------------+
         on FAIL: the failing task alone — a test fault to the tester, an
         implementation fault to the implementer, never both. Max 3 attempts
         per task, then it stops and reports.
```

1. **Recon.** `antz-scout` scans the repo and writes `.antz/00-recon.md`.
2. **Spec.** Clarify asks only what changes the acceptance criteria, using the `antz-clarify`
   skill when it is installed and any inquiry skill otherwise. antz writes `.antz/01-spec.md`.
   This is the only phase that talks to you.
3. **Plan.** `antz-planner` writes `.antz/02-plan.md` with small tasks, each with its own test
   file, its `Depends on` and the files it touches (`Touches`).
4. **Per task.** `antz-tester` runs first and `antz-implementer` after it, chained. One writes
   the failing test, the other the minimum code to pass it, placed and shaped by the
   architecture skill, and both stay on the one command that proves that task. Wider suites
   belong to step 5, not to the chain. Independent tasks are dispatched together as
   several chains in one call, so they run in parallel, up to 4 at once and never two that
   would touch the same files.
5. **Verify.** Once every task is green, `antz-verifier` runs one time. If it passes, it writes
   `docs/decisions/<slug>.md` and `.antz/` is deleted. If it fails, it names the task and
   whether the test or the implementation is at fault, and only that side goes back to work. A
   fault in shape counts as an implementation fault. After 3 attempts on the same task it
   stops and reports.

The dispatch tool exists only during a run. `/antz` offers it, and it is gone again once the
decision is written and `.antz/` is deleted.

## What it leaves behind

`antz-scout` creates `.antz/` with a `.gitignore` inside it holding `*`, so the scratch space
never shows up in `git status` and your repo's `.gitignore` is never touched. The only
artifact meant to survive a run is `docs/decisions/<slug>.md`, one living document per
domain, written by `antz-verifier` when a run passes.

## Models

Agents inherit the session's model. To pin one, add a `model:` line to an installed agent
file. On pi it is `provider/model` with an optional `:thinking` suffix, and on Claude Code and
OpenCode it is that client's own syntax. `antz-scout` can run cheap and fast, `antz-tester`
and `antz-implementer` need a capable coding model, and `antz-verifier` should be a different
model family from the implementer so the two don't share blind spots.

A reinstall keeps the pin. The installer overwrites the file it ships and writes your
`model:` line back. Delete the line and reinstall to reset it.
