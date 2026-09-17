---
name: antz
description: /antz "<request>" — turn a vague request into a verified, TDD-built feature.
argument-hint: "<request>"
---

**Working root**: the host repo root. Every antz artifact lives in `.antz/` there. Nothing is written outside it except the tests, the implementation, and `docs/decisions/`.

**Request** — everything after `/antz`:

$ARGUMENTS

Route on what is on disk, never on memory of an earlier session.

1. Read `.antz/`. If it is not empty and the request above describes a **different** feature than the artifacts already there, say so and stop — starting fresh means deleting `.antz/`, never resuming someone else's change. Otherwise let the most advanced artifact decide the phase — no question, no restart:
  - nothing there → run antz-scout (single), then continue
  - `.antz/00-recon.md` → step 2
  - `.antz/01-spec.md` → step 3
  - `.antz/02-plan.md` → step 4
  - `.antz/02-plan.md` with every task checked → step 5

2. Run the antz-clarify skill yourself, here, in the user's language — this is the only phase that talks to the user. It reads `.antz/00-recon.md` and writes `.antz/01-spec.md` in English.

3. Run antz-planner (single) to write `.antz/02-plan.md`. Read the plan.

4. For each unchecked task in `.antz/02-plan.md`, respecting `Depends on`: chain antz-tester → antz-implementer. Tasks with no unmet dependency may run in parallel, up to 4 at a time (antz-planner gives each task its own test file, so they never collide). Mark the task `[x]` once its antz-implementer passes.

5. Run antz-verifier (single) when every task is checked. It returns a verdict, not a repair. If it fails a task: uncheck that task, go back to step 4, and re-run antz-verifier. Stop after 3 repair attempts on the same task and report.

6. Report the result to the user, in their language.
