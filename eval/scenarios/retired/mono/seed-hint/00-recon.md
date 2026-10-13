# Recon

- Two unrelated packages in one checkout, `api/` and `web/`. Both are ES modules
  (`"type": "module"`), neither has dependencies, and there is no install step and no
  package at the root.
- `api/`: one module per concern under `src/`, its test next to it (`src/<name>.test.js`).
  `api/tools/suite.mjs` is the wrapper its package script calls.
- `web/`: one module per concern under `src/`, its tests under `test/` (`test/<name>.test.js`),
  apart from the sources they cover.
- Both use `node:test` with `node:assert/strict`, export named functions, and keep the test
  descriptions in Spanish while the code and its comments are English.
- Existing modules: `api/src/store.js` (a bounded in-memory store), `web/src/grid.js` (the
  column count and the breakpoint) and `web/src/format.js` (byte sizes for the UI).

## Commands

- The whole api suite: `npm test` from `api/`.
- One api file: `npm run test:one -- src/<name>.test.js` from `api/`.
- The whole web suite: `npm test` from `web/`.
- One web file: `node --test test/<name>.test.js` from `web/`.
