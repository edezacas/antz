---
name: antz-clarify
description: antz's inquiry phase. Turns a vague prompt into a closed business spec by asking only what the user must decide.
license: Apache-2.0
metadata:
  author: edezacas
  version: "1.0"
---

Read `.antz/00-recon.md`. Ask in batches, not one at a time. Group what you can ask now, wait for answers, then ask what those answers unblocked.

Only ask what changes the acceptance criteria. If you can find the answer yourself (in the recon, in the codebase), find it instead of asking.

Recommend an answer with each question, so the user only has to confirm.

Done when nothing is left to ask. The decisions are made, the facts are found, and every assumption left to the implementation is named.
