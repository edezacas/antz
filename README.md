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

This repo already paid for the lesson once — the phase/partition/`antzspec/` flow in the
sibling `../antz` — and the simplification is the point.

## Install (user scope — available in every project, no per-repo setup)

```
mkdir -p ~/.pi/agent/{agents,extensions} && \
cp -r extensions/* ~/.pi/agent/extensions/ && \
cp -r agents/*     ~/.pi/agent/agents/     && \
cp -r skills/*     ~/.pi/agent/skills/     && \
cp -r prompts/*    ~/.pi/agent/prompts/
```

Reload pi (`/reload`) or restart it. The `extensions/` copy is what makes the rest work:
pi core has no sub-agents, and `subagent.ts` is the extension that provides the dispatch
tool every agent is run through.

## Use, from inside any repo

```
/antz "add a way for agents to mark a lead as unresponsive after 3 failed contact attempts"
```

## Flow

`/antz "<request>"` routes on what is already in `.antz/`, so a run can be resumed
mid-flight:

1. **Recon** — `antz-scout` scans the repo and writes `.antz/00-recon.md`.
2. **Spec** — the `antz-clarify` skill asks the user only what changes the acceptance
   criteria, and writes `.antz/01-spec.md`. This is the only phase that talks to the user.
3. **Plan** — `antz-planner` writes `.antz/02-plan.md`: small tasks, each with its own
   test file and its `Depends on`.
4. **Per task** — `antz-tester` → `antz-implementer`, chained: a failing test, then the
   minimum code to pass it. Independent tasks run in parallel (max 4), never two that
   touch the same file.
5. **Verify** — `antz-verifier` runs once, with every task green. On PASS it writes
   `docs/decisions/<slug>.md` and deletes `.antz/`. On failure it names the failing task
   and whether the test or the implementation is at fault, and the loop goes back to step
   4 for that task alone — a test fault to the tester, an implementation fault to the
   implementer, never both. Max 3 attempts per task, then it stops and reports.

## Structure

- `agents/` — antz-scout, antz-planner, antz-tester, antz-implementer, antz-verifier
- `skills/antz-clarify/` — the inquiry phase
- `skills/antz-tdd/` — red/green rules used by antz-tester and antz-implementer
- `prompts/antz.md` — orchestration
- `extensions/subagent.ts` — the dispatch tool: single, parallel (max 4), or chain

## Per target project

Nothing to set up. `antz-scout` creates `.antz/` with a `.gitignore` inside it containing
`*`, so the scratch space never shows up in `git status` and your repo's `.gitignore` is
never touched. The only artifact meant to survive a run is `docs/decisions/<slug>.md` —
one living document per domain — written by `antz-verifier` on PASS.

## Models

Agents inherit the session's model. Pinning one means adding a `model:` line to an agent
file: `antz-scout` can run cheap and fast, `antz-tester` and `antz-implementer` need a
capable coding model, and `antz-verifier` should be a different model family from
`antz-implementer` so the two don't share blind spots.

**Not usable yet.** `buildArgs()` in `extensions/subagent.ts` passes `-m`, which pi 0.85.1
rejects, so any agent carrying a `model:` line fails to dispatch. No agent pins one today,
and that is the only reason the pipeline runs. See the gotcha in `AGENTS.md`.
