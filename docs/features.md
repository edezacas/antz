# features — what to change next, ordered by what it returns

Not a wish list: every item below comes from an audit of a real run, and each one says what it
costs, what it preserves and how it is checked. The design of record stays [`README.md`](../README.md);
this file is only the queue.

## Where it comes from

Two bodies of evidence, both on disk and both re-checkable:

- **The eval sessions** (`eval/out/*.session.jsonl`). Each dispatch persists its runs, and every
  run carries `usage`, `steps` and the path of every `read` it made. That is the instrument —
  it is read by hand today, which is itself item 7.
- **A real run**, bluplat on 2026-09-29: 12 tasks, 5 h 30 in one session, then 2 h in a second
  one after the run failed to close. Its numbers are the ones that moved the priorities:

| Agent | Dispatches | Tokens | Turns | Share |
|---|---|---|---|---|
| antz-implementer | 19 | 16.1 M | 449 | 42 % |
| antz-tester | 17 | 8.8 M | 362 | 23 % |
| antz-scout | 1 | 7.3 M | 150 | 19 % |
| antz-verifier | 1 | 5.7 M | 102 | 15 % |
| antz-planner | 1 | 0.35 M | 47 | 1 % |
| the orchestrator | — | 4.7 M | 59 | — |

Fixture and reality disagree, and the disagreement is the point: in `eval/out/M-1` the verifier is
20 turns and 34 % of the tokens, here it is 102 turns and 15 %. Neither number is transferable on
its own; the combination is what reorders the queue.

## What "value" means

The verifier's five jobs, which every item below is judged against:

1. **Independence** — it wrote neither the test nor the code, and it runs on another model family.
2. **Integration** — the whole suite and the build, the one thing the per-task chain never runs.
3. **The test judged against the spec**, not against itself, and blame attributed to one side.
4. **Shape**, which the green suite cannot see (the `D` scenario).
5. **The decision document**, the only artifact meant to survive.

## P0 — the run has to close, and the verdict has to survive

- [x] **1. The verdict on disk.** Today it lives only in the orchestrator's context, so a round that
  dies takes its work with it. Writing it to `.antz/03-verdict.md` lets `/antz` resume at step 5.
  *Cost of not doing it, measured:* the second session re-did the verification and the repair by
  hand — 213 turns, 36.7 M tokens, no tester, no verifier, `.antz/` still on disk today.
  *Touches:* `prompts/antz.md` step 5, `agents/antz-verifier.md`, and the gotcha in `AGENTS.md`
  that rejects an on-disk verdict on purpose. That decision now has a price attached.

- [x] **2. Bound the verifier's round.** Four rules, all judgement, no format:
  judge the change (`git diff`) rather than the tree, cross-checking what the plan said each task
  would touch (`Touches`) against what the diff shows; do not discover how to run the suite;
  run the suite first and let it narrow the scope; and on a repair round judge the repaired task
  plus the suite, not the whole plan.
  *Returns:* 102 turns → ~30. Not a saving: a round that large is what the provider cut short
  (`content_filter`, then an abort 30 min later).
  *Constraint:* `agents/antz-verifier.md` is 13 lines, the ceiling in `AGENTS.md`. This has to
  condense what is there, not add to it.

- [x] **3. The suite and build commands belong to the recon.** `antz-scout` records how to run one
  spec, the whole suite and the build for each subproject, exact command included.
  *Returns:* the verifier stops spending turns being a build engineer — it spent most of its 80
  `bash` calls discovering `venv`, `phpunit` and `karma`.

## P1 — no agent running away

- [x] **4. A turn budget that reports rather than kills.** Past a threshold the agent stops and
  names its blocker, and the orchestrator decides: split the task, change the approach, ask the
  user. Not a hard cap — in the real case the task *converged*, and cutting it would have been
  wrong. The agents already do this unprompted ("the test is not red, I'm stopping here"); the
  budget just makes it reliable.
  *Applies to:* an implementer at 147 turns / 70 min / 11.8 M (31 % of the run, on one task) and
  a verifier at 102.
  *Touches:* `agents/antz-implementer.md`, `agents/antz-tester.md`, `agents/antz-verifier.md`.

- [x] **5. Tasks that are actually small.** T8 held 18 tests and three separate capabilities
  (edit mode, drag gating, dimension persistence) and shares `layout.component.ts` with T7. Split,
  it is three parallel chains of ~25 turns instead of one of 147.
  *Returns:* it attacks the 42 % of the run that the implementers cost, which is more than the
  verifier's 15 %.
  *Touches:* `agents/antz-planner.md` — the rule already says "small tasks"; the planner applied
  it to the other eleven.

## P2 — context that buys nothing, and being able to see it

- [x] **6. The task handed to an agent has to be self-sufficient.** Acceptance criteria, seam, owned
  test file and `Touches` copied out of the plan verbatim, and no reopening `.antz/` unless
  something is missing.
  *Returns:* on the real run the testers read `.antz/` 34 times (recon 11, spec 10, plan 13) and the
  implementers 4; in the fixture, zero. The recon alone is 21 KB, ~5 k tokens, and it stays in a
  context that costs ~24 k per turn until the session ends.
  *Touches:* `prompts/antz.md` step 4, one line each in `agents/antz-tester.md` and
  `agents/antz-implementer.md`.

- [x] **7. Per-agent numbers as an instrument.** A row per agent in `out/agents.tsv`: tag, scenario,
  agent, turns, input, cacheRead, output, seconds. The data already exists in
  `details.runs[].usage`; today it takes a hand-written `jq`. About ten lines in `eval/run.sh` and
  a paragraph in `eval/README.md`.
  *Returns:* every other item here becomes a number instead of an impression.

- [x] **8. The panel must not hide the file name.** `toolArg` truncates to 64 characters from the
  end, so `…/.antz/01-spe…` and `…/src/paginati…` render identically — which is how a real
  observation got misread as "every agent re-reads the plan". The `path` case should keep the tail.
  *Touches:* `extensions/antz-subagent.ts`.

## P3 — measure before touching

- [ ] **9. Merging antz-tester into antz-implementer.** Recommended against: the split is what makes
  the test's independence a fact rather than a discipline, and it is what the verifier's blame
  routing and the eval's A/B pair are built on. If it is still tried, it needs a fixture with real
  exploration cost (the 8-line one is biased towards merging) and a scenario that catches a test
  bent to fit the code.

- [ ] **10. A cheaper verifier model.** Recommended against. On the real run its problem was size,
  not price, and a cheaper model that needs more turns costs more. The separate model family stays —
  it is verified in practice (`nan/mimo-v2.6-flash` against `nan/glm5.3-flash`).

## Already right — leave it alone

- The verifier's pin to another model family: honoured for real.
- Parallelism: four testers starting within the same second, one chain per task, no cross-talk.
- The shared prompt prefix: instructions ride in the first user message so the cached prefix is
  reused, as `extensions/antz-subagent.ts` documents.
- `eval/`: A/B/C/D remain the net that catches a regression in any of the above.

## How each item is checked

Items 1–6 are prompt text, so they are provoked, not asserted: `./eval/run.sh A B C D` for the
repair loop, the blame routing and the shape judgement (`D`), with item 7 in place to say whether
anything got cheaper. Item 8 and the tool itself: `./eval/dispatch.sh`. Every batch needs the same
`RUNS` before and after, and one green run proves nothing — this is a rate, not a boolean.

**Order of work:** 7 → 1 and 2 → 4 and 5 → 6 and 8 → 9 and 10 only with data.

## Status

Items 1–8 are implemented, one commit each, on the branch `feat/features-01-08`; the
per-item changes to `eval/run.sh` (the two-package scenario, and the verdict assertion in
`C`) land with the measurement they belong to. Each commit is a state that can be checked
out and installed on its own, which is how the numbers below are taken:

| Batch | State | What it answers |
|---|---|---|
| `TAG=before RUNS=5 ./run.sh A B C D M` | `master` | the baseline every later number is compared against |
| `TAG=item1 RUNS=5 ./run.sh M` … one per commit | the branch, cumulatively | which change moved turns, tokens and `.antz/` reads, per agent in `agents.tsv` |
| `TAG=before RUNS=5 ./run.sh N H` | `master` | what a recon that names the commands is worth (item 3), and how often testers open `.antz/` (item 6) |
| `TAG=after RUNS=5 ./run.sh A B C D M` | the tip | the quality net: blame routing, `D`, the cap in `C`, and the end state |

The per-item batch is `M` because it is the cheapest scenario that reaches every role with
the same workload every run; `A B C D` is the net and is run at the start and at the end,
not between every item. One run proves nothing — these are rates.

### What the ladder showed (2026-09-30)

One run per state, so counts rather than rates. `before` on `master`, then the branch
cumulatively, installed with `measure.sh` and read back with `agents.sh`:

| Item | Metric | Before | After |
|---|---|---|---|
| 1 | `.antz/03-verdict.md` after `C`, plus one live recovery | no file | 35 lines naming the failing task, and a verifier call that died on a proxy timeout had its verdict read from disk and its repairs routed |
| 2 | verifier turns per round, `A`/`B`/`D` | 11.8 / 13.5 / 15.0 | 13.5 / 11.0 / 14.5 — no reduction the fixture can show |
| 3 | verifier turns, `N` against its control `H` | `N`: 22 per round, 1765 s | `H`: 25 turns, 483 s — the fixture's discovery cost is two `package.json` |
| 4 | whether it fires | — | no run reached it; `C` still spent its three attempts |
| 5 | — | not reachable: the eval seeds a plan, it never plans | — |
| 6 | reads under `.antz/`, `N` | testers 1.14, implementers 1.33 per run — 16 in 13 agent runs | none, in 10 runs |
| net | `A`, `B`, `D`, `C` at the tip | — | all PASS, blame routed to the right side, `D` rejecting the shape, `C` stopping at three attempts |

The prompt text was rewritten afterwards for concision: no dashes as punctuation, one idea per
sentence, same rules and the same line budget (9-13 per agent, 32 for `prompts/antz.md`). The
numbers above predate that rewording, and `TAG=reword RUNS=1 ./run.sh A B D C` is the guard
that the net still holds with the new wording.

**Demonstrated:** item 6, and item 1 where it matters most. **Not demonstrated, and not
demonstrable here:** items 2 and 3, because the fixture has no discovery cost to remove,
and items 4 and 5, because nothing in it provokes a task big enough to grind or plans at
all. Those four keep the real-run evidence they were written from; the eval cannot confirm
them, and now says so instead of implying otherwise.
