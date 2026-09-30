# Plan

- [ ] **T1 `api-store-capacity`** — the capacity report on the store.
  - **Acceptance criteria**: `api/src/store.js` gains `capacity()`, returning the limit the store was created with and `DEFAULT_CAPACITY` when none was given, and `isFull()`, true exactly when `size()` equals that limit and false otherwise. A `capacity` that is not a positive integer (zero, negative, fractional, `NaN`) is refused with a `RangeError` when the store is created, not at the first `add`. Everything already exported keeps its behaviour: `add` still throws `RangeError` when full, `list()` still returns a copy, and `api/src/store.test.js` must keep passing untouched.
  - **Owns test**: `api/src/capacity.test.js` (new).
  - **Depends on**: none.
  - **Touches**: `api/src/store.js`.

- [ ] **T2 `api-store-serialize`** — the JSON round-trip, in its own module.
  - **Acceptance criteria**: a new `api/src/serialize.js` exporting `serialize(store)` and `fromJSON(text, options)`. `serialize` returns the compact JSON of `{"version":1,"items":[…]}` with the items in insertion order. `fromJSON` rebuilds a store with the options it is given (`capacity` included) and the items in the order they were stored; an unknown top-level key in the document is ignored, a missing or `null` `items` list means an empty store, and any `version` other than `1` is refused with a `RangeError`. Malformed JSON is left to `JSON.parse` to refuse.
  - **Owns test**: `api/src/serialize.test.js` (new).
  - **Depends on**: none.
  - **Touches**: `api/src/serialize.js` (new).

- [ ] **T3 `web-duration-format`** — the duration formatter.
  - **Acceptance criteria**: `web/src/format.js` gains `formatDuration(ms)`. Under a minute: `"45s"`, with the seconds as digits and no padding. From a minute: `"1m 05s"`, the seconds always two digits. From an hour: `"1h 05m"`, the minutes always two digits and the seconds dropped. Zero, negative, `NaN` or infinite: `"0s"`. The value is truncated, never rounded up, and the existing `humanSize` is unchanged.
  - **Owns test**: `web/test/duration.test.js` (new).
  - **Depends on**: none.
  - **Touches**: `web/src/format.js`.

- [ ] **T4 `web-grid-span`** — the column span of a widget width.
  - **Acceptance criteria**: `web/src/grid.js` gains `spanFor(width, viewportWidth)`: `"1/3"` is 2 columns, `"1/2"` is 3 and `"1"` is 6, and any other width falls back to `"1"`. Below `BREAKPOINT_PX` every width spans the full row (all `COLUMNS`), whatever it is. `columnsFor` and both constants are unchanged.
  - **Owns test**: `web/test/span.test.js` (new).
  - **Depends on**: none.
  - **Touches**: `web/src/grid.js`.
