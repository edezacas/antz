# eval — does the repair loop actually work?

`run.sh` measures the one part of antz that a normal run almost never exercises:
the repair loop. Everything else in this repo is prompt text, and the loop is
prompt text too — `prompts/antz.md` steps 4 and 5 — so it cannot be asserted on
like code. It can be *provoked*.

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

A and B are the same observable — one failing suite — and differ only in which
side respects the acceptance criteria. That difference is the whole experiment:
it isolates blame attribution from "make the red test go away". C is the only way
to reach the cap deterministically; without the watcher, hitting three attempts
depends on the model failing three times on its own.

A trailing extra `verifier` round is tolerated in A and B, because a verifier can
return PASS without doing the PASS work (writing the decision, deleting
`.antz/`), and the orchestrator sends it back to finish. That is recovery, not a
routing fault, and it is reported in the run's detail rather than counted as a
failure. The opposite case is a failure: a single `verifier` dispatch that ends
with the decision written and `.antz/` gone means it repaired the fault itself,
so no blame was reported and nothing was routed — the loop never ran.

## Running it

```bash
./run.sh                # the three scenarios, once each
./run.sh A B            # only those
RUNS=5 ./run.sh         # five repetitions of each
SKIP_FRESHNESS=1 ./run.sh
```

Roughly 2–15 minutes per run depending on how many repair rounds happen. Every
run appends a row to `out/results.tsv`, which is the file worth looking at after
`RUNS=5`, and leaves the sandbox, the log and the session trace in `out/`, all
of it gitignored.

It measures **what is installed** in `~/.pi/agent`, not the working tree, and
refuses to run when the two disagree — editing `prompts/antz.md` and forgetting
`./install.sh` would otherwise grade the previous antz. The `model:` line is
excluded from that check on purpose: the installer preserves a local pin.
`pi` is also run from inside each sandbox, and the run is discarded as
meaningless if the session's recorded `cwd` is anywhere else.

## What it does not prove

- Not the happy path: recon, clarify, planning and the per-task red/green chain
  are outside it. It starts where a feature already exists and already fails.
- Not a real repo. The fixture is one 8-line module with three tests; a
  TypeScript codebase with a slow suite is a harder judgement for the verifier.
- Not the model's fault alone: the agents carry `model:` pins, so a run measures
  a particular model pairing. A different pin is a different measurement.
- Not stable across antz edits: this eval is the regression net for `prompts/`,
  `agents/` and `skills/`, so run it after touching them, with the same `RUNS`.

## What it has shown so far

Two 10-run batches — five A and five B, run concurrently — with the orchestrator
on `nan/deepseek-v4-flash`, tester and implementer on `nan/glm5.3-flash` and the
verifier on `nan/mimo-v2.5`, a different family from the implementer as the
README recommends:

| `agents/antz-verifier.md` | stuck runs (needed an extra round) | repaired by itself | misrouted |
|---|---|---|---|
| as it stands | 1 / 10 | 0 / 10 | 0 / 10 |
| reordered, then rolled back | 0 / 10 | 1 / 10 | 0 / 10 |

**Neither row is evidence of an improvement, and the second one was rolled
back.** Ten runs cannot tell 10% from 0%. What the batch established is the rate
itself: the failure the reorder was chasing — a verifier declaring PASS without
writing the decision or deleting `.antz/`, which leaves a finished run that never
ends — is roughly a 1-in-10 event, not the 3-in-4 that a handful of earlier runs
on an uncontrolled harness had suggested. Worth knowing before spending a prompt
line on it, and the reason to repeat a batch before believing any of this.

The reorder moved the verdict to the end and tied the word PASS to a state of the
repo rather than to the report. That bought nothing measurable and put a worse
failure next to it: a verifier taking the shortest path to the state it had just
been told *is* PASS, fixing the test itself and closing the run. One observation
is not a cause, but the trade is bad either way — a stuck run costs one verifier
round and heals on the next `/antz`, while a bypassed loop reports no blame,
routes nothing, and never runs the tester's red-before-green. A prompt change needs
a reason rather than a reflex, and there was no reason here. The `agents/` file is
back to what it was; only this eval and its verdicts changed.

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

The shape of the rounds varies between runs — `verifier, implementer ×3,
verifier` in one, an alternation in another — which is the prompt leaving the
orchestrator free to re-verify between attempts or not. The assertions do not
pin that shape, only the cap and the outcome.

## Adding a scenario

Add `scenarios/<X>/src/…` with the files that differ from `fixture/`, plus a
`case` in `run_once` that asserts the contract. Keep the fixture *blind*: no
comment, filename or seed text may hint at which side is at fault, or the eval
measures the hint instead of the loop. C is the example of a scenario that
borrows another's files and adds a perturbation, rather than restating them.
