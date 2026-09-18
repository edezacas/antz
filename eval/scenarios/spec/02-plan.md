# Plan

- [x] Task 1 — `paginate` respects `MAX_LIMIT = 100`.
  - Test: `src/pagination.test.js`
  - Acceptance: with `{ limit: 1000 }` over 200 elements it returns 100.
  - Depends on: none
- [x] Task 2 — an `offset` past the end returns `[]`.
  - Test: `src/pagination.test.js`
  - Acceptance: `paginate([1,2,3], { offset: 10 })` returns `[]`.
  - Depends on: none
