# eval — does the repair loop actually work?

`run.sh` provokes the one part of antz a normal run almost never exercises: the repair loop,
which is prompt text (`prompts/antz.md` steps 4 and 5) and so cannot be asserted on like code.
It seeds a fault in a sandbox, runs `/antz` against it, and reads which agent the repair was
routed to. The verdict is model judgement, so it is a rate over runs and not a boolean: one
green run proves nothing.

`run.sh` is the only instrument that calls a model. `prompts.sh`, `dispatch.sh`,
`judge.test.mjs`, `rejudge.sh` and `agents.sh` cost seconds and no tokens. What the eval has
already shown — the batches, the post-mortems, the scenarios retired — is `FINDINGS.md`,
beside this file, kept out of this one so that this one stays a manual.

## The scenarios

`/antz` routes on what is on disk, so the eval writes the state instead of running the earlier
phases: each sandbox gets `.antz/` with `00-recon.md`, `01-spec.md` and `02-plan.md` and a plan
whose tasks are all `[x]`, which sends `/antz` straight to verification. A/B/C/D therefore run
about three dispatches; `M` and `S` seed an unchecked task and enter at step 4, so the
tester → implementer chain runs first. The trace is the dispatch order, read from the session
file (`pi --session`): the sequence of agents *is* the routing. The `.gitignore` that holds `*`
is kept as `scenarios/spec/antz.gitignore` and renamed on copy: as a real `.gitignore` it would
hide the seed — itself included — from this repo.

| | Seeded state | Contract |
|---|---|---|
| **A** | test faithful to the criteria, implementation violating them | `verifier → implementer → verifier`, `.antz/` deleted, `docs/decisions/pagination.md` written |
| **B** | implementation faithful, test contradicting the criteria | `verifier → tester → verifier`, same end state |
| **C** | A, with a watcher re-injecting the fault every 2 s | ≤ 3 repairs, then stop: `.antz/` untouched, `03-verdict.md` written, no decision |
| **D** | green and correct, but a needless abstraction: a one-implementation policy class behind a wrapper and a factory | `verifier → implementer → verifier`, same end state |
| **M** | fixed recon, spec and plan, no fault, and a realistic `AGENTS.md` | four independent chains dispatched together and verified; the measurement is its usage row |
| **S** | one task whose acceptance cannot be met: `{ limit: 1000 }` must return 100 elements *and* throw a `RangeError` | the trace: no payload dispatched twice, the chain reached, no `TIMEOUT` hit |

A and B differ only in which side respects the criteria, which isolates blame attribution from
"make the red test go away". D routes like A, but its suite is green, so a verifier that stops
at "the tests pass" fails it: D is the one arm that measures the architecture check. `S`
asserts the trace and only reports the ending, because a task reframed to drop the criterion
the prompt contradicts is satisfiable and closes in PASS.

What A, B and D pin is the routing — the first agent after the opening verification is the one
the verifier blamed, and the other side is never touched — plus the closing verification and
the end state. Everything else is reported rather than counted: a trailing `verifier` round and
repeats on the blamed side are tolerated, because the cap counts attempts, not rounds. A single
`verifier` dispatch that repairs the fault itself fails instead, since no blame was reported and
nothing was routed. Deleting `.antz/` is the orchestrator's job on PASS, never the verifier's.
In `C`, an agent that judges the fault unfixable and stops is a PASS — that is what *never
grind* asks for.

## Running it

```bash
./run.sh                            # A, B, C and D, once each
./run.sh A B                        # only those
RUNS=5 ./run.sh                     # repetitions, for a rate
TAG=before RUNS=5 ./run.sh M        # label a phase, for a before/after
TIMEOUT=3000 ./run.sh C             # seconds per run, default 1800
SKIP_FRESHNESS=1 ./run.sh           # grade the install knowingly
node --test judge.test.mjs          # the judge, free
./rejudge.sh                        # re-make every verdict from out/, free
./agents.sh out/M-1.session.jsonl   # what each agent spent
```

A few minutes to twenty per run, depending on the repair rounds. `run.sh` grades **what is
installed** in `~/.pi/agent` and refuses to run unless the working tree matches it (`model:`
excepted) — edit `prompts/` and forget `./adapters/pi/install.sh` and you would grade the
previous antz. It runs `pi` inside the sandbox and discards the run if the session's `cwd` is
anywhere else. A scenario `judge.mjs` has no contract for is refused before anything is
spawned. Node is required: the verdict is `judge.mjs`.

Each run appends a row to `out/results.tsv` (verdict and trace), one to `out/usage.tsv`
(tokens) and one per agent to `out/agents.tsv`, and leaves the log, the session and a compact
snapshot of the end state in `out/<scenario>-<run>.state/` — all gitignored. The sandbox is
outside the repo, under `${ANTZ_EVAL_SANDBOX:-${TMPDIR:-/tmp}/antz-eval}`, because from inside
`eval/` the harness and the comments that name the fault are one directory up, and an agent
read them. To reclaim the megabytes and keep the numbers:

```bash
find out -mindepth 1 -maxdepth 1 ! -name '*.tsv' -exec rm -rf {} +
rm -rf "${ANTZ_EVAL_SANDBOX:-${TMPDIR:-/tmp}/antz-eval}"
```

That takes the snapshots with it, and `rejudge.sh` then falls back to what the session alone
can settle — it says so, and returns `UNKNOWN` rather than a PASS it cannot support.

## Which scenarios a change needs

Each scenario owns a contract no other asserts, so a change needs the arm that can fail on it
and not the rest. This is the inner loop; the full `A B C D` is the outer one, before an
install or when an edit moves the routing broadly.

| The edit | The run that can see it |
|---|---|
| `prompts/antz.md` — blaming a side and routing the repair | **A, B** |
| `prompts/antz.md` — the attempt cap, *never grind*, cut-or-reframe | **C, S** |
| `prompts/antz.md` — who closes the run and deletes `.antz/` | **A, B, C** |
| `code-design` in agent-skills | **D** |
| `agents/antz-verifier.md` | **C**, and **A** or **B** |
| `agents/antz-tester.md`, `antz-implementer.md` — the handover | **M, S**, and `antzReads` in `agents.tsv` |
| `extensions/antz-subagent.ts` | **`dispatch.sh`** (free), then **M** |
| `tdd` in agent-skills, the test the tester writes | **M** |
| docs, eval or README alone | none — the free instruments only |

A single arm is 5–12 minutes and ~120–430 k tokens, against ~30 minutes and ~850 k for
`A B C D`. Editing `code-design` in agent-skills and running all four is ~690 k tokens that cannot
fail on the edit, because only `D`'s seed makes the architecture check reachable. `D` and `M` grade
whatever copy is installed, so reinstall the skill after editing it: the tree no longer pins either.
The map is `judge.mjs` read backwards: it says which arm *can* observe an edit, not that the edit
is safe.
One paragraph of `prompts/antz.md` can carry two rows — union them, and keep the full batch
when in doubt.

## The instruments

### `prompts.sh` — the flow's wiring, free

Checks in a second what the design already declares: the line budgets (9–13 per agent, 32 for
`prompts/antz.md`); that every `.antz/NN-name.md` `/antz` routes on is one an agent writes, and
every artifact an agent writes is routed on; that `prompts/antz.md` names no dispatch tool,
which is what keeps its body byte-identical on all three clients; and that every agent declares
the `name`, `description` and `tools` pi needs. It says nothing about prose.

### `dispatch.sh` — the tool, free

Substitutes the pi SDK with stubs (`stubs/`, three packages) and drives
`extensions/antz-subagent.ts` directly, so the tool's own behaviour is asserted rather than the
model's judgement: the four shapes (`agent`, `tasks`, `chain`, `chains`, and two at once
refused); the concurrency cap of 4, asserted on live fake sessions rather than the clock;
`{previous}` reaching the next step of its own chain and no other's; a failing chain leaving its
siblings intact and marking the steps behind it `not run`; a `read` of a discovered `SKILL.md`
marked used on the run that did it and not on its siblings; and both renderers, including a
half-streamed call. The fake agents are the input; everything else asserted is the tool's.

It proves nothing about a real model, and `run.sh` is still the only instrument that grades
what is installed. A new import in the extension needs a new export in the stubs.

### `judge.mjs` and `rejudge.sh` — the verdict, free to re-make

A verdict is a pure function of the session (trace, payloads, concurrency shape, usage) and the
end state (`.antz/` present, `03-verdict.md`, the decision document). `session.mjs` reads the
first, `judge.mjs` decides, and neither spawns anything. `run.sh` produces both inputs and calls
the judge; `rejudge.sh` points it at every trace in `out/` and prints what changed, for seconds
and no model:

```bash
./rejudge.sh
  S/2: FAIL -> PASS  (trace-only)
  5 row(s) changed; written to out/rejudged.tsv
```

It never overwrites `results.tsv`: that is the record of what was paid for, judged the way it
was judged at the time. Each row names which of three states it read — `snapshot` (the `.state/`
survives, so the full verdict), `sandbox` (no snapshot, but the sandbox is still under
`$ANTZ_EVAL_SANDBOX`), or `trace-only` (only the trace, which comes back `UNKNOWN` rather than a
PASS the session cannot support). The counting rules are `judge.test.mjs`'s fixtures;
`FINDINGS.md` has the ones that were wrong and what each cost. The judge is not the flow: a
contract that is wrong is wrong however cleanly it is computed.

## Reading a run

`usage.tsv` totals a dispatch, so a `chains` call of eight agents is one row and the role
disappears. `agents.tsv` keeps one row per agent run — agent, status, turns, reads, `antzReads`,
tokens, seconds, skills, tools — read from the same session by `agents.sh`, which also works on
any session, a real one included:

```bash
./agents.sh --summary out/M-1.session.jsonl
./agents.sh --summary ~/.pi/agent/sessions/<cwd>/<session>.jsonl
```

- **`turns`** is the tool calls, and the LLM round trips — the cost a token total hides. The
  fixture's verifier spends 10–20; the same role on a real repository spent 102 in one round,
  and a round that size is the one a provider cuts short.
- **`antzReads`** counts the reads under `.antz/`, which the flow wants at zero for a tester and
  an implementer: they are handed their task. A real run's testers spent 34.
- **`seconds`**, against the dispatch's wall clock, says whether the time was the model or a
  suite that takes 40 s to boot.

The two files read the same sessions by different paths, so the summary closes with a reconcile
line: the dispatch totals against the sum of the agent rows. They agree; a dispatch that errored
has no agent rows, which is the usual reason they would not.

### Measuring cache reuse (`M`)

`M` is the arm that measures tokens: a fixed plan, so every run does the same work, and a
realistic 131-line `AGENTS.md` so the shared prefix is a measurable share of them. Its four
tasks are independent, so the verdict also asserts the parallel shape — at least one dispatch
carrying more than one unit of work, which is when pi runs them concurrently. Label the phases
and compare the `usage.tsv` rows:

```bash
TAG=before RUNS=5 ./run.sh M
# apply the change, then ./adapters/pi/install.sh
TAG=after  RUNS=5 ./run.sh M
```

What to look for: `input` down and `cacheRead` up, with `withUsage` equal to `calls`. Two
caveats: a provider that reports no cache leaves every token column at zero, and one without
pricing reports `cost: 0` — compare tokens, not money.

## What it does not prove

- **Not the happy path.** Recon, clarify and planning are out: A/B/C start from a feature that
  already exists and already fails, D from one that is green, and `M` skips planning. Clarify is
  missing everywhere, because `pi -p` cannot answer it.
- **Not a real repo.** The fixture is one small module with three tests; a TypeScript codebase
  with a slow suite is a harder judgement for the verifier.
- **Not the model.** The agents carry `model:` pins, so a run measures a model pairing.
- **Not a stopwatch.** The parallel assertion counts the units of work a dispatch carried, not
  that they overlapped. Each agent's `startedAt` and `endedAt` are in the session for a reader
  who wants to check by hand.
- **Not the judgement behind `S`.** A task cut in two and one nudged by a word both read as "not
  resent unchanged", and a reframe that closes in PASS cannot be told from a cut left undone.
  `S` asserts the rule's letter; the per-agent counts in `agents.tsv` are what a reader checks
  by hand when it matters.
- **Not stable across antz edits.** This is the regression net for `prompts/`, `agents/` and
  `skills/`, so run it after touching them, with the same `RUNS`.

## Adding a scenario

Add `scenarios/<X>/src/…` for the files that differ from `fixture/`, a `case` in `judge.mjs`'s
`verdict`, and its decision document in `DECISION_OF` if it writes one. The seed and the spawn
stay in `run.sh`; only the verdict lives in the judge. `prompts.sh` and `judge.test.mjs` are
where a wiring mistake should surface before anything is paid for.

A scenario that seeds its own plan lives in `scenarios/<name>/seed/` with its own `run.sh`
branch, the way `stop` does, and needs its own prompt if its plan belongs to another feature —
`/antz` refuses to resume a plan it was not asked for. Keep the fixture *blind*: no comment,
filename or seed text may hint at which side is at fault, or the eval measures the hint instead
of the loop. `C` is the example of one that borrows another scenario's files and adds a
perturbation rather than restating them.

## Running a ladder of states (`measure.sh`)

Comparing two states is a loop — check out, install, run — and `measure.sh` holds the harness
constant while it does it: only `prompts`, `agents`, `skills` and `extensions` come from the
state under test, and the tree is put back on its branch on the way out.

```bash
./measure.sh before master  A:2 B:1 D:1    # the baseline
./measure.sh item2  d7dad3c M:2             # one change on top of it
```

The tag labels the rows in `results.tsv`, `usage.tsv` and `agents.tsv`, which is what makes two
batches comparable afterwards. A FAIL is a result, not an error, so a scenario outside its
contract does not stop the ladder.
