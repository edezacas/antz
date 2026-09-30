# 01 — Spec: the store and the browser helpers

Slug: store-helpers

Domain: **store-helpers** (the small pure helpers both packages are built from: the api store,
and the web formatting and grid helpers). Decision record target: `docs/decisions/store-helpers.md`.

## Goal

Four additions, none of which depends on another: the api store learns to report its capacity
and to round-trip through JSON, and the web gains a duration formatter and a grid span helper.
They are independent, so they can be built in any order.

## Acceptance criteria

1. **Capacity report** (`api/src/store.js`): `capacity()` returns the limit the store was created
   with, and `DEFAULT_CAPACITY` when none was given; `isFull()` is true exactly when `size()`
   equals that limit. A `capacity` that is not a positive integer is refused with a `RangeError`
   when the store is created.
2. **JSON round-trip** (`api/src/serialize.js`): `serialize(store)` returns
   `{"version":1,"items":[...]}` with the items in insertion order; `fromJSON(text, options)`
   rebuilds a store with the same options and the items in the same order; an unknown top-level
   key is ignored, a missing or null `items` list means an empty store, and a `version` other
   than `1` is refused with a `RangeError`.
3. **Duration format** (`web/src/format.js`): `formatDuration(ms)` renders `"45s"` under a
   minute, `"1m 05s"` from a minute (seconds always two digits), `"1h 05m"` from an hour
   (minutes always two digits, seconds dropped), and `"0s"` for anything negative or not finite.
   The value is truncated, never rounded up.
4. **Grid span** (`web/src/grid.js`): `spanFor(width, viewportWidth)` maps `"1/3"` to 2 columns,
   `"1/2"` to 3 and `"1"` to 6; below `BREAKPOINT_PX` every width spans the full row; an unknown
   width falls back to `"1"`.

## Out of scope

No exported behaviour changes: the existing tests of both packages have to keep passing
untouched, and no module may import the other package.
