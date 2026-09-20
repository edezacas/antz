# collection-helpers

Small, dependency-free helpers for working with in-memory collections. The
package is meant to be copied into a service, not published: it has no build
step, no transpiler and no bundler.

## Overview

The library is a set of pure functions over arrays. Each function does one
thing, takes plain values, and returns plain values. There is no state, no
configuration object, and no ambient anything: given the same arguments a
function returns the same result and mutates nothing it was handed.

Callers are other modules in the same service. Treat the exported surface as a
public API even though it is not published: changing a signature breaks callers
the same way, and there is no version number to hide behind.

## Commands

- `npm test` — the whole suite. It is the only command you need.
- `npm test -- --test-name-pattern "chunk"` — a single suite or test, when the
  full run is noise.
- `node --test src/chunk.test.js` — one file, without going through npm.

There is no lint, no formatter and no type checker in the project. The style is
enforced by review, not by tooling, so read the neighbouring files before you
write a new one and match them.

## Structure

```
src/
  pagination.js        one module per concern
  pagination.test.js   its test, next to it
```

- One module per concern. If a file starts growing a second responsibility that
  can be named on its own, it becomes a second module.
- The test for a module lives next to it and shares its name: `src/chunk.js` is
  tested by `src/chunk.test.js`. A module without a test is unfinished work.
- Modules are loaded with `require` and export through `module.exports`, as
  named exports. No default exports: they make the import site lie about what
  is available and they rename badly under refactors.
- Index files (`src/index.js`) are not used here. Importers name the module they
  actually need; a barrel would only add a file that has to be kept in sync.

## Code style

- CommonJS, `"use strict";` at the top of every file.
- Two-space indentation, double quotes, semicolons. Look at `src/pagination.js`
  and follow it.
- `const` by default, `let` when reassignment is real, never `var`.
- Prefer early returns to nested conditionals. A function that fits on a screen
  is easier to review than one that fits in a prettier shape.
- Small helpers local to a module stay local; only export what callers use.
- No classes for what a function does. No getters or proxies for what a plain
  property does.
- Comments explain why, not what. If the code needs a comment to say what it
  does, rename things until it does not.

## Argument conventions

- A function that operates on a list takes the list first, options second.
- Options are a single object with defaults destructured in the signature:
  `function paginate(items, { limit = DEFAULT_LIMIT, offset = 0 } = {})`.
- Defaults live in a named constant when they are part of the contract, so
  callers and tests can refer to them instead of restating a magic number.
- Do not accept both a positional and an options form. One shape per function.

## Errors

- Throw a `TypeError` when the caller passed the wrong kind of thing (a string
  where a list belongs, a non-function callback).
- Throw a `RangeError` when the value is the right kind but outside the domain
  (a negative size, a non-positive interval).
- Return the empty result rather than throwing when the input is merely empty
  or past the end. Asking for a page beyond the data is a normal question with a
  normal answer (`[]`), not an error.
- Error messages are lower-case, name the argument, and state what was wrong:
  `size must be at least 1`, not `Invalid size!`.
- Never swallow an error. If a function cannot do its job, it says so.

## Testing

- `node:test` and `node:assert/strict`, next to the module.
- Test names describe the behaviour in plain language. A reader should know
  what broke from the name alone, without opening the test body.
- One behaviour per test. Several assertions are fine when they inspect the same
  result; several unrelated behaviours in one test are not.
- Cover the ordinary case first, then the edges: empty input, a single element,
  a boundary exactly at the limit, and one step past it.
- Assertions compare values, not shapes: `deepEqual` for arrays and objects,
  `throws` with the error class for the error cases.
- No mocks. These are pure functions over plain values; if a test needs a mock,
  the function is doing something it should not.
- A test that cannot fail is not a test. Before calling the work done, confirm
  it fails against the current code for the reason you expect.

## Performance

- Keep the common case linear and obvious. Do not optimise a loop that runs over
  a list a caller already holds in memory.
- Avoid copying an array more than once per call unless the copy is the result.
- Streaming, generators and lazy evaluation are out of scope: callers hold the
  whole list, so the helpers return the whole result.

## Dependencies

- None, and that is deliberate. `package.json` has no `dependencies` and no
  `devDependencies`, and adding one needs a reason stronger than convenience.
- The Node standard library is fine (`node:test`, `node:assert`). Anything that
  needs a server, a network call or a background process is not.

## Definition of done

- The behaviour the caller asked for is implemented, and only that behaviour.
- Its test exists, is named after the behaviour, and fails before the change and
  passes after it.
- `npm test` is green and nothing else in the suite was touched to make it so.
- No new file exists without a reason, and no comment explains something the
  names already say.

## Review notes

- A change that touches a shared helper should leave the callers alone. If a
  caller has to change, the signature was wrong or the behaviour moved: say
  which, out loud, rather than doing both quietly.
- Prefer a smaller diff that solves the stated problem to a larger one that also
  tidies the neighbourhood. Unrelated cleanups belong in their own change.
- When two implementations are equally correct, choose the one with less
  machinery: fewer branches, fewer parameters, fewer concepts.
