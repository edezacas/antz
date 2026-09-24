---
name: antz-architecture
description: Where code belongs, how it is shaped, and how a finished change is judged. Activate before writing a test or implementation code, and when reviewing a change that is already green. Apply SoC, SOLID, DRY and KISS pragmatically.
license: Apache-2.0
metadata:
  author: edezacas
  version: "1.3"
---

Ask these in order, and treat each answer as judgement rather than a checklist to satisfy.

Where does this belong? A business rule, a data access, a presentation concern, or whatever else this repo already separates: put it in the box it already uses for that concern, and add a box only when every existing one is wrong for it.

Inside that box, aim for one reason to change, and depend on an abstraction only where something genuinely varies at the seam. A single implementation is indirection, not a seam.

Look for the logic before you write it. If it already exists, reuse it or put yours beside it, and leave code that is only superficially similar alone, even when it sits next to the logic it resembles; if unifying it would reach outside your task, report it instead of doing it.

Finish with the smallest thing that passes: no interface, wrapper or pattern the test does not demand. A readable conditional beats unnecessary over-engineering; when you take it over the abstract route or depart from an established convention, say so.

Placement and shape are settled while writing; DRY and KISS are judged once, on the whole change, because only then are the cross-task duplicates and the surplus structure visible. What it finds is a shape fault only when a behaviour-preserving change fixes it with the tests green; anything that needs new behaviour is scope, not shape.
