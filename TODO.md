# TODO

Known gaps. Nothing here blocks a run; the flow works as documented in `README.md`.

## Parallel chains

`prompts/antz.md` says plan tasks may run in parallel, but the tool's `tasks` mode
parallelizes single agents only. Chaining tester→implementer per task relies on the
model emitting several `chain` calls in one message, which pi runs concurrently.
If that ever proves fragile, the tool needs an explicit parallel-chains shape.
