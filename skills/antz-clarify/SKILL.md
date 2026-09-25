---
name: antz-clarify
description: antz's inquiry phase. Interviews the user, asking only what must be decided, until a vague prompt is a closed business spec. Activate on requirements, scope, ambiguity or an unclosed spec.
license: Apache-2.0
metadata:
  author: edezacas
  version: "1.1"
---

Read `.antz/00-recon.md`. Ask in batches, not one at a time. Group what you can ask now, wait for answers, then ask what those answers unblocked.

Only ask what changes the acceptance criteria. If you can find the answer yourself (in the recon, in the codebase), find it instead of asking.

Recommend an answer with each question, so the user only has to confirm.

Done when nothing is left to ask. The decisions are made, the facts are found, and every assumption left to the implementation is named.
