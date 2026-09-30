---
description: /antz "<prompt>" - turn a vague prompt into a verified, TDD-built feature.
argument-hint: "<prompt>"
---

Everything antz writes lives in `.antz/`; nothing is touched outside it except the tests, the implementation and `docs/decisions/`.

**Prompt** (everything after `/antz`):

$ARGUMENTS

Route on what is on disk, never on memory of an earlier session. If the state on disk belongs to another feature, say so and stop. Starting fresh means deleting `.antz/`. Never resume someone else's change. The most advanced artifact present tells you where to enter:

- nothing → step 1
- `.antz/00-recon.md` → step 2
- `.antz/01-spec.md` → step 3
- `.antz/02-plan.md` → step 4
- `.antz/02-plan.md` with every task checked, or `.antz/03-verdict.md` → step 5. Act on the verdict when there is one.

`antz-scout`, `antz-planner`, `antz-tester`, `antz-implementer` and `antz-verifier` all run as subagents. Everything else (routing, clarify, marking `[x]`, sending repairs back, reporting) happens here, in this session.

1. Run antz-scout with the prompt as its task, then step 2.

2. Clarify here, in the user's language. It is the only phase that talks to the user; a subagent cannot. Read whatever skills cover interviewing the user. Ask only what changes the acceptance criteria. Stop when nothing is left to ask. Write `.antz/01-spec.md` in English, with a `Slug:` line naming the domain, not the feature, so related features share one `docs/decisions/<slug>.md`. Then step 3.

3. Run antz-planner to write `.antz/02-plan.md`, then step 4.

4. Take each unchecked task in `Depends on` order. Chain antz-tester into antz-implementer, so the tester's report reaches the implementer. Give both the task in full: acceptance criteria, test path, files it touches. Neither reopens `.antz/`. Mark `[x]` when the chain ends. The task is proved by one command, the narrowest that shows the test red and then green. That command comes from the tester. Wider suites belong to step 5. Independent tasks run together, up to 4. Two tasks that touch the same files never run together; `Touches` says which. When every task is checked, step 5.

5. Once every task is checked, run antz-verifier. It writes its verdict to `.antz/03-verdict.md`: PASS, or the failing tasks and which side is at fault. An interrupted run then resumes here instead of redoing the work. Send a test fault back to antz-tester. Send an implementation fault to antz-implementer. Never both. The verifier runs again for the whole plan, once per round, never per task. A task an agent stopped on is a task to cut or to send with a different approach, never to resend unchanged. On PASS, delete `.antz/` once `docs/decisions/<slug>.md` exists, then step 6. After 3 failed attempts on the same task, stop, leave `.antz/` in place and report.

6. Report to the user, in their language.
