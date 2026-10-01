# Background subagents

**Status: explored, not implemented.** Everything below was checked by reading the
installed pi and its published types; nothing in the repo was changed but this file.
Two decisions are still open — see [Open decisions](#8-open-decisions). A session that
picks this up should start at [Order of work](#6-order-of-work).

Explored 2026-10-01 against pi 0.99.2 (`pi --version`), on the tree at `f238303`.

## 1. What is wanted

Two goals, and they are one change, not two:

1. **Free the orchestrator's turn while children run**, so a message from the user is
   answered immediately instead of queued behind a whole `chains` dispatch.
2. **See at any moment what each child is doing.**

What pi already gives, so the goal is narrower than it sounds:

- Typing during a blocking dispatch is not lost, it queues: Enter waits for the current
  response and its tool calls, `Alt+Enter` waits for the whole task (`usage.md:40`). So
  goal 1 is about *latency*, not capability.
- The panel in `extensions/antz-subagent.ts` **already shows live progress** — but only
  because the tool blocks. It repaints once a second through the `heartbeat`
  (`:503-507`) → `onUpdate()` (`:496`) → `renderResult`. Once `execute` returns,
  `onUpdate` is dead and `renderResult` runs only when pi repaints the row, so a
  background child is invisible unless something else draws it.

That is why the two goals are one change: background without a new surface for the panel
means going blind.

## 2. What the SDK offers (verified, with how to re-check)

Types are not in the repo — there is no `package.json` or `tsconfig.json` here, the
extension is loaded by pi through jiti and never type-checked. Read them off the
published package:

```bash
curl -s https://cdn.jsdelivr.net/npm/@earendil-works/pi-coding-agent@0.99.2/dist/core/extensions/types.d.ts \
  | rg -n 'sendMessage|setWidget|registerMessageRenderer|WidgetPlacement'
```

| Need | API | Where |
|---|---|---|
| Wake the orchestrator with a finished child's result | `pi.sendMessage(msg, { triggerTurn: true, deliverAs: "followUp" })` | `types.d.ts:1213` |
| Live panel that outlives the tool call | `ctx.ui.setWidget(key, string[] \| factory, { placement })`, `placement: "aboveEditor" \| "belowEditor"` | `types.d.ts:47, 101-104` |
| Render that message as the panel, not as plain text | `pi.registerMessageRenderer(customType, renderer)` | `types.d.ts:1207` |
| A `ctx` is available inside `execute` | `ExtensionToolContext extends ExtensionContext`, which carries `ui`, `mode`, `hasUI`, `cwd`, `signal` | `types.d.ts:215-222, 269` |
| `pi -p` and eval runs have no UI | `ctx.hasUI` is false in `print`/`json`; the widget must be a no-op there, like the current heartbeat | `types.d.ts:219` |

**The decisive fact — abort semantics.** The `signal` that `execute()` receives is the
run's signal, and it is **not aborted when the run finishes normally**, because
`finishRun()` clears the active run without aborting its controller:

```bash
curl -s https://raw.githubusercontent.com/earendil-works/pi/v0.99.2/packages/agent/src/agent.ts \
  | rg -n -B2 -A8 'get signal\(\)|private finishRun'
# agent.ts:336  get signal() { return this.activeRun?.abortController.signal }
# agent.ts:550  private finishRun(): void { … this.activeRun = undefined; }   // no abort()
```

So a child tied to that signal survives the end of the dispatching turn and dies only if
the user aborts *that* turn (Ctrl+C / Esc). That is exactly the behaviour wanted, and it
comes for free — but it is the one fact that must be re-checked after a pi upgrade, since
it is the whole safety story for orphan children.

**What does not exist:** no background/detached tool primitive in pi core (the shipped
`examples/extensions/subagent/` is foreground-only, and the 0.99.2 changelog mentions the
subagent *example* only), and no way to re-render a finished tool row from outside its own
`renderResult` — the documented hooks are the widget and the message renderer.

## 3. Design

### Surface

`background: true` as a **modifier on the four shapes that already exist**, not a fifth
shape. The exclusivity check stays as it is (`:491-493`), so the model still sees one tool
and one sentence of description, and `modeOf` (`:170`) is untouched.

```
{ chains: [[tester, implementer], …], background: true }
→ content: "antz_subagent chains: job-1 running (8 runs)"     // returns in milliseconds
→ details.runs[] with every run status "running" or "queued"
```

### Machinery

- **A module-level registry** (`Map<string, AgentRun>` plus the job → runs mapping) keeps
  the live state; `AgentRun` (`:113`) and its `queued|running|done|failed` already carry
  everything the panel needs, including `usage`, `skillsUsed`, `startedAt`/`endedAt`.
- **Completion** is one message per finished job:

  ```ts
  pi.sendMessage(
    { customType: "antz-subagent", content: [{ type: "text", text }], display: true, details },
    { triggerTurn: true, deliverAs: "followUp" },
  );
  ```

  `content` is the same capped text today's tool result carries (`capOutput`, `:311`), and
  `details` is the same `AntzDetails`, so `eval/agents.sh` can read the run list from it
  unchanged in shape. `triggerTurn: true` is what starts a turn when the session is idle;
  `deliverAs: "followUp"` is what makes it wait for the run in progress instead of
  cutting into it.
- **The live panel** is the body of `renderResult` (`:650-740`) extracted to a pure
  `panelLines(details, expanded, theme)` and rendered by both the tool row and the widget.
  Key `antz-subagents`, `placement: "aboveEditor"`, refreshed on the existing 1 s tick
  while any run is alive, cleared with `setWidget(key, undefined)` when none is. Guarded
  by `ctx.hasUI`, like the heartbeat.
- **Cancellation and orphans.** Keep the existing `signal` wiring in `runAgent`
  (`:419-420`) — it is what makes Ctrl+C stop the children. Add the pieces it implies:
  abort everything on `session_shutdown` (the docs require long-lived resources to be
  closed there, and a reload/session switch kills the closures), and one explicit way to
  stop a job without aborting the turn (a `{ cancel: "job-3" }` param, or a `/antz-cancel`
  command — the choice is cheap but must exist, since aborting is otherwise the only
  lever).
- **A duplicate guard.** With background the orchestrator does not see a result before
  deciding what to do next, so it can send the same task twice — which is exactly what the
  attempt cap measures and what `payload_keys` (`eval/run.sh:119`) looks for. Cheapest
  honest guard: refuse a dispatch whose `(agent, task)` pair matches a live run, and say
  which job it collides with.

### Files

- `extensions/antz-subagent.ts` — all of the above. This is the only *product* file the
  mechanism lives in; `agents/*.md` and `skills/` are not touched by it.

## 4. What it breaks

| Site | What happens |
|---|---|
| `prompts/antz.md`, step 4 | "Mark `[x]` when the chain ends" and "the task is proved by one command … that command comes from the tester" assume the report is in hand. In background it arrives later, as a message. Needs one sentence, and a rule for what to do when the user speaks mid-step-4 (today only clarify talks to the user). |
| `eval/agents.sh:35` | Reads `toolResult[]` with `toolName == antz_subagent`. Background spend and steps would read as **zero, without failing** — wrong numbers in silence. |
| `eval/run.sh:168` (`usage_of`, selector at `:171`) | Same filter: `select(.role == "toolResult" and .toolName == "antz_subagent")`. |
| `eval/dispatch.mjs:29` | The fake `pi` object needs `sendMessage` (and a `registerMessageRenderer` no-op); `:95` builds a bare ctx, which needs `hasUI`/`ui` for the widget path. |
| `eval/stubs/node_modules/@earendil-works/pi-coding-agent/index.js` | Header says it: "Adding an import or an SDK method to the extension means adding it here." Only needed if a new *named export* is imported; `sendMessage`/`setWidget` are instance methods and belong in `dispatch.mjs`. |
| `eval/README.md` | "What each agent spent" and "The dispatch harness" sections describe the two readers above. |

Unaffected, and worth stating so nobody rewrites them: `sequence` (`run.sh:98`),
`payload_keys` (`:119`), `attempts_by_file` (`:138`), `parallel_dispatches` (`:154`) all
read the *tool call arguments*, so routing, the attempt cap and the parallelism count keep
their meaning. Cache-and-cost grading of `run.sh M` is also unaffected as long as step 3
below lands with steps 1-2.

## 5. Code sketch (the two non-obvious pieces)

```ts
// Module scope, next to `modelRuntime()`. `outputs` is indexed like `runs`; `abort`
// is the job's own controller, aborted by the tool call's `signal` and by a cancel.
const jobs = new Map<string, { runs: AgentRun[]; outputs: string[]; mode: AntzDetails["mode"]; abort: AbortController }>();

// At the end of a background dispatch, once per job:
const report = (jobId: string) => {
  const job = jobs.get(jobId);
  if (!job) return;
  const details: AntzDetails = { mode: job.mode, runs: job.runs, skills };
  const failed = job.runs.some((run) => run.status === "failed");
  const text = job.runs
    .map((run, index) => `[${run.agent}] ${run.status === "failed" ? `FAILED — ${run.error}` : job.outputs[index]}`)
    .join("\n\n---\n\n");
  pi.sendMessage(
    { customType: "antz-subagent", content: [{ type: "text", text: capOutput(text, MAX_OUTPUT_BYTES) }], display: true, details },
    { triggerTurn: true, deliverAs: "followUp" },
  );
  jobs.delete(jobId);
  paintWidget();               // clears this job's rows
};
```

```ts
// The widget: the same lines as the tool row, one key, cleared when the last job ends.
const paintWidget = () => {
  if (!ctx.hasUI) return;                       // print/json: nothing to draw
  const live = [...jobs.values()];
  const runs = live.flatMap((job) => job.runs);
  ctx.ui.setWidget("antz-subagents", runs.length ? panelLines({ mode: live[0].mode, runs }, false, theme) : undefined);
};
```

The catch to respect: `panelLines` needs a `theme`, and a *captured* `ctx` can go stale
after `/reload`, `/new` or a session switch. Keep the widget cheap and re-derive it from
the freshest ctx (`session_start`, `turn_start`), or wrap the call in `try/catch` and drop
the capture on failure.

## 6. Order of work

Each step is verifiable on its own; nothing is installed or paid for until step 5.

1. **Widget only, foreground untouched.** Extract `panelLines` from `renderResult`, add the
   widget for the runs of the in-flight tool call. `./eval/dispatch.sh` and
   `./eval/prompts.sh` must stay green (`prompts.sh` fails if a tool creeps into
   `prompts/antz.md` — this step does not touch it).
2. **The background modifier.** Registry, handle in `content`, `sendMessage` +
   message renderer, `session_shutdown` cleanup, duplicate guard, cancel path. Extend
   `eval/dispatch.mjs` (and its fake `pi`/ctx) with checks: returns immediately while the
   children are still `running`; the completion message carries `details.runs[]` with
   usage; the four-agent cap still holds; an identical dispatch is refused; `cancel` stops
   a job. `dispatch.sh` stays free and deterministic, so this is where the behaviour is
   proved.
3. **The two readers.** `eval/agents.sh` and `eval/run.sh:usage_of` learn the
   `antz-subagent` custom message as a second carrier. Prove it on a session that has both
   kinds of dispatch: the numbers must not move for a foreground run and must not be zero
   for a background one.
4. **The flow sentence.** `prompts/antz.md` step 4: what to do while a job is in flight,
   and what a mid-run message from the user means. Keep it to a rule, not a contract.
5. **A real run.** Install (`./adapters/pi/install.sh`, then `/reload`), `/antz` in a
   sandbox on a multi-task plan, and read it back with
   `./eval/agents.sh --summary <session.jsonl>`. This is also the only thing that can
   close the three open questions in `AGENTS.md`, so it is worth doing after the change
   rather than before.

## 7. Risks

- **Silent zeros.** The one failure mode that looks like success: the instruments keep
  parsing and report nothing spent. Steps 1-3 are one release; landing 1-2 without 3 is
  worse than not shipping.
- **Orphan writers.** The user aborts and immediately re-runs `/antz`: children of the
  first run may still be editing tests or implementation while the new run dispatches its
  own. Mitigated by the inherited signal and by aborting on `session_shutdown`, but only
  if the cancel path actually exists.
- **Duplicate work.** See the guard in §3. Without it, background weakens a rule the cap
  currently enforces by construction.
- **Budget.** `extensions/antz-subagent.ts` is 740 lines today. A registry, a widget
  painter and a completion path is real growth in pi's own convention; it is defensible
  as a capability (not a rule, not a shape), but it needs a reason in the commit message,
  per the design principle in `AGENTS.md`.
- **Extra turns.** Every completion wakes the model, so a run gains turns relative to
  today's one-return-per-dispatch. `run.sh M` measures the shared prefix; if cache reuse
  moves, it will show there.

## 8. Open decisions

Asked and left unanswered on 2026-10-01; both need a human call before step 2.

1. **Scope.** (a) background + widget + the eval readers, (b) widget only, leaving the
   dispatch blocking, (c) background + widget but no eval update, accepting the silent
   zeros, (d) nothing.
2. **Mid-run user messages.** With background, the user *can* interject at step 4. Does
   the orchestrator (a) get a rule in `prompts/antz.md` the way clarify has one, (b) just
   answer and go back to waiting, or (c) answer questions only, taking no action on the
   plan until the verdict?

## 9. Non-goals

- A navigable fleet view, live mid-run steering of a child, resumable child sessions, or
  scripted workflows. Those are `@tintinweb/pi-subagents`' territory and do not fit here.
- Adopting a third-party subagent package. The dispatch tool is antz's own, in-process
  through the SDK, so that `tools:` and `model:` are enforced by the SDK and the run has
  no extensions. A package would bring its own orchestrator and fight
  `setAntzToolActive` (`:51`). The packages below are references, not candidates:
  `npm:simple-subagents` (job ids, `subagent_status`/`subagent_control`, `/subagents`
  dashboard), `npm:@tintinweb/pi-subagents` (background by default, FleetView, steering),
  `npm:@pi-vault/pi-subagents` and `npm:pi-subagents-lite` (`run_in_background`),
  `npm:@bacnh85/pi-subagent` (in-process sessions, like antz).
- Changing what `sequence`, `parallel_dispatches`, `payload_keys` or `attempts_by_file`
  measure.
