# antz

Spec-driven development workflow (specifier / coder / verifier) as portable agent definitions, plus an `orchestrator` role that sequences the three for one change and is the recommended entry point via `/antz`.

## Why

AI coding agents are good at writing code and bad at remembering what the system is *supposed* to do. Without a persistent spec, intent gets re-derived from scratch every session, ambiguity surfaces after the code is written instead of before, and a small feature can quietly change behavior nobody meant to touch.

antz addresses that with:
- **Clarity before code** — `specifier` turns a request into concrete Gherkin scenarios before any code is written. A genuine ambiguity blocks implementation (`OPEN_QUESTIONS.md`) instead of getting guessed away.
- **Specs that persist** — `verifier` merges each shipped scenario into `spdd/specs/<domain>.md`, so the next session reads what the system actually does instead of re-deriving it from code or chat history.
- **Work split by dependency** — `specifier` breaks a feature into sub-specs that are each independently implementable and verifiable, ordered so dependencies come first.
- **Marked by branch, never touched by git** — every `/antz` flow gets its own marker branch (`antz/<slug>`, pointing at the commit the flow started from), but nothing is ever committed or removed for you: the work stays uncommitted in your working tree, where you keep full control. At the end you review, commit, and delete the marker branch yourself.
- **Guarded automation** — the `orchestrator` runs specifier -> coder -> verifier end to end, classifying each sub-spec from disk receipts (no test-suite re-runs between steps; only the verifier runs the full verification), but stops and reports whenever something needs a human call: an ambiguous change, an open question, a stuck sub-spec, or a rejection that doesn't trace back to a single sub-spec.

## What you get

Using antz turns "chat with an agent until something works" into a repeatable pipeline with spec artifacts you keep:

```
                    your request (/antz <request>)
                              |
                              v
                       .-----------.
                       | orchestr. |  sequences, classifies from disk,
                       '-----------'  stops for human calls
                    /          |         \
                   v           v          v
             .---------.  .---------.  .---------.
             | specifier|->|  coder  |->| verifier|
             '---------'  '---------'  '---------'
             Gherkin      code +       validates, merges into
             sub-specs    unit tests   spdd/specs/, archives
             (+QA suite)  + receipts   the change
                   \          |          /
                    v         v         v
                  all work uncommitted on branch antz/<slug>
                              |
                              v
                     you: review, commit,
                     merge, delete the branch
```

- **A spec you can trust exists before code does** — Gherkin scenarios with per-scenario ids, written against the real codebase, so every test name traces back to an intended behavior and every merge updates the persistent spec, not just the code.
- **One sub-spec at a time, in dependency order** — implementation sessions stay small and focused; each is verified on disk before the next one starts.
- **Orchestration that never re-verifies blindly** — each implemented sub-spec leaves a result receipt; the orchestrator classifies progress by reading files, so steps chain quickly without re-running your whole test suite, and only a doubtful receipt triggers a re-run.
- **Honest failure handling** — genuine ambiguity stops work (`OPEN_QUESTIONS.md`), a stuck sub-spec stops it too (`BLOCKED:`), verification failures get one bounded retry, and a second rejection stops the flow for good instead of looping on a broken change.
- **Fresh context every session, state always on disk** — no role depends on another's chat output; interrupting or resuming a flow days later works because the state machine re-derives everything from the working tree.
- **You stay in control of git** — the flow never commits, never forces anything, and never deletes anything: you review the diff, commit selectively, decide where to merge, and clean up.
- **Skills awareness carried into every delegation** — each delegated session receives the matching skills' paths derived fresh from your own skills directories at delegation time.

## Agent Compatibility

Currently compatible with:
- Claude Code
- OpenCode

## Requirements

- **`git`** — required to run `/antz`. Every flow is marked by its own branch `antz/<slug>`, so the orchestrator needs `git` on `PATH` and to be run inside a git repository with at least one commit. It fails closed (never falls back to an unbranched mode) if either is missing — install `git` and/or run `git init` plus an initial commit yourself first.
- **POSIX `sh`** — `install.sh` and the scripts the orchestrator runs (git flow, status probe, skills derivation — source files under `scripts/orchestration/`, injected into the rendered orchestrator) are plain `sh`, no bash-only syntax; any POSIX-compliant shell works.
- **`curl`** — only needed to install without a local checkout (`curl | sh`, and `install.sh --check` run the same way); a local checkout installs from disk instead.
- Claude Code and/or OpenCode installed, for `install.sh` to detect and target.

# Install

Renders the agent definitions under `agents/prompts/` + `agents/meta/` into native subagent files for whichever of Claude Code / OpenCode are detected, and installs them into that client's global agents directory (`~/.claude/agents/`, `~/.config/opencode/agents/`).

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh
```

To install from a tag (ref-pinned provenance), fetch `install.sh` from the tag's raw URL and pass `ANTZ_REF=<tag>` to `sh`, so every file the installer reads (`VERSION`, `CHANGELOG.md`, `agents/`, `scripts/`) is fetched from that same tag instead of `master`:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/v4.7.0/install.sh | ANTZ_REF=v4.7.0 sh
```

`ANTZ_REF` is used verbatim — a branch name works the same as a tag, and nothing validates it. Unset or empty, the default ref (`master`) applies. Local-checkout installs below read everything from disk and ignore `ANTZ_REF` entirely.

Or, from a local checkout:

```sh
./install.sh            # auto-detect installed clients
./install.sh --claude    # force Claude Code only
./install.sh --opencode  # force OpenCode only
./install.sh --all       # force both
```

Re-running is safe: files this script generated are marked and get overwritten in place; a pre-existing, unrelated agent file with the same name is backed up (`<file>.bak.<timestamp>`) instead of being silently overwritten.

## Usage

Run `/antz <your request>` in Claude Code or OpenCode after installing. It delegates to `antz-orchestrator`, which sequences `specifier -> coder -> verifier` for one change, picking up correctly even if interrupted and resumed later. Every change gets its own marker branch `antz/<slug>`, while all work stays uncommitted in your checkout; the underlying roles are also directly invokable for manual/expert use outside any flow.

`/antz-set-model` configures or clears the `model:` frontmatter line of one installed antz agent file, per agent and per client (`--agent` is one of `specifier|coder|verifier|orchestrator`). It edits the file directly in the invoking session and never delegates to any `antz-*` subagent:

```sh
/antz-set-model --agent coder --model anthropic/claude-opus-4-5  # set the model explicitly (value written verbatim)
/antz-set-model --agent coder                                    # omit --model/--clear: interactive model picker
/antz-set-model --agent coder --clear                            # remove the model: line (client's default model)
```

Omitting `--model`/`--clear` opens the interactive picker: on OpenCode it enumerates models at invocation time via `opencode models`; on Claude Code it offers the documented alias vocabulary (`sonnet`, `opus`, `haiku`, ...). Both pickers always offer a free-form entry and a revert-to-default option, and argument/install-state validation happens before any question is asked.

## Updating

```sh
./install.sh --check   # report whether an update is available, and what changed
./install.sh           # install it (re-run with the same flags you used before)
```

Each install embeds its `VERSION`; re-running reports the version jump and the relevant `CHANGELOG.md` entries.

Without a local checkout, run the same check remotely:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh -s -- --check
```

Or just fetch the current published version number:

```sh
curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/VERSION
```

## Benchmark & telemetry

`bench/` measures the antz flow itself, so you can see how it is doing and compare runs, clients, and versions. It runs the full `specifier -> coder -> verifier` flow against a small checked-in fixture and records one telemetry row per repetition: wall-clock time, tokens (input / output / reasoning / cache), cost, turns, tool calls, subagent delegations, and the flow's outcome (`approved`, `rejected`, `blocked`, `open-question`, `timeout`, `error`). It then aggregates the rows into a report.

It is **client-agnostic**: `bench/` launches Claude Code, OpenCode, or the offline dry-run client as a subprocess behind one adapter contract, normalizes each client's telemetry into a single schema (`null`, never a silent zero, where a client cannot report a field), and pins the model so a comparison isn't confounded. Each repetition gets a fresh git repo materialized from the fixture and a fresh sandbox: the measured flow is rendered from the checkout under test, and your real config is never touched. Nothing is ever committed.

Run it from the repository root:

```sh
# offline smoke run: no client, no network, no cost
sh bench/antz-bench.sh --client dryrun --repetitions 3

# a real measurement: auto-detect installed clients and run each once
sh bench/antz-bench.sh

# force a client, repeat it, and pin the model
sh bench/antz-bench.sh --client opencode --repetitions 5 --model <provider/model>

# aggregate a results file, optionally against a baseline
sh bench/antz-bench.sh report --jsonl bench/results/bench-<stamp>.jsonl --baseline baseline.jsonl
```

Each run appends JSONL records to `bench/results/bench-<UTC>.jsonl` (git-ignored) and prints a report. Outcomes are data, not failures: exit 0 means every repetition produced a record. `--timeout <seconds>` bounds each repetition (default 1800). Full flag list with `sh bench/antz-bench.sh --help`.

Example (dry-run, 3 repetitions):

```
antz-bench report: total records: 3
client dryrun: records=3 models=null
  outcomes: approved=3
  wall_clock_ms: n=3 mean=33.666667 median=33 min=32 max=36 p95=36
  client_duration_ms: n=3 mean=800 median=800 min=400 max=1200 p95=1200
  tokens_input: n=3 mean=200 median=200 min=100 max=300 p95=300
  tokens_output: n=3 mean=100 median=100 min=50 max=150 p95=150
  tokens_reasoning: n=0 mean=null median=null min=null max=null p95=null
  tokens_cache_read: n=3 mean=20 median=20 min=10 max=30 p95=30
  tokens_cache_write: n=0 mean=null median=null min=null max=null p95=null
  cost_usd: n=3 mean=0.025 median=0.025 min=0.0125 max=0.0375 p95=0.0375
  turns: n=3 mean=6 median=6 min=3 max=9 p95=9
  tool_calls: n=3 mean=12 median=12 min=6 max=18 p95=18
  subagent_delegations: n=3 mean=4 median=4 min=2 max=6 p95=6
```

Real-client numbers are the point: run `--client claude` / `--client opencode` with a pinned model, repeat enough for a distribution, and keep the JSONL as a baseline. The dry-run client scripts its outcome deterministically, so it is also the way to exercise the harness without spending anything (the hermetic `tests/bench-harness_test.sh` uses it; the real bench never runs inside `tests/run_all.sh`).

### Saving baselines

`bench/results/` is generated output and git-ignored; the baselines you want to keep live in `bench/baselines/`, which is committed. Create each baseline **once** by pointing `--jsonl` at that directory — the raw audit dirs still land under `bench/results/runs/`, so the baseline file itself stays clean:

```sh
# baseline for Claude Code, pinned model, 5 repetitions
sh bench/antz-bench.sh --client claude --repetitions 5 \
  --model sonnet --jsonl bench/baselines/claude-sonnet.jsonl

# baseline for OpenCode, pinned model, 5 repetitions
sh bench/antz-bench.sh --client opencode --repetitions 5 \
  --model nan/deepseek-v4-flash --jsonl bench/baselines/deepseek-v4.jsonl
```

`--model` is forwarded to the client verbatim: Claude Code takes an alias or a full model name (`sonnet`, `opus`, `claude-...`); OpenCode takes `provider/model` (e.g. `nan/deepseek-v4-flash`).

Then, for **every later measurement**, let the runner write its own fresh timestamped file (the `--jsonl` default) and compare it against the frozen baseline with `--baseline`:

```sh
sh bench/antz-bench.sh --client opencode --repetitions 5 --model nan/deepseek-v4-flash \
  --baseline bench/baselines/deepseek-v4.jsonl
```

Records are **appended, never overwritten**: `--jsonl` adds to whatever the file already holds, while the default path is a new timestamped file each run. So keep a baseline as one clean run and don't measure into it again — a re-run against the same `--jsonl` would pool every execution into one file and blur the comparison. For a new baseline, use a new name (or `rm` the old file first).

## License

Code in this repository is licensed under [Apache-2.0](LICENSE)
