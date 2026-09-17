# TODO

Known gaps, deliberate deferrals, and decisions not to re-open. Nothing here blocks
a run; the flow works as documented in `README.md`.

## Decided: the panel repaints on boundaries plus a tick, and chain stays uncapped

The tool streams what each child is doing into an expandable panel, and caps what
reaches the orchestrator. Three limits are deliberate.

- Repaints happen on tool start/end and finished messages — never `text_delta` — plus a
  1 s tick while any child is running. Without the tick the clock would freeze during a
  long LLM call or a long command, which is precisely the stretch a watcher is nervous
  about. The tick is the cheapest signal that the run is alive; the transcript is not.
- `details` holds the tool trail plus the child's last message, capped like `content`.
  Storing every text block was tried and reverted: it duplicated the report in the
  session file, unbounded, to serve prose nobody reads while waiting. The trail and the
  final line answer "is it alive and on what" on their own.
- The cap is 16 KB and applies to single and tasks alone. Chain is uncapped because
  `{previous}` is the handoff between agents: the user seeing the tester's report in
  the panel does not give the implementer that report, so truncating there would break
  the flow instead of saving context.

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
