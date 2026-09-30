# platform

Two subprojects in one checkout: `api/` (the store the client talks to) and `web/` (the
helpers the browser runs). Each is its own package with its own runner, and neither imports
the other. A change in one is not a change in the other.

## Structure

- `api/src/` — server-side modules, one concern per file, each with its test next to it.
- `api/tools/` — the suite wrapper and the local helpers it needs.
- `web/src/` — browser modules, one concern per file.
- `web/test/` — the web tests, kept apart from the sources they cover.

## Conventions

- ES modules everywhere (`"type": "module"`), `node:test` and `node:assert/strict` for the
  tests.
- No dependencies: Node alone, no install step.
- A module exports named functions and nothing else.
