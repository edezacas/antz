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

## License

Code in this repository is licensed under [Apache-2.0](LICENSE)
