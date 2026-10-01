---
description: /antz "<prompt>" turns a vague prompt into a verified, TDD-built feature.
argument-hint: "<prompt>"
---

Everything antz writes lives in `.antz/`, except the tests, the implementation and `docs/decisions/`.

**Prompt** (everything after `/antz`): $ARGUMENTS

Route on what is on disk, never on memory of a past session. If the state belongs to another feature, say so and stop; starting fresh means deleting `.antz/`. The most advanced artifact present says where to enter: nothing, step 1; `.antz/00-recon.md`, step 2; `.antz/01-spec.md`, step 3; `.antz/02-plan.md`, step 4; every task checked or `.antz/03-verdict.md`, step 5, acting on the verdict there. Never resume someone else's change.

`antz-scout`, `antz-planner`, `antz-tester`, `antz-implementer` and `antz-verifier` run as subagents. Routing, clarify, marking `[x]`, sending repairs back and reporting happen here, in this session.

1. Run antz-scout with the prompt as its task, then step 2.

2. Clarify here, in the user's language, since a subagent cannot ask. Read whatever skills cover interviewing the user, ask only what changes the acceptance criteria, and stop when nothing is left to ask. Write `.antz/01-spec.md` in English with a `Slug:` line naming the domain, not the feature, so related features share one `docs/decisions/<slug>.md`. Then step 3.

3. Run antz-planner to write `.antz/02-plan.md`, then step 4.

4. Take each unchecked task in `Depends on` order and chain antz-tester into antz-implementer, so the tester's report reaches the implementer. Give both the task in full: acceptance criteria, test path, files it touches; neither reopens `.antz/`. The tester's one command proves the task, the narrowest that shows the test red and then green; wider suites belong to step 5. Mark `[x]` when the chain ends. Independent tasks run together, up to 4, and never two that touch the same files (`Touches` says which). Then step 5.

5. Run antz-verifier once every task is checked. It writes its verdict to `.antz/03-verdict.md`, PASS or the failing tasks and the side at fault, so an interrupted run resumes here instead of redoing the work. Send a test fault back to antz-tester and an implementation fault to antz-implementer, never both. It runs once per round for the whole plan, never per task. A task an agent stopped on is cut or sent a different way, never resent unchanged. On PASS, delete `.antz/` once `docs/decisions/<slug>.md` exists, then step 6. Stop after 3 failed attempts on the same test file (a task cut or reframed counts against it), leaving `.antz/` in place and reporting.

6. Report to the user, in their language.
