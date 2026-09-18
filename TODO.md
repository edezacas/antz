# TODO

Known gaps. Nothing here blocks a run; the flow works as documented in `README.md`.

## Parallel chains

`prompts/antz.md` says plan tasks may run in parallel, but the tool's `tasks` mode
parallelizes single agents only. Chaining tester→implementer per task relies on the
model emitting several `chain` calls in one message, which pi runs concurrently.
If that ever proves fragile, the tool needs an explicit parallel-chains shape.

## Repair path never exercised on a real run

Every real `/antz` run so far has ended in a PASS on the verifier's first round, so
half the flow is documented but unobserved: no test sent back to `antz-tester`, no
implementation sent back to `antz-implementer`, neither the three-attempt cap nor a
re-plan has ever fired. The 2026-09-18 `stavia` run is the latest example — 17
dispatches, 8 tasks, 0 repairs — so it is evidence that the flow plans and executes,
not that it recovers. `eval/` grades the repair loop as a rate over `RUNS`, which is
not the same as watching it work once. What would close it: one real run where
verification blames the test, and one where it blames the implementation.
