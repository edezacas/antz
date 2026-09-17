# TODO

Known gaps, deliberate deferrals, and decisions not to re-open. Nothing here blocks
a run; the flow works as documented in `README.md`.

## Cap per-task output in parallel dispatch

`mapConcurrent` returns every child's full final text and the parallel branch pastes
all of it into the orchestrator's context. One verbose tester or implementer can bloat
the parent's window — `pi-subagents` caps each task (50 KB) for exactly this reason.

Next: truncate each task's text on a byte boundary inside the parallel branch, ~5
lines. Decide the cap, and whether the truncation notice reports how much was dropped.

## Progress streaming for long runs

The tool returns only final text, so a ten-minute antz run is opaque to the user until
it ends. `onUpdate` in `execute` would stream child activity into the TUI.

Next: decide whether watching progress is worth anything for antz. It threads a
stateful callback through all three dispatch modes and changes nothing about how the
orchestrator works.

## Parallel chains

`prompts/antz.md` says plan tasks may run in parallel, but the tool's `tasks` mode
parallelizes single agents only. Chaining tester→implementer per task relies on the
model emitting several `chain` calls in one message, which pi runs concurrently.
If that ever proves fragile, the tool needs an explicit parallel-chains shape.

## Decided, don't re-open: no third-party subagent package

Evaluated 2026-09-17. `pi-subagents` (nicobailon) does run foreground children
in-process like ours, but brings five runtime dependencies (jiti, yaml, acorn, undici,
typebox) and a framework — builtin agents, missions, watchdog, fleet, its own
workflows — that antz deliberately does without; its children also start with a clean
system prompt, so antz's five agents would need rewriting to inherit skills and
`AGENTS.md`. `pi-agent-harness` (baryonlabs) is not an alternative to this extension
but to antz itself: a meta-factory that generates agents, skills and prompts, whose
bundled subagent is a copy of pi's example (child process, CLI flags). Only the local
extension delivers all three at once: no dependencies, in-process dispatch, and a tool
scoped to `/antz`.
