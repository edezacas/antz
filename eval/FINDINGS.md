# FINDINGS — what the eval has already shown

The record behind `README.md`: what was paid for, what came back null, and the scenarios
retired. Nothing here is needed to run the eval — it is what a future session reads before
deciding a measurement is worth repeating. Each entry keeps its result and its numbers; the
narration it was gathered from is in git history.

## The parallel shape (`M`)

One `M` run after `chains` was added: the orchestrator made **two** tool calls where the
pre-`chains` runs made five — a single `chains` call holding four tester → implementer chains,
then the verifier. Four agents ran at once (the cap), and 322 s of agent work finished in 126 s
of wall clock. A second run, interactive, repeated it, so the shape is not an artefact of
headless mode. One run says the shape is reachable, not that the model reaches for it every
time.

That second run also showed the property that makes parallel chains safe: every implementer's
task carried its own tester's report and no chain's text reached another, so `{previous}` is
per chain and not shared state.

## The repair loop (A/B, 20 runs)

Two 10-run batches, five A and five B run concurrently, orchestrator on
`nan/deepseek-v4-flash`, tester and implementer on `nan/glm5.3-flash`, verifier on
`nan/mimo-v2.5` — a different family from the implementer, as the README recommends:

| `agents/antz-verifier.md` | stuck runs (needed an extra round) | repaired by itself | misrouted |
|---|---|---|---|
| as it was, verifier deleting on PASS | 1 / 10 | 0 / 10 | 0 / 10 |
| reordered, then rolled back | 0 / 10 | 1 / 10 | 0 / 10 |

**Neither row is evidence of an improvement**: ten runs cannot tell 10% from 0%. What they
established is the rate — a verifier declaring PASS without writing the decision, which leaves a
finished run that never ends, is roughly a 1-in-10 event, not the 3-in-4 a handful of earlier
runs on an uncontrolled harness had suggested. That is why a batch is repeated before anything
is believed.

The reorder moved the verdict to the end and tied PASS to a state of the repo rather than to a
report. It bought nothing measurable and put a worse failure next to it — a verifier taking the
shortest path to the state it had just been told *is* PASS, fixing the test itself and closing
the run. The trade is bad either way, so it was rolled back: a stuck run costs one verifier
round and heals on the next `/antz`, while a bypassed loop reports no blame, routes nothing,
and never runs the tester's red-before-green.

What changed instead is who closes the run: the verifier writes the decision and stops, and the
orchestrator deletes `.antz/` on PASS once that document exists. A and B still end with the
document written and `.antz/` gone; C, where there is no PASS, checks the other half — that the
new owner does not delete it on the way out.

Misrouting never happened: 20 of 20 runs sent a test fault to the tester and an implementation
fault to the implementer, each with the verifier's report as the task and never to both. That
is the part the loop exists for.

The shape of the rounds varies between runs — `verifier, implementer ×3, verifier`, an
alternation, and `verifier, implementer ×3` with no closing verification, when the last attempt
was the last allowed. The assertions do not pin it: the cap is on attempts, and re-verifying
between them is the orchestrator's call.

Two behaviours, both observed, neither in any prompt:

- **The orchestrator does not trust a child's report.** An implementer claimed a green suite
  while the file was unchanged; the orchestrator re-read it, caught the lie, and said so in the
  next attempt's task.
- **`antz-scout` can appear mid-loop**, as a fresh in-process probe while the orchestrator was
  diagnosing why writes appeared not to persist. It is not part of the documented loop and it
  did not consume an attempt.

`C` is the arm that reaches the cap, but whether it is reached is a rate: the watcher cannot be
repaired away, so an agent that judges the environment unfixable and stops — what *never grind*
asks for — closes the round first. Four runs took 1, 2, 3 and 3 attempts.

Both arms were also watched on a real run (2026-09-21, a small Node checkout project entered at
step 5 with one fault seeded): an implementation that ignored a discount cap gave
`verifier → implementer → verifier`, and a test that contradicted the spec gave
`verifier → tester → verifier`. Each named the failing task and the side at fault, sent it only
there, and closed in PASS with the decision written and `.antz/` deleted.

## The prompt changes (2026-09-30)

One commit each, installed one state at a time with `measure.sh` and read back with `agents.sh`.
One run per state, so these are counts, not rates. The verifier's five jobs are what the
assertions hold it to: independence, integration, the test judged against the spec, the shape,
and the decision document.

| Change | Why it exists | What it measured |
|---|---|---|
| the verdict on disk | a dead round took its verdict with it, and finishing by hand cost a real run 2 h and 36.7 M tokens | `C` asserts the file: 35 lines naming the failing task. A verifier call that died on a proxy timeout had its verdict read back from disk and its repairs routed |
| a bounded verifier round | a real round spent 102 turns and 31 min, most of it working out how to run two suites | verifier turns per round in `A`/`B`/`D`, 11.8 / 13.5 / 15.0 → 13.5 / 11.0 / 14.5: no reduction the fixture can show |
| the recon names the commands | the phase whose job is to read the repo did not write down how to run it | `N` against its control `H`: 22 turns per round against 25, the discovery cost being two `package.json`. Both retired since |
| never grind, and a stopped task cut or reframed rather than resent | one implementer spent 147 steps and 70 min on one task, 31 % of a run | nothing: no run reached it, and `C` still spends its three attempts. A stopped task is reachable since, via `S` |
| a task is one capability and one seam | that plan's T8 held three capabilities and 18 tests | not reachable: the eval seeds a plan, it never plans |
| the task handed over whole | that run's testers opened `.antz/` 34 times, a 21 KB recon read each time | reads under `.antz/` in `agents.tsv`: 1.14 and 1.33 per run, 16 in 13 agent runs, → none in 10 |
| one row per agent | a `chains` call of eight agents was a single usage row, and the role is what a cost question is about | `dispatch.sh`, and the reconcile line in the summary |
| the panel names the file | `…/.antz/01-spec.md` and `…/src/pagination.js` rendered alike, so an audit misread which file an agent had read | `dispatch.sh`, one assertion |

Two changes are demonstrated: the scratch directory out of the testers' and implementers'
hands, where the count going to zero is a change of kind rather than of mean, and the verdict on
disk, which is precisely what a dead round leaves behind. Four are **not reachable here** — the
fixture has no discovery cost to remove, nothing in it can provoke a task big enough to grind,
and it never plans. Those rest on the real run that motivated them, and the eval cannot confirm
them, which is worth knowing before it is asked to.

A change after that batch was checked with `TAG=cortes RUNS=1 ./run.sh A B D C`: A, B and C
PASS with the blame routed as ever. `D` came back with one repair round more than the assertion
allowed, although the verifier had rejected the shape and the run did close with a
verification; two more runs gave the canonical shape, so the deviation was the round shape
varying. The assertion was the thing that was wrong and now tolerates repeats on the blamed
side. That row is the only verdict in `results.tsv` judging a run by a rule the design never
held, and its end state was never recorded, so it stays as written rather than re-judged.

### `S`, and the two faults it exposed

Three runs, the first measurement of the stopped-task rule from the other side of `C`. Under the
contract it was written with, all three FAILed, and not one failure was the rule's: two were a
resend count of 11 and 16 that was never a payload count — `payloads()` compared the trace a
line at a time while a task carries newlines, so the `{previous}` and the criteria block every
task shares read as a resend — and the third was a run that read the contradiction and amended
spec and plan *before* dispatching, so no agent stopped on it. The other two stopped, the
orchestrator cut the `RangeError` criterion, re-dispatched a reframed chain and closed in PASS.
No run resent a payload, none spent more than 4 repairs, none came near the `TIMEOUT`, and no
implementer ground. The rule's letter is 3/3 — the reason `S` could not say so was two faults
in `S` itself, both fixed after it. The same three traces re-judge as 3/3.

### `cut`, built and dropped

It asked whether the cap holds when a task is cut rather than resent, and no seed could provoke
it: in two of three runs the orchestrator read the seeded test, saw the contradictions and
stopped to ask instead of dispatching, and in the third the tester pared the test down and the
run converged. The model resolves the contradiction — by refusing it or by normalising the spec
— before the cap is in play, and a scenario that cannot provoke what it promises is worse than
none. Its first batch was also judged by a counter bug (a task names its test file twice, so two
attempts read as four), and the second batch overwrote the first's traces, so only the second is
checkable. `cut` has no contract, which is why `rejudge.sh` skips it.

The two `C` rows that read FAIL under the old "exactly three attempts" reading judge a run by a
rule the design never held: a stopped agent closing the round early is what *never grind* asks
for. The harness now accepts ≤ 3 attempts and fails only a run that passes the cap, converges,
or never repairs anything.

One reporting bug was fixed on the way: `gone` was 1 while `.antz/` was still there, and the `S`
branch's closing sentence read it as its opposite, so a run that left `.antz/` with no decision
printed "closed in PASS anyway". The verdict never depended on it — `S` asserts the trace and
only reports the ending.

## The skills move (2026-10-22)

The TDD and architecture rules left antz for `edezacas/agent-skills`. antz ships one skill now,
`antz-clarify`, and the agents keep asking for "whatever skills cover test-driven development and
architecture". `prompts/`, `agents/` and `extensions/` are untouched, so this batch measures the
two skills from outside. `D` and `M` are the arms that can see it. `TAG=skills-move ./run.sh D M`,
then `RUNS=3 ./run.sh D`.

| Run | Verdict | What it showed |
|---|---|---|
| `M` | PASS | four chains in two dispatches, decision written, `.antz/` deleted, 1396 s and 537 k tokens. Every tester and every implementer read `tdd` and `code-design`; both verifiers read `code-design` |
| `D` 1 | FAIL | the verifier read `code-design`, named the surplus, and passed it anyway |
| `D` 2-4 | PASS | the canonical shape, a repair round or two, 665 s, 834 s and 420 s |

`M` is the clean half. The merged `tdd` reaches the tester and the implementer, they read it, and
the four chains converge, so the fusion did not break the handover. Whether the headless seam
rule was exercised, `M` cannot say, because its plan names every test path already.

`D` 1 is worth keeping. The verifier did not skip the skill. `agents.tsv` records `code-design`
for that run, and its report names the fault exactly, "`LimitPolicy` single-impl seam, stateless
`ArrayPaginator`/`makePaginator` in `src/pagination.js`", then files it as "taste in untouched
baseline code, no plan criterion broken, so not a failing task".

That is the scenario contradicting itself. `D` seeds the over-abstraction in the baseline, and
`agents/antz-verifier.md` says "judge the change, not the tree". A verifier that takes that line
literally has to let it pass. Seven `D` runs before the move passed, and three of the four after
it did, so the rate is 10 of 11 and not a regression from the rename, which changed no body text.
The two clauses simply disagree, and one run in eleven noticed.

If `D` is to keep measuring the architecture check, one of the two has to move. Either the seed
puts the surplus inside the change, or the verifier's rule widens from the change to the tree.
Neither is a fix to make from one batch, and until one of them happens, `D` measures the loop and
only sometimes the shape.

### The skills' own evals

The batch above reads the flow. The skills were also measured on their own, with the runner in
`agent-skills`. They are 6 of that iteration's 20 cases, 12 of its 40 runs, each one graded by a
separate judge. `tdd` 9/9 against 6/9, `code-design` 10/10 against 9/10, 19/19 against 15/19
together, and the assertions that can fail because of the skill rather than by luck 14/14 against
10/14. Two cases carry the difference, the tester's batch of tests written ahead of any
implementation and the smallest change for one new option. The other four cases pass in both
arms, so this batch gives them no signal.

## Retired scenarios

A scenario is retired when it can no longer buy a measurement. It is kept under
`scenarios/retired/`, its seeds and traces stay, and `judge.mjs` holds no contract for it, so
`rejudge.sh` skips it rather than guessing a verdict.

- **N and H** (2026-10), the two-package discovery pair, now `scenarios/retired/mono/`. N's
  unique claim was the cost the one-module fixture cannot charge for — how to run a suite, and a
  tester that opens `.antz/` — and it came back null against H, its own control: 22 turns per
  round against 25. Its other assertion, four chains dispatched in parallel, is `M`'s, and `M`
  covers it in a fifth of the wall clock. N was also the only scenario that could outlast
  `TIMEOUT`, and one of its three runs was cut off there. N cost 1512 s and 734 k tokens a run
  and H 483 s and 535 k, against 296 s and 315 k for `M`: the pair is three times the tokens of
  A, B and D together. Giving them back their `run.sh` branch, their seed and their contract
  runs them as before.
- **`cut`** (2026-10), built, measured and dropped. Its six rows in `out/` are the record of a
  counter bug, not of the loop; they live in `out/results-dropped.tsv` so the summary no longer
  reports them.

The rule this leaves: a scenario exists while it owns a contract no other arm asserts. When that
stops being true — measured null, folded into a cheaper scenario, or outlasted by its own
`TIMEOUT` — retire it here instead of leaving it in the batch.
