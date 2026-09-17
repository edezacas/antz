---
name: antz-clarify
description: antz's inquiry phase. Turns a vague prompt into a closed business spec by asking only what the user must decide.
---

Read `.antz/00-recon.md` if it exists. Ask in batches, not one at a time — group what you can ask now, wait for answers, then ask what those answers unblocked.

Only ask what changes the acceptance criteria. If you can find the answer yourself (the recon, the codebase), find it — don't ask.

Recommend an answer with each question so the user can just confirm.

Done when nothing's left to ask. Write `.antz/01-spec.md` in English: the decisions, the key facts, the technical assumptions left to antz-implementer, and one line `Slug: <kebab-case-feature-name>` that antz-verifier will use for `docs/decisions/<slug>.md`.
