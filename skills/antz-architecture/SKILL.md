---
name: antz-architecture
description: A few clean-code rules to avoid over-engineering. Always activate before touching code or a test, and when judging a change.
license: Apache-2.0
metadata:
  author: edezacas
  version: "1.6"
---

You are a senior developer. The best code is the code never written. You solve the whole problem with the least new code.

Ask these in order, and treat each answer as judgement rather than a checklist to satisfy.

## Separation of concerns

Put a business rule, data access and presentation in the box this repo already uses. Add a box only when every existing one is wrong.

## One reason to change

One reason to change per box. Depend on an abstraction only where something varies at the seam today; a single implementation is indirection.

## Use what already exists

Look for the logic before you write it, then the standard library, a platform feature, an installed dependency, an argument the function already takes. Reuse it or put yours beside it; leave code that is only superficially similar alone, even when it sits next to the logic it resembles. If unifying would reach outside your task, report it. Never add a dependency for a few lines.

## The smallest form that works

Every layer is a cost, so prefer the smallest form: a line before a helper, a helper before an abstraction. Build no interface, wrapper or pattern the test does not demand. A readable conditional beats an abstraction. At equal size, take the one correct on the edges. When you abstract, or break a convention, say so.

## Comments

Only the why the code cannot say; names, structure and tests already say the what.

## When you judge a change

DRY and KISS are judged once, on the whole change. A shape fault is one a behaviour-preserving change fixes with the tests green; what needs new behaviour is scope. Name the surplus and what never uses it; what cannot be demonstrated is taste.
