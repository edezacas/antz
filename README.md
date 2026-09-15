# antz

Spec-driven development (SPDD) as portable agent definitions: **specifier** turns a vague request into Gherkin behavior specs, **coder** implements, **verifier** validates and merges shipped behavior into a persistent spec. An **orchestrator** runs one change end to end and is the recommended entry point via `/antz`.

## Why

AI coding agents are good at writing code and bad at remembering what the system is *supposed* to do. Without a persistent spec, intent gets re-derived from scratch every session, ambiguity surfaces after the code is written instead of before, and a small feature can quietly change behavior nobody meant to touch.

antz addresses that — and it is priced to match the request instead of charging the worst case every time:

- **Two modes, one flow.** A bounded change to behavior that already exists takes the `direct` path — coder, then verifier — with no spec ceremony at all. A change that introduces or alters an externally visible contract, spans more than one layer, or isn't pinned down by its own request takes the `spec` path: Gherkin scenarios first, then one coder session per sub-spec.
- **Clarity before code, where it pays.** In spec mode, a genuine ambiguity blocks implementation (`OPEN_QUESTIONS.md`) instead of getting guessed away. In direct mode, the coder escalates (`ESCALATE`) if the work turns out larger than one session.
- **Specs that persist.** The verifier merges each shipped scenario into `spdd/specs/<domain>.md`, so the next session reads what the system actually does instead of re-deriving it from code or chat history.
- **Scenarios that are tests.** A scenario's id is its test name and its body enacts the Given/When/Then — one artifact, no step-definition layer, nothing to drift.
- **Only observable behavior earns a scenario.** Wording, policy, and structure become a short acceptance checklist, never Gherkin.
- **Marked by branch, never touched by git.** Every `/antz` flow gets its own marker branch (`antz/<slug>`, pointing at the commit the flow started from), but nothing is ever committed or removed for you: the work stays uncommitted in your working tree, where you keep full control.
- **State on disk, never in chat.** The orchestrator reconstructs everything from the working tree on every invocation: open questions, the rejection count, the tests already written. Interrupting and resuming days later works, and no role's prose is ever the input to a routing decision.
- **Guarded automation.** The flow stops and reports whenever something needs a human call: an ambiguous change, an open question, a stuck sub-spec, or a rejection that doesn't trace back to a single sub-spec.

## What you get

```
                    your request (/antz <request>)
                              |
              +---------------+----------------+
              |                                |
         direct mode                        spec mode
     (bounded change to                 (new/changed contract,
      existing behavior)                 ambiguous request)
              |                                |
     coder -> verifier                 specifier -> coder (per sub-spec)
              |                          -> verifier
              |                                |
              +---------------+----------------+
                              v
                  Gherkin sub-specs (spec mode only)
                  code + tests (scenario id = test name)
                  spdd/specs/ updated on approval
                              v
                all work uncommitted on branch antz/<slug>
                              |
                     you: review, commit, merge,
                     delete the branch
```

- **For a bounded change, two sessions and no ceremony.** No change directory, no Gherkin, no receipts: the request itself is the acceptance basis the verifier walks against your diff.
- **For a change that needs specifying, a spec you can trust exists before code does.** Gherkin scenarios with per-scenario ids, written against the real codebase, so every test name traces back to an intended behavior and every approval updates the persistent spec.
- **One sub-spec at a time, in dependency order.** Implementation sessions stay small and focused; each is verified before the next starts.
- **Honest failure handling.** Genuine ambiguity stops work (`OPEN_QUESTIONS.md`); a stuck sub-spec stops it too (`BLOCKED:`); a verification failure gets one bounded retry, and a second rejection stops the flow for good instead of looping on a broken change.
- **You stay in control of git.** The flow never commits, never forces anything, and never deletes anything: you review the diff, commit selectively, decide where to merge, and clean up.

## Agent Compatibility

Currently compatible with:
- Claude Code
- OpenCode
- Pi

## Requirements

- **`git`** — required to run `/antz`. Every flow is marked by its own branch `antz/<slug>`, so the orchestrator needs `git` on `PATH` and to be run inside a git repository with at least one commit. It fails closed (never falls back to an unbranched mode) if either is missing — install `git` and/or run `git init` plus an initial commit yourself first. Because nothing is ever committed for you, a *new* flow refuses a dirty working tree (`state=tree_dirty`): review and commit a finished change before starting the next one. Re-invoking the same change resumes it and is never blocked.
- **POSIX `sh`** — `install.sh` and the installed flow script are plain `sh`, no bash-only syntax; any POSIX-compliant shell works.
- **`curl`** — only needed to install without a local checkout (`curl | sh`, and `install.sh --check` run the same way); a local checkout installs from disk instead.
- Claude Code, OpenCode, and/or Pi installed, for `install.sh` to detect and target.

# Install

Renders the agent definitions under `agents/prompts/` + `agents/meta/` into native subagent files for whichever of Claude Code / OpenCode / Pi are detected, and installs them into that client's global agents directory (`~/.claude/agents/`, `~/.config/opencode/agents/`, `~/.pi/agent/agents/`).

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
./install.sh --pi        # force Pi only
./install.sh --all       # force all three
```

Re-running is safe: files this script generated are marked and get overwritten in place; a pre-existing, unrelated agent file with the same name is backed up (`<file>.bak.<timestamp>`) instead of being silently overwritten.

## Usage

Run `/antz <your request>` in Claude Code, OpenCode, or Pi after installing. It delegates to `antz-orchestrator`, which picks the mode, runs the flow for one change, and picks up correctly even if interrupted and resumed later. Every change gets its own marker branch `antz/<slug>`, while all work stays uncommitted in your checkout; the underlying roles are also directly invokable for manual/expert use outside any flow.

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
