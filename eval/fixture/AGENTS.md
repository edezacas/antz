# pagination

In-memory pagination helper for listings. No dependencies: Node alone.

## Commands

- `npm test` — the whole suite (`node --test`). It is the only runner.

## Structure

- `src/pagination.js` — `paginate(items, { limit, offset })`.
- `src/pagination.test.js` — its test, with `node:test` and `node:assert/strict`, placed next to the module.
