# Change: telemetry-benchmark

A repeatable, client-agnostic measurement harness for antz: it runs the full
specifier -> coder -> verifier flow against a small checked-in fixture,
normalizes each client's telemetry into one common schema, and aggregates the
runs into a report that answers "how does antz fare across runs, clients, and
versions" (wall clock, tokens, cost, turns, tool calls, delegations, outcome).

## Goal

`bench/` gains a POSIX-sh harness, repo-local and never installed globally:
one runner CLI, three client adapters (Claude Code, OpenCode, dry-run mock),
and a self-contained fixture. The real (LLM-invoking) bench is never part of
`tests/run_all.sh`; the owning test suite exercises the plumbing hermetically
through the dry-run client and the standalone report mode.

## Contract (one paragraph)

The user runs `sh bench/antz-bench.sh [--client <name>] [--repetitions <n>]
[--model <value>] [--timeout <s>] [--baseline <file>] [--jsonl <file>]
[--dryrun-outcome <outcome>]`. With no `--client`, every client detected by
install.sh's predicate runs; `--client` forces one. Each repetition
materializes a fresh git repo from the checked-in fixture, prepares a fresh
sandbox (agents rendered from the checkout under test, credentials copied
read-only, minimal env), launches the client headless as the antz-orchestrator,
collects telemetry, classifies the outcome from disk artifacts, and appends
one JSONL record. The run ends with an aggregate report (per client: count,
mean, median, min, max, p95 per metric, outcome distribution), optionally
compared against a baseline JSONL. `sh bench/antz-bench.sh report --jsonl
<f> [--baseline <b>]` computes that report standalone. Exit 0 = every
repetition produced a record; outcomes are data, not failures.

## Verified facts this spec is built on (investigated 2026-09-15)

- **Claude Code** (v2.1.272): `claude -p "<req>" --agent <agent>
  --output-format json` exits 0 and prints one JSON object with `usage`
  (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`,
  `cache_read_input_tokens`), `total_cost_usd`, `duration_ms`, `num_turns`,
  `session_id`, `modelUsage` (per-model aggregates), `subagent_stats`.
  Session transcript: JSONL under `<config>/projects/<munged-cwd>/<uuid>.jsonl`,
  entries carry `isSidechain`, per-message `usage`, `tool_use` blocks.
  `CLAUDE_CONFIG_DIR` relocates the whole config root; copying
  `.credentials.json` restores auth (verified live).
- **OpenCode** (v1.18.31): `opencode run --agent <agent> --format json "<req>"`
  emits per-event JSON lines each carrying `sessionID` (step-finish parts
  carry tokens); `opencode export <sid>` returns `{info, messages}` with
  `info.tokens`, `info.cost`, `info.model`, `info.time{created,updated}`;
  task tool parts carry `state.metadata.sessionId` naming the child
  (subagent) session — **parent totals exclude child sessions**, so the
  adapter exports children and sums (verified on real session data).
  `XDG_CONFIG_HOME` + `XDG_DATA_HOME` relocate config and data; copying
  `auth.json` restores auth (verified live).
- **Headless entry point**: both clients take the orchestrator agent directly
  (`--agent antz-orchestrator` / `--agent antz-orchestrator`), which is
  deterministic and non-interactive with a permission auto-approval flag.
  The `/antz` command path (Claude's extra primary-agent hop) is out of scope.
- **Isolation**: install.sh bakes the resolved libdir into the rendered
  orchestrator body (`__ANTZ_SCRIPTS_DIR__`), so rendering the checkout under
  test into the sandbox measures the checkout's flow, not the global install.
- **Known open point (implementation-time)**: whether Claude's result-level
  aggregates already include subagent usage is not settled here; the contract
  (clients-05) resolves it mechanically — the isolated transcript is the
  authoritative source for sidechain inclusion, and the coder verifies
  inclusion at delivery time against the canned-fixtures + one live run.

## Shared contracts (defined once, consumed identically)

- **Common telemetry schema** (`02-schema`, field set + null discipline +
  outcome precedence) — consumed by the adapters, the runner, and the report.
- **Adapter contract** (`03-adapter`: `bench_detect` / `bench_invoke` /
  `bench_collect`, run-dir artifact names, collect key set) — implemented by
  each of `bench/adapter-{dryrun,claude,opencode}.sh`.
- **Sandbox contract** (`04-clients`: per-repetition sandbox dirs, minimal
  allowlist env, credential copy, checkout-rendered install).
- **Fixture materialization** (`01-fixture`: fresh git repo per repetition,
  byte-stable request).
- **Report statistics** (`06-report`: nearest-rank p95, standard median,
  nulls excluded, explicit-only baseline).

## Entities

| Name | Path | New-or-Existing | Notes |
|---|---|---|---|
| Bench runner | `bench/antz-bench.sh` | new | POSIX sh; run mode + `report` mode; the only entry point |
| Bench shared library | `bench/lib.sh` | new | sandbox, fixture materialization, record emission, outcome classification |
| Dry-run adapter | `bench/adapter-dryrun.sh` | new | hermetic mock client; scripted outcomes; no network, no credentials |
| Claude adapter | `bench/adapter-claude.sh` | new | headless Claude Code telemetry via result JSON + isolated transcript |
| OpenCode adapter | `bench/adapter-opencode.sh` | new | headless OpenCode telemetry via run events + parent/child exports |
| Fixture scenario | `bench/fixture/scenario.txt` | new | the exact request text passed as the client prompt |
| Fixture repo | `bench/fixture/repo/` | new | small toy project (README + sources); no `.git` inside `bench/fixture/` |
| Results area | `bench/results/` | new | default JSONL output + per-repetition run dirs (created on demand) |
| Owning suite | `tests/bench-harness_test.sh` | new | hermetic: dry-run client, recording stubs, canned artifacts, report mode only |

## Operations

| Type | Identifier | Description |
|---|---|---|
| mode | (default) run | N sequential repetitions per selected client; JSONL + report |
| mode | report | aggregate report (+ optional baseline) from a JSONL; launches nothing |
| flag | `--client <name>` | force one client (`claude`, `opencode`, `dryrun`); skips auto-detection |
| flag | `--repetitions <n>` | repetitions per client (default 1) |
| flag | `--model <value>` | pinned model: forwarded to the client, recorded in every record |
| flag | `--timeout <seconds>` | per-repetition deadline; firing yields outcome `timeout` (default 1800) |
| flag | `--baseline <file>` | baseline JSONL for the report's comparison section |
| flag | `--jsonl <file>` | results path (default `bench/results/bench-<UTC timestamp>.jsonl`) |
| flag | `--dryrun-outcome <outcome>` | scripts the dry-run client's outcome (dryrun only) |
| adapter fns | `bench_detect` / `bench_invoke` / `bench_collect` | the per-client adapter contract |

## Invariants (change-wide)

- `bench/` is repo-local: **install.sh is byte-for-byte unchanged by this
  change and nothing under `bench/` is ever installed globally**; the harness
  renders the checkout under test into its own sandbox when it needs antz.
- No VERSION/CHANGELOG bump: only `bench/`, `tests/`, and (nothing in)
  `docs/` are touched — per the versioning law these paths need no bump.
- POSIX sh only across `bench/` and the owning suite; awk/sed/grep are the
  only parsing aids; no jq, python3, node, or any non-POSIX interpreter is
  required or invoked.
- The real bench never runs under `tests/run_all.sh`: the owning suite is
  hermetic (dry-run + stubs + report mode), keeping the suite law intact.
- Null beats zero; totals are null rather than silently partial; the outcome
  is read from disk, never from the client's prose.
- A measurement never writes outside its sandbox and results; the user's real
  config and the checkout are read-only to it. Nothing is ever committed.

## Out of scope

- Parallel repetitions, multi-machine distribution, run resumption.
- Multiple fixture scenarios; tuning the fixture request for determinism of
  real outcomes (only the request and starting state are deterministic).
- The `/antz` slash-command entry path (primary-agent hop) and any third
  client adapter.
- Statistical analysis beyond the pinned six statistics; charts; auto-baselines.
- Any change to `agents/prompts/`, `agents/meta/`, `install.sh`,
  `scripts/orchestration/`.

## Sub-specs (dependency order) and relevant files

### 01-fixture (destination domain: bench-fixture)
The checked-in fixture and per-repetition materialization.
- `bench/fixture/scenario.txt` — the request text (new).
- `bench/fixture/repo/` — the toy project files (new).
- `bench/lib.sh` — materialization helper (new).

### 02-schema (destination domain: bench-schema)
The common telemetry record: field set, null discipline, outcome precedence,
artifact counters.
- `bench/lib.sh` — record emission, outcome classification, counters (new).
- `tests/bench-harness_test.sh` — the owning suite (new).

### 03-adapter (destination domain: bench-adapter)
The detect/invoke/collect adapter contract and the dry-run client.
- `bench/adapter-dryrun.sh` — the mock client (new).
- `bench/lib.sh` — adapter sourcing and the run-dir artifact convention (new).

### 04-clients (destination domain: bench-clients)
Real client adapters, sandbox/isolation, model pinning, subagent attribution.
- `bench/adapter-claude.sh` — Claude Code adapter (new).
- `bench/adapter-opencode.sh` — OpenCode adapter (new).
- `bench/lib.sh` — sandbox preparation, credential copy, checkout render (new).
- `install.sh` — read-only reference: detection predicate (lines ~99-110),
  `resolve_libdir`, `__ANTZ_SCRIPTS_DIR__` substitution; **not modified**.

### 05-runner (destination domain: bench-runner)
The runner CLI: modes, flags, detection/forcing, repetition loop, outputs,
exit contract, hermetic-suite law.
- `bench/antz-bench.sh` — the runner (new).
- `tests/bench-harness_test.sh` — the owning suite (new).
- `tests/run_all.sh` — read-only reference (mechanical glob discovers the new
  suite; no edit).

### 06-report (destination domain: bench-report)
Aggregate statistics and baseline comparison, standalone.
- `bench/antz-bench.sh` — the `report` mode (new).
- `bench/lib.sh` — statistics helpers (new).

### e2e-qa
User-visible CLI workflows: `benchqa-01` (dry-run N=3 + report), `benchqa-02`
(detection refusal + forcing), `benchqa-03` (baseline comparison), `benchqa-04`
(outcome matrix incl. timeout), `benchqa-05` (real client, live half judged by
mechanism), `benchqa-06` (standalone report).
