---
name: antz-tdd
description: antz's red-green loop. Test the seam, not the internals.
---

Test through the public interface — no mocking internal collaborators, no testing private methods, no asserting through a side channel.

Red before green: the failing test first, then only enough code to pass it. One test, one seam, one implementation per cycle — never all tests then all code.

Refactoring isn't part of this loop.
