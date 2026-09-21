# eval — does the repair loop actually work?

`run.sh` measures the one part of antz that a normal run almost never exercises:
the repair loop. Everything else in this repo is prompt text, and the loop is
prompt text too — `prompts/antz.md` steps 4 and 5 — so it cannot be asserted on
like code. It can be *provoked*.

`run.sh M` is the exception: it runs the per-task chain and records what each
subagent spent, so the same harness measures prompt caching across agents.

`dispatch.sh` is the other instrument, and the mirror image. Instead of
provoking prompt text with real agents, it checks the one file of code that is
not prompt text — `extensions/antz-subagent.ts` — with the pi SDK stubbed out.
Free, deterministic, about a second, and it grades the **working tree** where
`run.sh` grades the install. It has its own section at the end of this file.

**This is not a test, it is an eval.** The verdict depends on model judgement, so
the result is a rate over N runs, not a boolean: it costs money and minutes, and
one green run proves nothing — the same way a first-try PASS on a real feature
says nothing about failure handling.

## How it measures

`/antz` routes on what is on disk, so the eval writes the state instead of
running the earlier phases. Each sandbox gets `.antz/` with `00-recon.md`,
`01-spec.md` and `02-plan.md`, and a plan whose tasks are all `[x]` — which sends
`/antz` straight to step 5, verification. One run is therefore about three
dispatches, not six phases. (The `.gitignore` holding `*` that `antz-scout` would
write is kept as `scenarios/spec/antz.gitignore` and renamed on copy: as a real
`.gitignore` it would hide the seed — itself included — from this repo.)

The trace is the dispatch order, read out of the session file (`pi --session`).
The sequence of agents *is* the routing, and the routing is what a failure
decides. Two different red test suites tell the loop apart:

| Scenario | Seeded state | Contract asserted |
|---|---|---|
| **A** | test faithful to the criteria, implementation violating them | `verifier → implementer → verifier`, `.antz/` deleted, `docs/decisions/pagination.md` written |
| **B** | implementation faithful, test contradicting the criteria | `verifier → tester → verifier`, same end state |
| **C** | A, plus a watcher re-injecting the fault every 2 s | ≤ 3 repairs, then stop: `.antz/` untouched and no decision written |
| **M** | fixed recon, spec and plan, no fault, and a realistic `AGENTS.md` | enters at step 4, dispatches the four independent per-task chains in one parallel dispatch, and verifies; the measurement is its usage row, not the routing |

A and B are the same observable — one failing suite — and differ only in which
side respects the acceptance criteria. That difference is the whole experiment:
it isolates blame attribution from "make the red test go away". C is the only way
to reach the cap deterministically; without the watcher, hitting three attempts
depends on the model failing three times on its own.

A trailing extra `verifier` round is tolerated in A and B, because a verifier can
return PASS without writing the decision document, and the orchestrator sends it
back to finish. That is recovery, not a routing fault, and it is reported in the
run's detail rather than counted as a failure. The opposite case is a failure: a
single `verifier` dispatch that ends with the decision written and `.antz/` gone
means it repaired the fault itself, so no blame was reported and nothing was
routed — the loop never ran. Deleting `.antz/` is not the verifier's job at all:
on PASS the orchestrator removes it once the document exists, so a verifier that
forgets costs a round rather than leaving a finished run on disk.

## Measuring cache reuse (`M`)

A/B/C enter at step 5, so they exercise about three dispatches and cannot show a
caching change. `M` seeds recon, spec and a plan whose four tasks are unchecked:
`/antz` enters at step 4, so every run does the same work — the four per-task
tester → implementer chains and the verifier. The plan is fixed on purpose: a
planner-generated one changes between runs, and that movement would be mistaken
for the change under test.

The four tasks are independent, so the verdict also asserts the parallel shape:
at least one dispatch must have carried more than one unit of work — several
chains in one call, or sibling calls in one message, which pi runs concurrently
as well. Tasks walked one call per turn are sequential however green they look,
and `M` is the only scenario positioned to notice.

`M` also replaces the fixture's ten-line `AGENTS.md` with a realistic one. What a
caching change buys is `AGENTS.md`, the skills and the cwd no longer being
recomputed on every agent's first call, so against the fixture's tiny context
that saving is a rounding error. The bigger one makes it a measurable share of
the tokens.

Whatever the verdict, every run appends its subagent totals to `out/usage.tsv`
(separate from `results.tsv`, whose fixed columns predate this): calls to the
tool, how many of those reported usage, and summed `input` / `cacheRead` /
`cacheWrite` / `output`, read from the `usage` pi persists on each `toolResult`.
One call can carry several agents, so `calls` is not the dispatch count; the
trace in `results.tsv` is. `TAG` labels the phase, so the same feature is
measured either side of a change:

```bash
TAG=before RUNS=5 ./run.sh M
# apply the change, then ./install.sh
TAG=after  RUNS=5 ./run.sh M
```

What to look for: `input` down and `cacheRead` up, with `withUsage` equal to
`calls` — the verdict already checks that all four tasks reached the tester and
the implementer. Two caveats — a provider that reports no cache leaves every
token column at zero (`calls` still counts the tool invocations), and a provider
without pricing in `models.json` reports `cost: 0`, so compare tokens, not money.
Runs with long gaps between agents can miss the provider's cache window even
when the change is correct.

## Running it

```bash
./run.sh                       # A, B and C, once each
./run.sh A B                   # only those
RUNS=5 ./run.sh                # five repetitions of each
TAG=before RUNS=5 ./run.sh M   # the full chain, to measure usage
SKIP_FRESHNESS=1 ./run.sh
```

Roughly 2–15 minutes per run depending on how many repair rounds happen; `M` is
at the top of that range because it runs the whole chain. Every run appends a row
to `out/results.tsv` and a usage row to `out/usage.tsv`, and leaves the sandbox,
the log and the session trace in `out/`, all of it gitignored.

The `.tsv` files are the record; the rest is only there to inspect a past run and
costs a few megabytes a batch. To reclaim it without losing the numbers:

```bash
find out -mindepth 1 -maxdepth 1 ! -name '*.tsv' -exec rm -rf {} +
```

It measures **what is installed** in `~/.pi/agent`, not the working tree, and
refuses to run when the two disagree — editing `prompts/antz.md` and forgetting
`./install.sh` would otherwise grade the previous antz. The `model:` line is
excluded from that check on purpose: the installer preserves a local pin.
`pi` is also run from inside each sandbox, and the run is discarded as
meaningless if the session's recorded `cwd` is anywhere else.

## What it does not prove

- Not the happy path: recon, clarify and planning are out of both. A/B/C start
  where a feature already exists and already fails; `M` skips planning too, so
  its workload is identical run to run. Clarify is missing everywhere — `pi -p`
  cannot answer it.
- Not a real repo. The fixture is one 8-line module with three tests, and `M`
  adds four toy helpers; a TypeScript codebase with a slow suite is a harder
  judgement for the verifier.
- Not the model's fault alone: the agents carry `model:` pins, so a run measures
  a particular model pairing. A different pin is a different measurement.
- Not stable across antz edits: this eval is the regression net for `prompts/`,
  `agents/` and `skills/`, so run it after touching them, with the same `RUNS`.
- The parallel assertion is a shape, not a stopwatch: it counts the units of work
  one dispatch carried, which is when pi runs them concurrently. Whether they
  actually overlapped is in the run's own `details` — each agent's `startedAt`
  and `endedAt` are persisted with the session — so it is checkable by hand and
  not checked here.

## What it has shown so far

One `M` run after `chains` was added — four independent tasks, one dispatch:
the orchestrator made **two** tool calls where the pre-`chains` `M` runs made
five, a single `chains` call holding one tester → implementer chain per task,
then the verifier. The four testers started within four milliseconds of each
other, at most 4 agents ran at once (the cap), and 322 s of agent work finished
in 126 s of wall clock. One run says the shape is reachable, not that the model
reaches for it every time.

A second run — interactive, on a sandbox in `/tmp` that entered at step 4 — repeated
it: one `chains` call of four, the four testers starting together, 4 agents at the
cap and 2.3×, so the shape is not an artefact of headless mode. It also showed the
property that makes parallel chains safe: every implementer's task carried its own
tester's report and no chain's text reached another, so `{previous}` is per chain
and not shared state.

Two 10-run batches — five A and five B, run concurrently — with the orchestrator
on `nan/deepseek-v4-flash`, tester and implementer on `nan/glm5.3-flash` and the
verifier on `nan/mimo-v2.5`, a different family from the implementer as the
README recommends:

| `agents/antz-verifier.md` | stuck runs (needed an extra round) | repaired by itself | misrouted |
|---|---|---|---|
| as it was, verifier deleting on PASS | 1 / 10 | 0 / 10 | 0 / 10 |
| reordered, then rolled back | 0 / 10 | 1 / 10 | 0 / 10 |

**Neither row is evidence of an improvement.** Ten runs cannot tell 10% from 0%.
What the first two batches established is the rate itself: the failure the reorder
was chasing — a verifier declaring PASS without writing the decision, which leaves
a finished run that never ends — is roughly a 1-in-10 event, not the 3-in-4 that a
handful of earlier runs on an uncontrolled harness had suggested. Worth knowing
before spending a prompt line on it, and the reason to repeat a batch before
believing any of this.

The reorder moved the verdict to the end and tied the word PASS to a state of the
repo rather than to the report. That bought nothing measurable and put a worse
failure next to it: a verifier taking the shortest path to the state it had just
been told *is* PASS, fixing the test itself and closing the run. One observation
is not a cause, but the trade is bad either way — a stuck run costs one verifier
round and heals on the next `/antz`, while a bypassed loop reports no blame,
routes nothing, and never runs the tester's red-before-green. It was rolled back.

What changed instead is who closes the run: the verifier writes the decision and
stops, and the orchestrator deletes `.antz/` on PASS once that document exists.
That removes the deletion from a prompt that had it as a trailing clause after a
long sentence about something else, and it puts the act with the one who decides
the run is over. A and B still end with the document written and `.antz/` gone; C,
where there is no PASS, is what checks the other half — that the new owner does not
delete it on the way out. One run of each says yes: `verifier → implementer →
verifier` and `verifier → tester → verifier` closing clean, and `verifier →
implementer` three times over, with `.antz/` left where it was and no decision
written.

The batch also turned up the opposite failure, once: a verifier that wrote the test
fix itself and closed the run in PASS. That is the one worth keeping an eye on, and
the reason it gets its own verdict here instead of being reported as a routing
mismatch: the end state looks right, so nothing else would notice that the loop
never ran.

Misrouting never happened: 20 of 20 runs sent a test fault to the tester and an
implementation fault to the implementer, each with the verifier's report as the
task and never to both agents. That is the part the loop exists for.

Two behaviours worth knowing about, both observed, neither in any prompt:

- **The orchestrator does not trust a child's report.** An implementer has
  claimed a green suite while the file was unchanged; the orchestrator re-read
  it, caught the lie, and said so in the next attempt's task.
- **`antz-scout` can appear mid-loop**, as a fresh in-process probe while the
  orchestrator was diagnosing why writes appeared not to persist. It is not part
  of the documented repair loop and it did not consume an attempt.

The shape of the rounds varies between runs — `verifier, implementer ×3, verifier`,
an alternation, and `verifier, implementer ×3` with no closing verification, because
the last attempt was the last one allowed. The assertions do not pin that shape: the
cap is on attempts, and re-verifying between them is left to the orchestrator.

## Adding a scenario

Add `scenarios/<X>/src/…` with the files that differ from `fixture/`, plus a
`case` in `run_once` that asserts the contract. Keep the fixture *blind*: no
comment, filename or seed text may hint at which side is at fault, or the eval
measures the hint instead of the loop. C is the example of a scenario that
borrows another's files and adds a perturbation, rather than restating them.

## The dispatch harness (`dispatch.sh`)

```bash
./dispatch.sh
```

`run.sh` can only see the tool through a real run: it is the wrong instrument for
"did I break the four shapes?", and a run costs money. This one substitutes the
pi SDK with stubs (`stubs/`, three packages, ~40 lines) and drives the tool
directly, so the parts that are the tool's own behaviour rather than the model's
judgement can be asserted on:

- **the four shapes**: `agent`, `tasks`, `chain`, `chains` — including that
  providing two by accident is refused rather than silently resolved;
- **the concurrency cap**: six chains of two steps, with the peak number of live
  fake sessions asserted at 4. The clock would prove less: it can pass on a fast
  machine for the wrong reason;
- **the per-chain handoff**: `{previous}` reaches the next step of the same chain
  and no other chain's text does — the property that makes parallel chains safe;
- **the failure path**: one chain failing leaves its siblings' results intact,
  marks the steps behind it `not run` instead of leaving them queued, and sets
  the error;
- **both renderers**: chain-per-line in the call, `chain.step` numbering in the
  result, and a half-streamed call not throwing while it renders.

The fake agents are the input: they sleep a fixed delay, record the prompt, and
fail on demand. Everything else in the assertions is the tool's.

**What it does not prove.** The SDK and the agents are fake, so it says nothing
about how a real model uses the shapes, what a real subagent does with its task,
or whether the flow works — that is `run.sh` and, above it, the manual run. A new
import in the extension needs a new export in `stubs/node_modules/…/pi-coding-agent`;
a missing name fails the harness by name rather than silently.

`run.sh` remains the only instrument that grades what is *installed*, and the two
are allowed to disagree: this one exists so a change to the tool can be checked
before anything is installed, or paid for.
