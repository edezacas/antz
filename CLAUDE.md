# antz

## Overview
`antz` is a spec-driven development (SPDD) workflow of portable agent definitions: **specifier** writes Gherkin behavior specs, **coder** implements one sub-spec per session, **verifier** validates, **orchestrator** sequences the three; `/antz` is the recommended entry point.

## Stack
- Role instructions live in `agents/prompts/<role>.prompt`; `agents/meta/<role>.yaml` holds `name`, `description`, `access`. Keep prompt bodies framework-agnostic.
- No build system, package manager, or runtime. `install.sh` (POSIX `sh`, `curl | sh`-runnable) renders each pair into the target framework's native subagent file under `~/.claude/agents/` or `~/.config/opencode/agents/`.

## Structure
- `agents/prompts/{specifier,coder,verifier,orchestrator}.prompt` — role instructions verbatim, no framework syntax.
- `agents/meta/{specifier,coder,verifier,orchestrator}.yaml` — `name`, `description`, `access`.
- `spdd/{changes,specs,archive}/` — all three exist: `spdd/changes/` in-flight changes, `spdd/specs/` per-domain specs, `spdd/archive/` archived changes. The specifier creates `spdd/changes/<slug>/`; the verifier writes `spdd/specs/` and moves approved changes to `spdd/archive/`.

## Gotchas
- **Self-hosting.** This repo develops itself through `/antz`; the workflow contract lives verbatim in `agents/prompts/*.prompt`, enforced by `tests/` and the probe — this file deliberately does not restate it. Machine-read contracts (receipts, `REJECTED.md` headings, probe fields) are specified in `spdd/specs/`.
- **No commits.** Flow work is never committed; it stays uncommitted in the tree on `antz/<slug>`.
- **Machine-read state.** Never hand-edit `spdd/changes/` or `spdd/archive/`.
- **Prompt edits.** Editing `agents/prompts/` pulls in the Versioning law and the Working-Root triplication: `## Working Root` is byte-identical across the three role prompts — edit all three; `tests/roles_test.sh` flags drift.

## Client Integration
- `install.sh` renders each `<name>.prompt` + `<name>.yaml` pair into each framework's frontmatter (Claude Code: `name`/`description`/`tools:`; OpenCode: `description`/`mode`/`permission:`) and installs it globally. `readonly` → no edit/write; `readwrite` → full edit plus `Skill` on Claude Code (OpenCode inherits it); `orchestrateonly` → readonly plus delegation (the `readonly` level stays defined though unused).
- Files `install.sh` writes carry an `antz:generated` marker in the frontmatter; re-running overwrites them in place but backups (`.bak.<timestamp>`) any same-named file lacking the marker. It also installs the orchestration scripts and the set-model script under `${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/` under the same rules.
- `install.sh` runs from a local checkout or via `curl | sh` (`RAW_BASE`, ref default `master`, overridden by `ANTZ_REF` — used verbatim, never validated, remote path only); `VERSION`/`CHANGELOG.md`/tagging track on `master`. `/antz` installs to `~/.claude/commands/antz.md` and `~/.config/opencode/commands/antz.md` under the same rules (mechanism in `docs/law-notes.md`).

## Benchmark
- `bench/` (usage in `README.md`) measures the antz flow: each repetition materializes the fixture and runs a client headless, writing one telemetry record per repetition. It is repo-local and never installed; the real (LLM-invoking) bench never runs under `tests/run_all.sh` (hermetic owner: `tests/bench-harness_test.sh`, spec `spdd/specs/bench-runner.md`).
- **Sandbox credentials.** The sandbox carries only the client credential file (`~/.claude/.credentials.json`, `~/.config/opencode/auth.json`), never `opencode.json`/provider config. A model whose provider is configured inline there (e.g. `nan` with its own `baseURL`) yields all-`error` records, not measurements — pin a model whose auth lives in `auth.json` (e.g. `opencode-go/...`) or extend the sandbox to carry provider config.
- **Results vs baselines.** `bench/results/` is gitignored (never commit it); curated baselines live in `bench/baselines/`. Records **append** to `--jsonl`, so a baseline is a single run — don't measure into it again.

## Test suite law

Tests assert current-version product behavior. Never history, never prose.

- One owning suite per behavior surface: extend the owner, never duplicate. Deleting a test needs no justification; adding one does.
- No suite compares the working tree to git HEAD, pins past versions, reads in-flight `spdd/changes/` paths, or asserts literal prompt/doc sentences. Migration-window guards die in the same change that adds them.
- New tests are never mandatory: an existing suite, a runtime check (probe/flow), or an explicit drop satisfies a scenario.
- `sh tests/run_all.sh` stays hermetic and under 120s (`spdd/specs/test-runner.md` runner-04). `tests/hygiene_test.sh` enforces these rules. A red run means a real regression or a law violation — nothing else.

## Versioning
- `VERSION` (semver) and `CHANGELOG.md` (Keep a Changelog) track `agents/prompts/`, `agents/meta/`, and `install.sh`; any commit touching those bumps `VERSION` and adds a same-commit `CHANGELOG.md` entry (patch: wording/refactor; minor: role or rendered behavior; major: workflow/command contract change). Grade multi-path commits by the most severe component; docs (`AGENTS.md`, `CLAUDE.md`, `docs/`, `spdd/`) and `tests/` need no bump. `install.sh` is tracked because it embeds the source `VERSION` in each installed marker, so an unbumped `install.sh`-only change would leave installed copies stale while `--check` stays silent.
- `install.sh` embeds `VERSION` in each installed file's marker and, on a newer install, prints the intervening `CHANGELOG.md` entries before overwriting; `--check` only reports. Every `VERSION` bump gets a local `vX.Y.Z` tag on the bump commit in the same change; tags push only on explicit request.
