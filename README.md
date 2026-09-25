# antz

Autonomous dev workflow for the pi coding agent. A vague prompt becomes a spec-clarified,
TDD-built, verified feature, with a single point of human interaction — the clarify phase.
It runs on pi, and on Claude Code and OpenCode through the adapters in
[`adapters/`](adapters).

## Design principle

**Give the model steps and a few rules. Nothing else.**

The flow says *what* happens in each phase and *which rules are not negotiable*. It never
prescribes the shape of what a model writes: no output formats, no required fields, no
"emit exactly these lines". Those buy a little determinism at parse time and pay for it
with a straitjacket — the moment the model's judgement is better than the contract, the
contract still wins. Models improve every few months; a fixed format is a bet that they
won't.

Before adding anything to `prompts/`, `agents/` or `skills/`, ask:

- **Step or shape?** "Chain the tester into the implementer" is a step. "Report exactly
  these three lines" is a shape. Keep the step, drop the shape.
- **Rule or routine?** A rule ("`[x]` means done, not verified"; "never send a task back
  to the tester and the implementer at once") is judgement the model applies. A routine
  is a script it executes.
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

Pick your client. Its guide is the install and nothing else:

| Client | Guide |
|---|---|
| pi | [adapters/pi](adapters/pi/README.md) |
| Claude Code | [adapters/claude](adapters/claude/README.md) |
| OpenCode | [adapters/opencode](adapters/opencode/README.md) |

The five agents and the `/antz` command install at user scope, so antz is available in every
project with no per-repo setup, and `--uninstall` takes them back out. The three skills come
next, in the same guide — one global copy every client shares.

To have an agent do the install, hand it this:

> Clone https://github.com/edezacas/antz and run `adapters/<your client>/install.sh` from
> that clone.

## Use, from inside any repo

```
/antz "add a way for agents to mark a lead as unresponsive after 3 failed contact attempts"
```

## Flow

`/antz "<prompt>"` routes on what is already in `.antz/`, so a run can be resumed mid-flight.
The five agents are subagents, while routing, clarify, the `[x]` marking and the reporting
happen in the session you are in. Clarify has to: a subagent has no UI, so it could not ask
the user anything.

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

1. **Recon** — `antz-scout` scans the repo and writes `.antz/00-recon.md`.
2. **Spec** — clarify (the `antz-clarify` skill when installed, any inquiry skill otherwise)
   asks only what changes the acceptance criteria; antz writes `.antz/01-spec.md`. This is the
   only phase that talks to the user.
3. **Plan** — `antz-planner` writes `.antz/02-plan.md`: small tasks, each with its own
   test file, its `Depends on` and the files it touches (`Touches`).
4. **Per task** — `antz-tester` → `antz-implementer`, chained: a failing test, then the
   minimum code to pass it, placed and shaped by the architecture skill. Independent tasks
   are dispatched together as several chains in one call, so they run in parallel (max 4 at
   once), never two that would touch the same files.
5. **Verify** — `antz-verifier` runs once, with every task green. On PASS it writes
   `docs/decisions/<slug>.md` and the orchestrator deletes `.antz/`. On FAIL it names the
   failing task and whether the test or the implementation is at fault — a fault in shape is
   an implementation fault — and only that side goes back: a test fault to the tester, an
   implementation fault to the implementer. Max 3 attempts per task, then it stops and
   reports.

The dispatch tool exists only during a run: `/antz` offers it, and it is gone again once the
decision is written and `.antz/` is deleted.

## What it leaves behind

`antz-scout` creates `.antz/` with a `.gitignore` inside it holding `*`, so the scratch space
never shows up in `git status` and your repo's `.gitignore` is never touched. The only
artifact meant to survive a run is `docs/decisions/<slug>.md`, one living document per
domain, written by `antz-verifier` on PASS.

## Models

Agents inherit the session's model. A `model:` line in an installed agent file pins one — on
pi `provider/model` with an optional `:thinking` suffix, on Claude Code and OpenCode that
client's syntax. `antz-scout` can run cheap and fast, `antz-tester` and `antz-implementer`
need a capable coding model, and `antz-verifier` should be a different model family from the
implementer so the two don't share blind spots.

A reinstall keeps the pin: the installer overwrites the file it ships and writes your
`model:` line back. Delete the line and reinstall to reset it.
