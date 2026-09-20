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

## Client-agnostic prompt assembly

Keeping the agent's body out of the child's system prompt is what lets the five
agents share one cached prefix. `extensions/antz-subagent.ts` does that in
process: it prepends the body to the task when prompting the child, so the body
never enters the orchestrator's context and `prompts/antz.md` does not change.
That is pi-only. The original design put the concatenation in a `build_task.sh`
installed in the agent dir and invoked by the orchestrator, so any harness with
bash could assemble the same task. Not implemented: the body would then pass
through the orchestrator's context on every dispatch, and it only helps a harness
that can suppress its own agent-file injection (Claude Code's `Task` may not), so
the caching win may not transfer anyway. Revisit only if a second harness is a
real target, and note that then the body has to leave the harness registration
files too, not just the system prompt.
