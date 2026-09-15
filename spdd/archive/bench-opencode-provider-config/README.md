# Change: bench-opencode-provider-config

The benchmark can measure OpenCode models whose provider is declared in the
host's `opencode.json` (e.g. `nan/*`), and the OpenCode credential reaches
the sandbox from the path the client actually reads.

## Goal

Two fixes in the bench-clients domain, both about which host client files a
measurement carries into its sandbox:

1. **Credential path drift (bug).** `bench/antz-bench.sh` (`do_repetition`)
   copies `auth.json` from `~/.config/opencode/` — the config dir — but
   OpenCode v1.18.31 reads credentials from its data dir
   (`~/.local/share/opencode/auth.json`; XDG_DATA_HOME-relocatable,
   verified via `opencode debug paths`). The owning spec (clients-03) and its
   test (`test_clients_03`) already pin the data dir; the runner call site
   drifts from both. Even `opencode-go/*` (key in `auth.json`) cannot
   authenticate in the sandbox today.
2. **Provider config carry (new capability).** A custom provider (`nan`,
   `npm: @ai-sdk/openai-compatible` with a `baseURL` and a models list) is
   declared in `opencode.json` only — never in `auth.json`. The sandbox
   carries no provider config, so OpenCode cannot resolve such models and
   every repetition ends `outcome=error` (reproduced on this host: empty
   sandbox → `UnknownError`; same sandbox with `opencode.json` copied in →
   proper `step_finish` with tokens).

## Contract (one paragraph)

Per repetition, the OpenCode preparation copies two host files read-only
into the sandbox's matching locations, mirroring the existing
credential-copy discipline (`bench_sandbox_copy_credentials`: copy when the
source exists, skip when it does not, make the destination non-writable,
never touch the source): the credential `auth.json` from the real data dir
(`${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json`), and the
provider config `opencode.json` from the real config dir
(`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json`). "Real" means
where the host's client actually reads the file — XDG-relocated when the
runner's environment sets it, the HOME default otherwise (verified against
OpenCode v1.18.31). The carry is byte-faithful and always-on. The Claude
path is unchanged.

## Design decision: always-on, byte-faithful carry (rationale)

- **Mirrors the existing discipline exactly.** The credential carry is
  strictly more sensitive than a config carry and is already unconditional,
  read-only, skip-if-absent. The provider config is the same class of host
  state; a second, gated mechanism for it would be one more contract to keep
  honest.
- **Gating would keep the default bench broken.** The diagnosed failure is
  the default path: `--model nan/<model>` without any flag produces all-error
  records today. A flag required for the headline use case is a tax, not an
  affordance, and it would add surface to a CLI whose flag set is pinned
  (runner-01) — an avoidable cross-domain change.
- **The isolation invariant governs writes, not reads.** The copy lands
  inside the sandbox; the host file is read-only to the measurement; the
  sandbox copy is made non-writable so the client cannot mutate its measured
  config mid-run.
- **Perturbation is the user's own client identity.** A host `opencode.json`
  may carry plugins/MCP/settings beyond the provider block; the bench
  measures "the client as this host has it" — its credentials already have
  the same property, and `client_version` is recorded alongside. Filtering
  the config down to provider blocks would silently measure a different
  client than the user's, and JSON surgery with awk is invention the harness
  avoids. Byte-faithful or nothing.

## Verified facts this spec is built on (investigated 2026-09-15)

- OpenCode v1.18.31: `opencode debug paths` reports data
  `~/.local/share/opencode` and config `~/.config/opencode`; with
  `XDG_DATA_HOME` / `XDG_CONFIG_HOME` set, both relocate (verified live).
- The host's `~/.config/opencode/opencode.json` declares the `nan` provider
  (plus unrelated settings — the perturbation concern is real); the data dir
  holds `auth.json`; `~/.config/opencode/auth.json` does not exist.
- `bench/antz-bench.sh:358-359` sources `auth.json` from the config dir —
  the drift. `spdd/specs/bench-clients.md` clients-03 and
  `tests/bench-harness_test.sh` `test_clients_03` (lines ~1862-1926) both pin
  the data dir.
- No `bench/` file references `opencode.json` today — the carry is new
  behavior.
- `install.sh` never writes `opencode.json`, so a carry that lands after the
  sandbox render cannot collide with the render's backup rules.
- `bench_sandbox_copy_credentials` (bench/lib.sh ~541-563) already implements
  the exact discipline the carry needs; the carry reuses it.
- The sandbox is deleted with each repetition (`rm -rf "$work"`), so the
  scenarios observe sandbox state through a recording stub OpenCode CLI that
  dumps what it sees beside itself — the established stub-recording pattern.

## Shared contracts (defined once, consumed identically)

- **Copy discipline** (clients-03, unchanged): copy when the source exists,
  skip when absent (nothing fabricated, run proceeds), destination made
  non-writable, source bytes and location never touched. Reused for both
  OpenCode files.
- **Real-dir definitions**: credential =
  `${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json`; provider config
  = `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json`. Sandbox
  destinations = the matching locations under the sandbox's relocated
  `HOME`/`XDG_CONFIG_HOME`/`XDG_DATA_HOME`.
- **Scenario-id continuity**: this change extends the bench-clients domain,
  so its scenarios form a new named group (`clientconfig-01..04`) inside
  that domain rather than renumbering the existing `clients-01..08` group —
  ids stay domain-unique for the coder's test tags.

## Invariants (change-wide)

- The host's real client files are read-only to a measurement; every carry
  lands inside the sandbox and is made non-writable there.
- Absence is skipped, never fabricated; the run proceeds either way.
- The carry is byte-faithful — no filtering, no rewriting.
- No new CLI surface, no record-schema change, no adapter change,
  no `install.sh` change.
- Hermeticity law unchanged: the owning suite launches no real client; the
  new scenarios use recording stubs only.
- No VERSION/CHANGELOG bump: only `bench/` and `tests/` are touched
  (`spdd/` docs need no bump per the versioning law). Nothing is committed.

## Out of scope

- Anything beyond the single `opencode.json` (`opencode.jsonc` variants,
  plugins, `node_modules`, `package.json`, `tui.json`).
- A Claude-side config carry; Claude's credential path already works.
- Gating flags/env vars for the carry (decided always-on, above).
- Record fields or run-dir artifacts describing the carry.
- Detection predicate changes; adapter invoke/collect changes.

## Sub-specs (dependency order) and relevant files

### 01-clientconfig (destination domain: bench-clients)
Which host client files a measurement carries into the sandbox, from where.
- `bench/antz-bench.sh` — `do_repetition`'s per-client preparation, the
  credential-copy call sites (~344-364): the drift fix and the carry land
  here (modified).
- `bench/lib.sh` — `bench_sandbox_copy_credentials` (~541-563), the
  discipline reused; `bench_sandbox_create` / `bench_sandbox_env`
  (~416-462), the sandbox relocation that defines the destination paths
  (read-only reference).
- `tests/bench-harness_test.sh` — the owning suite: `test_clients_03`
  (~1862-1926) pins the data-dir discipline at the helper level; the runner
  test helpers (~2302-2435: `make_bin_farm`, `stage_runner_checkout`,
  `bench_cli`, `make_runner_opencode_stub`) are the reuse path for
  full-runner stub runs (extended).
- `install.sh` — read-only reference: never writes `opencode.json`; **not
  modified**.

### e2e-qa
User-visible CLI workflows: `benchcfg-01` (bench a provider-declared model;
both files reach every sandbox; host untouched), `benchcfg-02` (live-session
scenario judged by mechanism: the pinned provider-declared model resolves —
telemetry non-null instead of the all-error pattern), `benchcfg-03` (no
provider config on the host: the run still completes, nothing fabricated).
