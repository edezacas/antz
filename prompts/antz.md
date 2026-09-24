---
description: /antz "<prompt>" - turn a vague prompt into a verified, TDD-built feature.
argument-hint: "<prompt>"
---

Everything antz writes lives in `.antz/`; nothing is touched outside it except the tests, the implementation and `docs/decisions/`.

**Prompt** (everything after `/antz`):

$ARGUMENTS

Route on what is on disk, never on memory of an earlier session. If what is there belongs to a different feature than the prompt, say so and stop. Starting fresh means deleting `.antz/`, never resuming someone else's change. Otherwise the most advanced artifact present tells you where to enter:

- nothing → step 1
- `.antz/00-recon.md` → step 2
- `.antz/01-spec.md` → step 3
- `.antz/02-plan.md` → step 4
- `.antz/02-plan.md` with every task checked → step 5

`antz-scout`, `antz-planner`, `antz-tester`, `antz-implementer` and `antz-verifier` all run as subagents. Everything else (routing, clarify, marking `[x]`, sending repairs back, reporting) happens here, in this session.

1. Run antz-scout with the prompt as its task, then step 2.

2. Run the antz-clarify skill here, in the user's language: it is the one phase that talks to the user, and a subagent cannot. It writes `.antz/01-spec.md` in English, then step 3.

3. Run antz-planner to write `.antz/02-plan.md`, then step 4.

4. For each unchecked task, respecting `Depends on`: chain antz-tester → antz-implementer, the implementer getting the tester's report, and mark the task `[x]` when the chain is done. Independent tasks run at the same time, up to 4, never two that would touch the same files (`Touches` is the hint). When every task is checked, step 5.

5. Once every task is checked, run antz-verifier. It returns PASS, or the failing tasks and whether the test or the implementation is at fault. A test fault goes back to antz-tester, an implementation fault to antz-implementer, never both. The verifier runs again for the whole plan, once per round, never per task. On PASS, once `docs/decisions/<slug>.md` exists, delete `.antz/`, then step 6. After 3 failed attempts on the same task, stop, leave `.antz/` in place, and report.

6. Report to the user, in their language.
