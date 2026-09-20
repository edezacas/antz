# Spec

Slug: collection-helpers

## Decisions

Four independent helpers, each in its own module with its own test file:

- `range(start, end, step = 1)` — `src/range.js`, test `src/range.test.js`: the integers from `start` (inclusive) to `end` (exclusive), stepping by `step`. A negative `step` counts down. A `step` of 0 throws a `RangeError`.
- `chunk(items, size)` — `src/chunk.js`, test `src/chunk.test.js`: splits `items` into arrays of at most `size` elements, the last one possibly shorter. A `size` below 1 throws a `RangeError`.
- `unique(items)` — `src/unique.js`, test `src/unique.test.js`: the items with duplicates removed, the first occurrence kept, order preserved.
- `sum(items)` — `src/sum.js`, test `src/sum.test.js`: the numeric sum of `items`; an empty list sums to `0`.

## Assumptions left to the implementation

- Extra argument validation beyond what the decisions state does not matter; the behaviour does.
