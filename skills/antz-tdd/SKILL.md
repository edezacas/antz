---
name: antz-tdd
description: antz's mandatory red-green loop for test-driven development, covering test-first, the seam the plan names, public interfaces and no mocking internals. Activate ALWAYS before writing a test or the minimum code that makes it pass.
license: Apache-2.0
metadata:
  author: edezacas
  version: "1.1"
---

The seam is the one the plan names, agreed before this session; there is no user here to ask.

Test through the public interface: no mocking internal collaborators, no testing private methods, no asserting through a side channel.

Red before green: the failing test first, then only enough code to pass it. One test, one seam, one implementation per cycle; never all tests then all code.

Refactoring isn't part of this loop.
