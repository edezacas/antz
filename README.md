# antz

Autonomous dev workflow for the pi coding agent. Turns a vague prompt
into a spec-clarified, TDD-built, verified feature — with a single point
of human interaction (the clarify phase). It runs on pi, and on Claude Code
and OpenCode through the adapters in `adapters/` — see [Install](#install).

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

## Install

pi, user scope, so it is available in every project with no per-repo setup:

```
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | bash
```

Reload pi (`/reload`) or restart it. The `extensions/` copy is what makes the rest work:
pi core has no sub-agents, and `antz-subagent.ts` is the extension that provides the dispatch
tool every agent is run through.

From a checkout, `./install.sh` copies that working tree instead of cloning — which is also how
a change to the installer gets tried before it is pushed. It takes `--ref <branch|tag|commit>`
to pick what to install, `--dir <path>` to override the target (default
`$PI_CODING_AGENT_DIR`, else `~/.pi/agent`), and `--uninstall` to remove exactly antz's files.
A reinstall is an upgrade: only antz's own paths are written, so anything else already in pi's
agent dir survives both directions. Under a pipe the flags go through bash:

```
curl -fsSL .../install.sh | bash -s -- --ref v1.0.0
```

Claude Code and OpenCode have no installer — they follow a guide. [`INSTALL.md`](INSTALL.md)
is the entry point, and [`adapters/`](adapters) has one file per client:
[Claude Code](adapters/claude.md) and [OpenCode](adapters/opencode.md), plus
[pi](adapters/pi.md), which just points back here. An adapter gives the target paths,
the frontmatter to paste for each of the five agents, and the check that the bodies
arrived byte for byte — the `/antz` command included, since it names no client's
dispatch tool. Both are written from the vendors' docs and have not yet been run as a
real install; the pi path above is the one exercised end to end.

## Use, from inside any repo

```
/antz "add a way for agents to mark a lead as unresponsive after 3 failed contact attempts"
```

## Flow

`/antz "<prompt>"` routes on what is already in `.antz/`, so a run can be resumed
mid-flight. `antz-scout`, `antz-planner`, `antz-tester`, `antz-implementer` and
`antz-verifier` are subagents; the routing, the spec phase, the `[x]` marking and the
reporting happen in the session. Clarify has to run there — a subagent is an isolated
session with no UI, so it could not ask the user anything.

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

The `antz_subagent` tool belongs to antz and nowhere else: a normal session is never
offered it. `/antz` makes it available, and it disappears again once a run ends with
`.antz/` gone — the orchestrator deletes it once the decision is written. A run left
half-done, waiting on a clarify answer, or under repair keeps it.

1. **Recon** — `antz-scout` scans the repo and writes `.antz/00-recon.md`.
2. **Spec** — the `antz-clarify` skill asks the user only what changes the acceptance
   criteria, and writes `.antz/01-spec.md`. This is the only phase that talks to the user.
3. **Plan** — `antz-planner` writes `.antz/02-plan.md`: small tasks, each with its own
   test file, its `Depends on` and the files it touches (`Touches`).
4. **Per task** — `antz-tester` → `antz-implementer`, chained: a failing test, then the
   minimum code to pass it. Independent tasks are dispatched together as several chains
   in one call, so they run in parallel (max 4 at once), never two that would touch the
   same files.
5. **Verify** — `antz-verifier` runs once, with every task green. On PASS it writes
   `docs/decisions/<slug>.md`, and the orchestrator deletes `.antz/` once that document
   exists. On failure it names the failing task and whether the test or the implementation
   is at fault, and the loop goes back to step 4 for that task alone — a test fault to the
   tester, an implementation fault to the implementer, never both. Max 3 attempts per task,
   then it stops and reports.

   That last part is the only piece a normal run may never reach, because a normal run
   almost never fails. It has its own eval — `eval/run.sh` seeds a fault and reads the
   dispatch order back out of the session — and it is a rate, not a gate.

   Both arms have since been watched on a real run (2026-09-21, a small Node checkout
   project entered at step 5 with one fault seeded): an implementation that ignored a
   discount cap gave `verifier → implementer → verifier`, and a test that contradicted
   the spec gave `verifier → tester → verifier`. Each named the failing task and the side
   at fault, sent it only there, and closed in PASS with `docs/decisions/checkout.md`
   written and `.antz/` deleted.

## Structure

- `agents/` — antz-scout, antz-planner, antz-tester, antz-implementer, antz-verifier
- `skills/antz-clarify/` — the inquiry phase
- `skills/antz-tdd/` — red/green rules used by antz-tester and antz-implementer
- `prompts/antz.md` — orchestration
- `INSTALL.md`, `adapters/` — the install guide for the clients without an installer: pi,
  Claude Code, OpenCode. Markdown for the agent doing the install; `install.sh` copies
  neither.
- `install.sh` — pi preflight, then a copy or clone into pi's agent dir, a verification
  pass, and `--uninstall`.
- `extensions/antz-subagent.ts` — the dispatch tool: single, parallel (max 4), chain, or
  several chains in parallel (max 4 in flight, one per task);
  each agent runs as its own session inside pi, not as a child process, and the tool is
  only offered during an `/antz` run. While it runs, a panel shows what each agent is
  doing — the model and thinking level it actually runs with, files, commands, the last
  thing it said — one line per agent collapsed with a live clock, the whole trail with
  ctrl+o. The panel is rendered from tool details, which never reach the model; what
  reaches the orchestrator is each agent's final text, capped at 16 KB — except in chain
  mode, where that text is the handoff between agents.
- `eval/` — two instruments, neither part of the install. `run.sh` is the repair-loop
  eval: it seeds `.antz/` with the plan already complete and a deliberate fault, runs
  `/antz` end to end, and reads the dispatch order back out of the session file — model
  judgement, so a rate over `RUNS` runs rather than a gate, grading what is installed.
  `dispatch.sh` checks the dispatch tool itself — the four shapes, the concurrency cap,
  the per-chain handoff, the failure path and both renderers — with the pi SDK stubbed,
  so it is deterministic, free, and tests the working tree. See `eval/README.md`.

## Per target project

Nothing to set up. `antz-scout` creates `.antz/` with a `.gitignore` inside it containing
`*`, so the scratch space never shows up in `git status` and your repo's `.gitignore` is
never touched. The only artifact meant to survive a run is `docs/decisions/<slug>.md` —
one living document per domain — written by `antz-verifier` on PASS.

## Models

Agents inherit the session's model. Pinning one means adding a `model:` line to an agent
file — `provider/model`, with an optional `:thinking` suffix: `antz-scout` can run cheap
and fast, `antz-tester` and `antz-implementer` need a capable coding model, and
`antz-verifier` should be a different model family from `antz-implementer` so the two
don't share blind spots. The pin is resolved in process, so a model that does not exist or
has no credentials fails that agent by name rather than silently running on the session's
model. On Claude Code and OpenCode it goes in that client's frontmatter block instead; the
adapter shows where, and the family rule is the same.

What bounds the choice is auth, not the extension: only `nan/*` is usable in this
environment (`~/.pi/agent/models.json` holds the only provider key), so any other pin
needs a `/login` for that provider first.

A reinstall keeps your pin. `install.sh` copies upstream's file over the one you edited
and then puts the `model:` line back — the file is antz's, that line is yours, so
upgrading never silently re-points an agent at another model. To go back to upstream's
value (or to none), delete the line and reinstall; with the line gone there is nothing to
put back.
