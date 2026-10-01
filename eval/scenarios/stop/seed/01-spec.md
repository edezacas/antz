# Spec

Slug: pagination

## Decisions

- `paginate` takes `{ limit, offset }` and returns the window `items[offset, offset + limit)`.
- `limit` is capped at `MAX_LIMIT = 100`: asking for 1000 returns 100 elements, not 1000.
- A `limit` above `MAX_LIMIT` throws a `RangeError`, and the message names the cap.
- An `offset` past the end returns `[]`, it does not throw.

## Assumptions left to the implementation

- The exact name of the cap constant does not matter; the behaviour does.
