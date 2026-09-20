# Recon

- Node.js, CommonJS, no dependencies. Only runner: `npm test` (`node --test`).
- One module per concern under `src/`, each with its test next to it (`src/<name>.test.js`), using `node:test` and `node:assert/strict`.
- `src/pagination.js` is the existing example: a small module that exports its functions via `module.exports`.
