# Plan

- [ ] Task 1 — `paginate` respects `MAX_LIMIT = 100`.
  - Test: `src/pagination.test.js`
  - Acceptance: with `{ limit: 1000 }` over 200 elements the same call returns 100 elements and throws a `RangeError`.
  - Depends on: none
  - Touches: `src/pagination.js`, `src/pagination.test.js`
