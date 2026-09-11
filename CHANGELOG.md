# Changelog

All notable changes to the antz agent definitions (`agents/prompts/`, `agents/meta/`) and to `install.sh` (which renders and installs them) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/): patch for
non-behavioral wording tweaks, minor for behavior changes, major for breaking
changes to the workflow contract (directory layout, access model, etc).

This branch (`master`) carries the branch-marked, no-commit variant of antz; the `worktree` branch carries the worktree-isolated variant (worktree isolation + gated per-role commits), whose `install.sh` binds its remote install to its own ref.

## [4.1.0] - 2026-09-11

### Changed
- **The specifier and verifier declared `access: readonly` while their own prompts required writing their core artifacts — corrected to `readwrite` for both.** `agents/meta/specifier.yaml` (authors `spdd/changes/<slug>/`: README.md, numbered `.feature` files, `OPEN_QUESTIONS.md`) and `agents/meta/verifier.yaml` (merges into `spdd/specs/`, owns `spdd/archive/` moves, appends `REJECTED.md`) now declare `access: readwrite`, so both clients render edit capability for them (Claude Code: `tools: Read, Grep, Glob, Bash, Edit, Write`; OpenCode: `mode: subagent`, `edit: allow`, `task: deny`) instead of silently completing with zero files written. The rendered output for `coder` and `orchestrator` is unchanged byte-for-byte. The safety boundary was never tool absence and still isn't: prompt-level path ownership per role plus the never-commits law, in the prompts. A path-restricted new access level was considered and dropped — neither client's permission layer can scope edits to paths, so it would have been an illusion of least privilege; `access: readonly` maps to no edit/write capability in both `install.sh` mappings, which are retained unchanged as a defined level (post-change no meta file declares readonly). Docs corrected to match: AGENTS.md and CLAUDE.md's access-model gotcha bullet (byte-identical between the two) and `docs/orchestrator.md`'s delegation-scoping paragraph.
- This grades as **minor**, not major: the rendered agents' capability changed (behavior change to the roles), but the workflow contract's access model itself is unchanged — the `access` taxonomy (`readonly | readwrite | orchestrateonly`), the access-to-frontmatter mapping, the `antz:generated` marker format, the directory layout, and the install locations are all untouched, so no consumer breaks; the precedent is that adding `orchestrateonly` (3.0.0) was major because it broke the then-documented access contract, while this broadens capability to match what the prompts always required.

## [4.0.0] - 2026-09-11

### Changed
- **Breaking (workflow contract): the flow's session now sits on the marker branch.** The orchestrator's embedded `antz-flow.sh` `ensure` no longer stops at creating the marker branch `antz/<slug>` at the flow's base commit — it now also checks the branch out on the fresh path (branch created at the current HEAD and the session positioned on it, `state=created`) and re-positions onto it on the resume path (`state=reused`; the branch ref is never rewritten), so every role's uncommitted work lands on the flow branch instead of whatever branch the session happened to be on. The positioning is refused, never forced: when git would have to overwrite uncommitted changes to switch, `ensure` stops with the machine-readable `state=checkout_refused` (exit 1) — nothing is ever forced or altered (no `--force`, no `-B`, no resets, no deletes), and the user resolves the conflict themselves. The never-commits law is fully intact: no role ever commits anything on any branch, and the marker branch still points at the commit the flow started from forever; a failed creation reports the truthful `state=no_branch`, never a false `state=reused`.
- **Breaking (workflow contract): the human follow-ups are the user's own decisions.** After an approved Merge & Archive and `release`, the user is already on `antz/<slug>` (ensure positioned the session there) and sees the pending files in `git status`: they review and commit whenever and how they prefer, then themselves decide whether and where to merge (e.g. `git switch <integration> && git merge antz/<slug>` — `<integration>` is a placeholder; the target branch is the user's to name — the orchestrator never hardcodes an integration branch name) and may delete the branch. The orchestrator never runs the follow-ups, never merges, and never resets a branch. The release gate, `discover`, and `state` keep their exact contracts.
- tests: `tests/antz-flow_test.sh`'s no-checkout assertion is inverted into a checkout/positioning assertion (fresh create and positioning, resume re-positioning, the refused stop, the truthful `state=no_branch`), with the never-commits and no-destruction guarantees still tested.

## [3.0.0] - 2026-09-10

### Changed
- **Breaking (workflow contract): no role commits anything, in any phase.** The per-role `antz-commit.sh` fences and their `## Committing` sections are gone from the specifier, coder, and verifier prompts, and the verifier's Merge & Archive move is via `git mv` (or a plain `mv` — the release gate only reads the working tree now), so every invocation, orchestrated or manual, leaves its artifacts uncommitted; committing the finished work is always the human's follow-up.
- **Breaking (workflow contract): the flow is branch-marked, not worktree-isolated.** The orchestrator's embedded `antz-flow.sh` was rewritten: `ensure` just creates the marker branch `antz/<slug>` at the main checkout's HEAD (never checked out, no `-B`/`--force`, `state=reused`/`state=created`, `state=no_commits` on an unborn repo); `state` verifies the marker branch and points `CHANGE_DIR` at the working tree's `spdd/changes/<slug>` (the resumable state — branch trees stay identical to the flow's base commit since nothing is ever committed); `release` gates only on the working tree (`spdd/archive/<slug>` present, `spdd/changes/<slug>` absent, marker branch present) and removes nothing, ever. `discover` lists `candidate=branch` markers (worktree plumbing and candidate classes: orphan/missing/conflict are gone) plus `candidate=on-disk` change dirs. The orchestrator prints the human follow-ups as `git add -A && git commit` / `git branch -d antz/<slug>` instead of merge commands
  (the marker branch never carries new commits, so there is nothing to merge). The coder's sequential-only rule now reasons about the shared working tree instead of the shared git index. The worktree-isolated flavor of all of this lives on in the `worktree` branch.
- tests: `tests/antz-flow_test.sh` rewritten for the branch-only script (16 tests: branch creation/reuse/no-checkout, probe state routing, release gates and no-removal, a never-commits guarantee, and the no_git/no_repo preflight); `tests/antz-commit_test.sh` deleted with the fence it guarded.

## [2.4.0] - 2026-09-10

### Fixed
- install.sh no longer kills the documented `curl | sh` install on macOS: bash 3.2 (the `/bin/sh` of macOS, in POSIX mode) mis-parses a heredoc whose body is captured inside a command substitution (`script=$(cat <<'SCRIPT' …)`), so the first `;;` inside the emitted `/antz-set-model` script surfaced as `syntax error near unexpected token ';;'` at line 230 and the install aborted before writing anything. All three offending heredocs (the embedded set-model script and the two per-client interactive-picker paragraphs) are now carried by top-level, no-argument emitter functions and captured via plain POSIX function-capture syntax, which every shell parses. Rendered output — all agent files, both `/antz` and `/antz-set-model` command copies, markers, VERSION embedding, flags, install paths — is verified byte-identical to the 2.3.0 render, and the plain-POSIX-sh parse/execute behavior is asserted unchanged. New mechanical regression guard plus a bash 3.2 reproduction helper under `tests/` (see `install.sh`'s comments and change `fix-install-sh-syntax`).

## [2.3.0] - 2026-09-10

### Changed
- Orchestrator prompt (`antz-flow.sh`): an explicit preflight fail-closes every subcommand (`discover`/`ensure`/`state`/`release`) with its own machine line when git is absent from the environment — `state=no_git` (the git executable is not on PATH) or `state=no_repo` (the directory, or any parent, is not a git repository, git's `fatal:` stderr suppressed in favor of the machine line). Previously both surfaced only as `set -eu`'s silent git invocation failure (exit 127/128, stdout empty, no `state=`/`candidate=` line), so the orchestrator's output contract had no defined action for them; per the user's decision there is no non-isolated fallback mode — `no_git` stops with an install-git report and `no_repo` (like `state=no_commits`) asks the human to `git init` themselves, never scaffolding either. Both rows added to step 1's action table. New flow tests 18–19 cover `discover` and `ensure` under a sanitized PATH and a non-repo directory.

## [2.2.0] - 2026-09-10

### Fixed
- Orchestrator prompt (`ensure`): `reuse_or_conflict`'s reused branch now exits 0 like ensure's direct reused path — previously it only printed and fell through, so the racing call re-entered the `worktree add -b` and attach attempts (two git invocations doomed to fail) and printed a second `state=reused` line, breaking any caller expecting exactly one `state=` line. A new flow test forces that path deterministically (registered worktree with branch intact, dir deleted, and a git shim that re-creates the dir and fails the attach, simulating the losing concurrent ensure) and asserts a single `state=reused` line.
- Orchestrator prompt (`release`): git's stderr on a refused `git worktree remove` is collapsed to spaces before emission, so the documented `git_error: <message>` output is always a single line even for multi-line git errors (e.g. a `fatal:` with a trailing `hint:`); the release-output table's wording now states the single-line contract.

## [2.1.0] - 2026-09-10

### Changed
- Orchestrator prompt: the per-sub-spec `coder` sessions of one change (step 3) are now explicitly sequential, never parallel — they share the working root's single git index, so a concurrent pair's commits envelope into whichever session commits last (one commit sweeps both sessions' files under its message; the other then fails its empty-staging check despite having done real work).
- Orchestrator prompt (`ensure`): a concurrent `ensure` of the same slug no longer surfaces as a spurious `state=conflict`. When `git worktree add -b` fails, the script falls back to attaching (the branch may have just been created by the concurrent call) and, before reporting `conflict`, re-checks for the valid reused state (`path` present and registered) and reports `state=reused` instead; the same reused-recheck applies to the `state=attached` path's failure arm via a shared `reuse_or_conflict` helper. The non-atomic grep-then-append on `.git/info/exclude` (two concurrent ensures may duplicate the line) stays as is — the exclusion is idempotent, so the race is harmless and now noted in a script comment.
- Orchestrator prompt (`discover` → `ensure` consistency): `candidate=orphan` (branch registered nowhere, no directory at its path) and ensure's branch-without-worktree case describe the same disk state, so the old "report the restore command and stop; never recreate it" row is gone — attaching is non-destructive (verbatim re-checkout of the branch, no `-B`/`--force`), so an orphan with `change=in-changes`/`none` resumes via `ensure` (`state=attached`); an orphan with `change=archived` is merged-approved and must not be re-attached. `candidate=missing` (registered-but-dir-missing) keeps its stop-and-report action and now states why ensure must not run against it.
- Orchestrator prompt (`state`): the flow script's `worktree=missing` output (working root vanished mid-session) is now documented — stop, re-run step 1, route on the fresh state.
- Orchestrator prompt (`release`): git's stderr on a refused `git worktree remove` is no longer forwarded raw — it is captured and emitted as an explicit `git_error: <message>` line after `gate=refused reason=remove-failed`, documented in the release-output table.
- Verifier prompt: the mover commit now passes the exact `spdd/specs/` domain file(s) it merged into instead of the whole `spdd/specs` directory (shared across changes — a directory add there is recursive and could sweep an interrupted session's leftovers under this change's message); `spdd/archive` stays a directory arg and the rejection reporter keeps passing the change dir, both now documented as the authorized directory exception (whole subtree is this flow's own artifact). Same rule added to the specifier prompt for the change dir; the unqualified "never sweeping" claim is scoped accordingly.

## [2.0.0] - 2026-09-10

### Changed
- **Breaking (workflow contract): each change's flow now runs isolated in its own git worktree.** The orchestrator's embedded `antz-flow.sh` (`discover`/`ensure`/`state`/`release`, same save-a-temp-and-`sh` convention as the existing probe script) creates/attaches `<repo-root>/.worktrees/<slug>` on branch `antz/<slug>` — never destructively (no `-B`, no `--force`, no prune; branch-without-dir attaches, plain-directory or registered-but-missing stops and reports) — and passes that absolute path as the delegation's Working Root. Every delegation carries the Working Root, and each role's prompt gains a `## Working Root` section (`cd '<root>'` as the session's first Bash action, re-`cd` on later calls since a client's Bash cwd may reset between calls, install host-project dependencies inside the fresh worktree before running the suite). The orchestrator's probe now runs with `CHANGE_DIR` resolved inside the worktree (never the main checkout's `spdd/changes/`), so all cross-role disk state (sub-specs, `OPEN_QUESTIONS.md`, `REJECTED.md`) is read from the isolated branch state. Slug derivation moves from the old learn-by-diffing to mechanic-imposed: a short kebab-case slug derived from the request and checked against `spdd/changes/`, `spdd/archive/`, `git branch --list 'antz/*'`, profusely suffixed only into an already-claimed change and only with human sign-off on the continuation.
- Commits are gated on the Working Root: each role's prompt carries the shared `antz-commit.sh` fence, which exits 1 without `WORKING_ROOT` (manual/direct invocation stays as uncommitting as before), stages only exact paths (no `-A`, refused outright by an explicit flag blocklist), and refuses empty trees. Commit ownership: specifier commits `spdd/changes/<slug>` per session (including `OPEN_QUESTIONS.md`, since its presence is a hard stop); coder commits its touched implementation/tests (including `BLOCKED:` stubs, so they survive worktree removal); verifier commits per session (Merge & Archive now via `git mv`, and On Rejection for `REJECTED.md`).
- Worktree removal is a single disk-checked gate: after an approved Merge & Archive, `release` reads `<worktree>/spdd/archive/<slug>` (must exist) and `spdd/changes/<slug>` (must not), plus a path-mismatch check against `.worktrees/<slug>` — any failure prints `gate=refused` and stops with no `--force`; on success the branch `antz/<slug>` survives the removed worktree for human review, and the orchestrator prints (never runs) the human merge commands, with the integration branch named by the user, never hardcoded.

## [1.8.0] - 2026-09-09

### Changed
- Specifier prompt: the "## Output" section now fixes `README.md` as the name of the change's overview file (goal, contract, shared contracts, invariants, out-of-scope, relevant-files pointers) in its own dedicated bullet, instead of only implying that name via the one existing bullet that mentions it in passing (the optional Entities/Operations table). The Entities/Operations table bullet no longer repeats the file name itself — it now relies on this new bullet, so `README.md` is stated exactly once across the whole "## Output" section.

## [1.7.0] - 2026-09-09

### Added
- Specifier prompt: the "## Output" section now documents an optional Entities/Operations table the specifier may include in a change's `README.md` when the change introduces a new data shape (entity, model, or interface) or multiple named operations (endpoints, CLI commands/flags, steps, events) — an entities table (Name, Path, New-or-Existing, Notes) and/or an operations table (Type, Identifier, Description), pruned per the existing example-table pruning rule. The table is a scannable complement only: never mandatory, and never a substitute for the tagged Gherkin scenarios, which remain the actual testable behavior spec. A change with no new data shape and only one operation is not forced to produce a near-empty table, and no section is required to be marked "not applicable" when empty — only the table format itself is adopted as an available tool, not the rigid always-fill-every-section convention of the `open-spdd` `spdd-canvas` skill this was compared against.

## [1.6.0] - 2026-09-09

### Changed
- Orchestrator probe script: hardened against the failure modes a review of 1.5.0 surfaced. (1) Scenario ids are now extracted only from the first line of the comment tag immediately above each `Scenario:`/`Scenario Outline:` line (an awk pass tracks the tag block and emits its first line on the scenario keyword), so an id-shaped token anywhere else — a loose comment (`invariant-2` in a `# NOTE:` line) or a tag description's cross-reference to another scenario (`same refusal message as set-model-cmd-06`, as the repo's own archived specs do) — can no longer become a phantom id whose never-existing test keeps a sub-spec perpetually `in_progress` and re-delegates `coder` forever. `Scenario Outline:` (the specifier's documented example-table form) is matched alongside `Scenario:`, and a hyphenated feature name (`user-profile-1`) extracts whole instead of splitting into the unmatchable `profile-1`. (2) A `CHANGE_DIR` that isn't an existing directory prints `change_dir=missing` and exits nonzero, instead of reporting the cleanest possible state (no open questions, 0 rejections, no sub-specs) that invited routing straight to `verifier` on a mistyped slug; the prompt's output table gains the matching stop-and-recheck-slug row. (3) The `## Rejection <n>` heading count tolerates trailing whitespace on the line (a stray trailing space or CRLF) while headings with trailing text still don't count.
- Orchestrator prompt: a sub-spec whose `ids` list is empty is unclassifiable — stop and ask the user, never treat it as vacuously `done` (previously "all ids green or ordinary-skip" held vacuously over an empty list).
- Specifier prompt: the `<feature>-<index>` scenario-naming convention is pinned — `<feature>` is the sub-spec file's stem minus its numeric prefix and extension, one word (letters/digits/underscores, no hyphens or spaces), so spec tags and the coder's test-name ids agree; the tag comment's first line carries the ADD/MODIFY/REMOVE marker and the id, with the description wrapping below it, and tag descriptions must not cite other scenarios' ids (the orchestrator's probe reads ids from tag first lines only); sub-spec filenames now explicitly require a two-digit numeric prefix, matching the probe's `[0-9][0-9]-*` glob.

## [1.5.0] - 2026-09-09

### Changed
- Orchestrator prompt: reduced rule/context load by (1) deduplicating "What you don't do" bullets already implied by `Process`, (2) turning the `REJECTED.md`-count and probe-output branching into compact tables instead of nested prose, and (3) offloading the mechanical parts of disk-state computation (`OPEN_QUESTIONS.md` presence, `REJECTED.md`'s entry count, each sub-spec's declared scenario ids) to a small embedded POSIX `sh` probe script, following the same embedded-script convention as `/antz-set-model`. Discovering the project's test command and classifying pass/fail/`BLOCKED` per id remain the orchestrator's own judgment call, since that stays language/framework-specific. Net decisions are unchanged; only the mechanism moved from prose to a deterministic script the orchestrator runs itself.
- Verifier's `REJECTED.md` entries must now be headed by an exact `## Rejection <n>` line (nothing else on that line) instead of an informally "numbered" entry, so the orchestrator's probe script can count them by exact match rather than by an LLM re-reading free-form prose — the same "cheap insurance" rationale as the `BLOCKED: <why>` colon convention.

## [1.4.0] - 2026-09-08

### Fixed
- `/antz-set-model` (Claude Code and OpenCode): the embedded script was corrupted by the client's command-body templating before it ever ran — OpenCode rewrites every `$<digits>` token plus `$ARGUMENTS` anywhere in a command body (missing positionals become the literal string `undefined`), and Claude Code does the same for `$1`/`$2`/`$ARGUMENTS`, so the script's positional-parameter parser and awk whole-line variable were replaced with invocation arguments at invocation time and every invocation failed with `unknown agent '...'`. The emitted script now contains no dollar-digit token at all: flag values are captured through a pending-flag for-loop instead of positional parameters, and the frontmatter rewrite is a plain read/printf loop instead of awk, with identical observable behavior (a rendering-level regression test guards the constraint).

## [1.3.0] - 2026-09-08

### Changed
- `/antz-set-model` (Claude Code and OpenCode) now offers an interactive model picker when invoked without `--model` or `--clear`: the invoking session asks the user which model to assign via its native question mechanism (embedded documented alias vocabulary in Claude Code; invocation-time enumeration through `opencode models` in OpenCode), then runs the same embedded script with the chosen value as `--model`. Argument validation, install-state checks, and the `antz:generated` marker check now all happen before any question is asked. Explicit `--model`/`--clear` invocations behave exactly as before, and the script's one-of/verbatim-write contract is unchanged.

## [1.2.0] - 2026-09-08

### Added
- `/antz-set-model`, a client-native command (Claude Code and OpenCode) installed by `install.sh` alongside the four role agents and `/antz`. Lets a user configure or clear an already-installed antz agent's `model:` frontmatter, per agent and per client, by editing that agent's file directly in the invoking session — never delegating to any `antz-*` subagent. `install.sh`'s own agent-rendering logic gains no concept of `model:`: no agent ships with a configured model by default, before or after this change.

## [1.1.1] - 2026-09-08

### Changed
- Orchestrator prompt: wording pass (tightened phrasing, em dashes to colons, dropped redundant rationale) with no behavioral change.

## [1.1.0] - 2026-09-08

### Changed
- Specifier now reads `spdd/specs/` for the affected domain(s) before investigating the real code, and scopes that code investigation to what the spec doesn't cover, what the change touches, or suspected drift — instead of a full code-plus-specs sweep every time. Intent: specs exist to save tokens on redundant code review, not just to store behavior.

## [1.0.0] - 2026-09-08

### Added
- Fourth role, `orchestrator` (`agents/prompts/orchestrator.prompt`, `agents/meta/orchestrator.yaml`), sequencing `specifier -> coder -> verifier` for one change. Its entire Process is a stateless reconciliation routine: every invocation reconstructs the full picture from `spdd/` alone (numbered sub-spec filenames, scenario-id test tags, `BLOCKED:` stubs, `REJECTED.md` entry count — see the `0.3.0`-`0.5.0` entries above) and takes the one next action needed, so it can resume after any interruption with no memory of what it already did.

### Changed
- `access` gains a third value, `orchestrateonly` (readonly plus a delegation capability), used only by `orchestrator`. This breaks the previously-documented binary `readonly`/`readwrite` access contract, hence the major bump — `specifier`, `coder`, and `verifier` keep their existing `readonly`/`readwrite` access unchanged.

### Known Limitations
- On Claude Code, the orchestrator's delegation to `specifier`/`coder`/`verifier` is scoped by a prompt-level rule ("What you don't do"), not by the tool grant — see `CLAUDE.md` Gotchas.

## [0.5.0] - 2026-09-08

### Added
- Verifier now appends one numbered entry to `spdd/changes/<change-slug>/REJECTED.md` on each rejection (never overwriting), recording the reported blockers and, per blocker, the sub-spec it traces to or an explicit note that it doesn't trace to a single sub-spec.

### Changed
- Verifier's Input Rule now supports a whole-change invocation form: when invoked without a named sub-spec, it verifies every sub-spec with code present instead of stopping, flagging any unimplemented sub-specs in the report.

## [0.4.0] - 2026-09-08

### Changed
- Coder now tags every test's name with its scenario's `<feature>-<index>` id (not just a comment), writes an explicit `skip`/`pending` stub for a scenario it won't automate instead of omitting it silently, and checks for already-passing/skipped tests before planning so a resumed session doesn't redo finished work.
- When coder refuses or escalates a sub-spec instead of finishing it, it now leaves a stub reasoned `BLOCKED: <why>` (scenario-scoped, or tagged with the sub-spec's first scenario id if refused at the planning stage) instead of leaving no trace on disk.

## [0.3.0] - 2026-09-08

### Changed
- Specifier now prefixes sub-spec filenames with a numeric dependency-order index (`01-api.feature`, `02-client.feature`, ...), so implementation order is readable from a plain directory listing without a separate ordering file.

## [0.2.0] - 2026-09-08

### Added
- Coder and verifier now refuse to run against the wrong workflow state instead of silently proceeding: missing `spdd/changes/<change-slug>/`, a sub-spec not found in it, an unresolved `OPEN_QUESTIONS.md`, or (verifier only) a sub-spec with no coder implementation yet all produce an explicit stop-and-report instead of best-effort work.

## [0.1.0] - 2026-09-08

### Added
- Three-role SPDD workflow: `specifier`, `coder`, `verifier` agent prompts and metadata.
- `OPEN_QUESTIONS.md` convention: its presence at `spdd/changes/<slug>/OPEN_QUESTIONS.md` blocks the coder until the specifier resolves and removes it.
- `install.sh` renders `agents/prompts/` + `agents/meta/` into Claude Code and OpenCode native subagent files, installed globally with an `antz-` name prefix to avoid collisions.
