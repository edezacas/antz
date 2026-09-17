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

## Decided, don't re-open: the installer copies, it is not a pi package

`install.sh` reproduces the manual one-liner's flat layout in pi's agent dir, so
`findAgentFile` and the children's loading of the host repo's skills and `AGENTS.md` keep
working with no change to the extension. `pi install git:` was the alternative and gives
`pi update --extensions`, `pi remove` and `pi config` for free. It was left out because
`agents/` is not a pi resource type: a clone lands in `~/.pi/agent/git/<host>/<path>` where
`findAgentFile` does not look, so the extension would need a third lookup path relative to
its own file, and it is not established that a child's `DefaultResourceLoader` sees a
package's `skills/antz-tdd` — losing the red/green rules silently is a worse failure than
not having an update command. Revisit if distribution through pi.dev/packages starts to
matter; the relative `../agents` lookup is worth adding then, and it is compatible with the
copy layout.

Three shapes are deliberate too. `--uninstall` is a flag rather than a second script: one
artifact, and the removal list sits next to the install list it mirrors. There is no state
file: what antz installed is derivable from the file names, so a reinstall is just a copy
and nothing has to be kept in sync with the tree. And nothing is ever read from stdin —
under `curl | bash` stdin is the script itself — so every choice is a flag.

## Decided, don't re-open: a reinstall keeps the `model:` line, with no flag to reset it

The README tells the user to pin a model by editing an agent file, which makes that file
half antz's and half theirs. The installer resolves it by copying upstream's file and
putting the local `model:` line back — a pin, and nothing else, survives an upgrade. The
pin is local state that is not tracked anywhere, so it is read from the file that is
about to be overwritten rather than from a state file.

Two consequences are accepted. Once a pin is installed there is no way to tell it from a
value antz shipped, so an agent whose `model:` changes upstream keeps the old one until
the line is deleted and the installer run again — the escape hatch is `sed -i
'/^model:/d'`, not a flag, because a flag is another thing to document and the line is
already editable by hand. And only `model:` is preserved: `tools:` and `description:` come
from upstream every time, so a stale local override cannot contradict an agent whose body
changed with it.

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
