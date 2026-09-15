# antz

## Overview
`antz` is a spec-driven development (SPDD) workflow of portable agent definitions. **orchestrator** runs one change end to end in the cheapest mode that fits it — `direct` (a bounded change: coder, then verifier) or `spec` (specifier writes Gherkin sub-specs, coder implements one per session, verifier validates and merges); `/antz` is the recommended entry point.

## Stack
- Role instructions live in `agents/prompts/<role>.prompt`; `agents/meta/<role>.yaml` holds `name`, `description`, `access`. Keep prompt bodies framework-agnostic.
- No build system, package manager, or runtime. `install.sh` (POSIX `sh`, `curl | sh`-runnable) renders each pair into the target framework's native subagent file under `~/.claude/agents/`, `~/.config/opencode/agents/`, or `~/.pi/agent/agents/`.

## Structure
- `agents/prompts/{specifier,coder,verifier,orchestrator}.prompt` — role instructions verbatim, no framework syntax.
- `agents/meta/{specifier,coder,verifier,orchestrator}.yaml` — `name`, `description`, `access`.
- `scripts/orchestration/antz-flow.sh` — the flow's only git mutation (`start <slug>`); installed to the shared libdir, never run from the checkout.
- `spdd/{changes,specs,archive}/` — all three exist: `spdd/changes/` in-flight changes, `spdd/specs/` per-domain specs, `spdd/archive/` archived changes. The specifier creates `spdd/changes/<slug>/`; the verifier writes `spdd/specs/` and moves approved changes to `spdd/archive/`.
- `AGENTS.md` is the single source for this file's law; `CLAUDE.md` is a symlink to it, never a copy.

## Gotchas
- **Self-hosting.** This repo develops itself through `/antz`; the workflow contract lives verbatim in `agents/prompts/*.prompt` and is enforced by `tests/` — this file deliberately does not restate it. The machine-read contracts (the flow script's states, the change/archive layout, the `REJECTED.md` heading) are specified in `spdd/specs/`.
- **No commits.** Flow work is never committed; it stays uncommitted in the tree on `antz/<slug>`.
- **Machine-read state.** Never hand-edit `spdd/changes/` or `spdd/archive/`.
- **Prompt edits.** Editing `agents/prompts/` pulls in the Versioning law and the Working-Root triplication: `## Working Root` is byte-identical across the three role prompts — edit all three; `tests/roles_test.sh` flags drift.
- **Specs stay true.** A spec that describes behavior this change removed or rewrote is deleted or rewritten in the same change — a false spec is worse than no spec.

## Client Integration
- `install.sh` renders each `<name>.prompt` + `<name>.yaml` pair into each framework's frontmatter (Claude Code: `name`/`description`/`tools:`; OpenCode: `description`/`mode`/`permission:`; Pi: `name`/`description`/`tools:` plus `inheritProjectContext`/`inheritSkills`/`systemPromptMode`/`defaultContext`) and installs it globally. `readonly` → no edit/write; `readwrite` → full edit plus `Skill` on Claude Code (OpenCode inherits it; Pi maps to `inheritSkills: true`); `orchestrateonly` → readonly plus delegation (Claude Code: plain `Agent`; OpenCode: a `mode: primary` agent with a task glob allowlist; Pi: the `edit`/`write` pass-through grants plus the `subagent` tool in its allowlist — pi-subagents intersects a child's tool plan with the delegating session's available builtins, so a readonly orchestrator would strip the roles' writer tools; the `readonly` level stays defined though unused).
- Files `install.sh` writes carry an `antz:generated` marker as a line-start header comment; re-running overwrites them in place but backups (`.bak.<timestamp>`) any same-named file lacking the marker. It also installs `antz-flow.sh` under `${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/` under the same rules.
- `install.sh` runs from a local checkout or via `curl | sh` (`RAW_BASE`, ref default `master`, overridden by `ANTZ_REF` — used verbatim, never validated, remote path only); `VERSION`/`CHANGELOG.md`/tagging track on `master`. `/antz` installs to `~/.claude/commands/antz.md`, `~/.config/opencode/commands/antz.md`, and `~/.pi/agent/prompts/antz.md` under the same rules (mechanism in `docs/law-notes.md`).

## Test suite law

Tests assert current-version product behavior. Never history, never prose.

- One owning suite per behavior surface: extend the owner, never duplicate. Deleting a test needs no justification; adding one does.
- No suite compares the working tree to git HEAD, pins past versions, reads in-flight `spdd/changes/` paths, or asserts literal prompt/doc sentences. Migration-window guards die in the same change that adds them.
- New tests are never mandatory: an existing suite, a runtime check (flow script), or an explicit drop satisfies a scenario.
- `sh tests/run_all.sh` stays hermetic and under 120s (`spdd/specs/test-runner.md` testrunner-02). `tests/hygiene_test.sh` enforces these rules. A red run means a real regression or a law violation — nothing else.

## Versioning
- `VERSION` (semver) and `CHANGELOG.md` (Keep a Changelog) track `agents/prompts/`, `agents/meta/`, and `install.sh`; any commit touching those bumps `VERSION` and adds a same-commit `CHANGELOG.md` entry (patch: wording/refactor; minor: role or rendered behavior; major: workflow/command contract change). Grade multi-path commits by the most severe component; docs (`AGENTS.md`, `docs/`, `spdd/`) and `tests/` need no bump. `install.sh` is tracked because it embeds the source `VERSION` in each installed marker, so an unbumped `install.sh`-only change would leave installed copies stale while `--check` stays silent.
- `install.sh` embeds `VERSION` in each installed file's marker and, on a newer install, prints the intervening `CHANGELOG.md` entries before overwriting; `--check` only reports. Every `VERSION` bump gets a local `vX.Y.Z` tag on the bump commit in the same change; tags push only on explicit request.
