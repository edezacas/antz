# antz

Autonomous dev workflow for the pi coding agent. Turns a vague prompt
into a spec-clarified, TDD-built, verified feature — with a single point
of human interaction (the clarify phase).

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

## Install (user scope — available in every project, no per-repo setup)

```
curl -fsSL https://raw.githubusercontent.com/edezacas/antz-pi/master/install.sh | bash
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
   minimum code to pass it. Independent tasks run in parallel (max 4), never two that
   would touch the same files.
5. **Verify** — `antz-verifier` runs once, with every task green. On PASS it writes
   `docs/decisions/<slug>.md`, and the orchestrator deletes `.antz/` once that document
   exists. On failure it names the failing task and whether the test or the implementation
   is at fault, and the loop goes back to step 4 for that task alone — a test fault to the
   tester, an implementation fault to the implementer, never both. Max 3 attempts per task,
   then it stops and reports.

   That last part is the only piece a normal run may never reach, because a normal run
   almost never fails. It has its own eval — `eval/run.sh` seeds a fault and reads the
   dispatch order back out of the session — and it is a rate, not a gate.

## Structure

- `agents/` — antz-scout, antz-planner, antz-tester, antz-implementer, antz-verifier
- `skills/antz-clarify/` — the inquiry phase
- `skills/antz-tdd/` — red/green rules used by antz-tester and antz-implementer
- `prompts/antz.md` — orchestration
- `install.sh` — pi preflight, then a copy or clone into pi's agent dir, a verification
  pass, and `--uninstall`.
- `extensions/antz-subagent.ts` — the dispatch tool: single, parallel (max 4), or chain;
  each agent runs as its own session inside pi, not as a child process, and the tool is
  only offered during an `/antz` run. While it runs, a panel shows what each agent is
  doing — files, commands, the last thing it said — one line per agent collapsed with a
  live clock, the whole trail with ctrl+o. The panel is rendered from tool details, which
  never reach the model; what reaches the orchestrator is each agent's final text, capped
  at 16 KB — except in chain mode, where that text is the handoff between agents.
- `eval/` — the repair-loop eval: it seeds `.antz/` with the plan already complete and a
  deliberate fault, runs `/antz` end to end, and reads the dispatch order back out of the
  session file. Not a test and not part of the install: the loop is model judgement, so the
  result is a rate over `RUNS` runs. See `eval/README.md`.
- `TODO.md` — known gaps and decisions not to reopen.

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
model.

What bounds the choice is auth, not the extension: only `nan/*` is usable in this
environment (`~/.pi/agent/models.json` holds the only provider key), so any other pin
needs a `/login` for that provider first.

A reinstall keeps your pin. `install.sh` copies upstream's file over the one you edited
and then puts the `model:` line back — the file is antz's, that line is yours, so
upgrading never silently re-points an agent at another model. To go back to upstream's
value (or to none), delete the line and reinstall; with the line gone there is nothing to
put back.
