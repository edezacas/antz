---
name: antz
description: /antz "<request>" — turn a vague request into a verified, TDD-built feature.
argument-hint: "<request>"
---

Everything antz writes lives in `.antz/`; nothing is touched outside it except the tests, the implementation and `docs/decisions/`.

**Request** — everything after `/antz`:

$ARGUMENTS

Route on what is on disk, never on memory of an earlier session.

1. List `.antz/` and let the most advanced artifact decide the phase — no question, no restart:
  - nothing there → antz-scout (single), with the request above as its task
  - `.antz/00-recon.md` → the antz-clarify skill, here, in the user's language
  - `.antz/01-spec.md` → antz-planner (single)
  - `.antz/02-plan.md` → step 2
  - `.antz/02-plan.md` with every task checked → step 3

  If what is there belongs to a different feature than the request, say so and stop — starting fresh means deleting `.antz/`, never resuming someone else's change.

2. For each unchecked task, respecting `Depends on`: chain antz-tester → antz-implementer, handing the tester's report to the implementer, and mark the task `[x]` when the chain is done. Tasks may run in parallel, up to 4 at a time, but never two that touch the same file.

3. Run antz-verifier (single) with every task checked, and again after each round of repairs — never per task. It returns PASS, or the failing tasks and whether the test or the implementation is at fault. A test fault goes back to antz-tester, an implementation fault to antz-implementer — never both. After 3 failed attempts on the same task, stop, leave `.antz/` in place, and report.

4. Report to the user, in their language.
