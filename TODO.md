# TODO

Known gaps. Nothing here blocks a run; the flow works as documented in `README.md`.

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
