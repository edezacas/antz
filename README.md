# antz

Autonomous dev workflow for the pi coding agent. Turns a vague prompt
into a spec-clarified, TDD-built, verified feature — with a single point
of human interaction (the clarify phase).

## Install (user scope — available in every project, no per-repo setup)

```
cp -r agents/*   ~/.pi/agent/agents/
cp -r skills/*   ~/.pi/agent/skills/
cp -r prompts/*  ~/.pi/agent/prompts/
```

Reload pi (`/reload`) or restart it.

## Use, from inside any repo

```
/antz "add a way for agents to mark a lead as unresponsive after 3 failed contact attempts"
```

## Structure

- `agents/` — antz-scout, antz-planner, antz-tester, antz-implementer, antz-verifier
- `skills/antz-clarify/` — the inquiry phase
- `skills/antz-tdd/` — red/green rules used by antz-tester and antz-implementer
- `prompts/antz.md` — orchestration

## Per target project

Add `.antz/` to that project's `.gitignore` — it's antz's working
scratch space, not something to commit. The only artifact meant to
survive is `docs/decisions/<slug>.md`, written by antz-verifier once a
feature passes.

## Models

Edit the `model:` line in each agent file (omit it to inherit the
session's active model). antz-scout can run on something cheap and
fast; antz-tester and antz-implementer need a capable coding model;
antz-verifier should use a different model/family than antz-implementer,
so it doesn't share the same blind spots.
