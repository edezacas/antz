# antz

## Overview
Portable workflow definitions for the pi coding agent: a vague prompt becomes a
spec-clarified, TDD-built, verified feature, with one point of human contact (clarify). It
ships markdown — five subagents, three skills, one slash command — plus the one extension that
dispatches them, and one installer per client. `adapters/<client>/install.sh` copies that
client's artifacts, not this file: antz is never the base, it runs inside foreign repos. The
three skills are a separate, global `npx skills` install shared with Claude Code and OpenCode.
An adapter is a directory: `README.md` (its guide), `install.sh` (its one-line wrapper) and
`frontmatter/<agent>.yaml` wherever the client's block is not already pi's.

`README.md` is the design of record.

## Design principle
**Steps and a few rules. Nothing else.** A step ("chain antz-tester into antz-implementer")
stays; a shape ("report exactly these three lines", a `Seam:` field) does not. Prefer a rule
the model applies with judgement over a contract it satisfies literally, and ask whether a
better model would make it unnecessary. Agent files stay 9–13 lines and `prompts/antz.md`
~33; a change that pushes those up needs a reason, not a reflex. An adapter is a guide plus
the installer it ships with — paths, the frontmatter blocks, a check — never a rationale.

## Stack
Markdown with YAML frontmatter, plus bash for the install: the only code is
`extensions/antz-subagent.ts`, which imports pi's SDK only, and `adapters/install.sh` with
its three wrappers. No runtime, no build step. pi 0.85.x, and `npx skills` (Node >= 22.20)
only for the separate global skills install.
`prompts/<name>.md` and `skills/<name>/SKILL.md` are pi built-ins and `extensions/*.ts` is
pi's auto-discovery path, but `agents/<name>.md` is the extension's own convention, not pi
core.

## Commands
- Install (user scope, then `/reload` in pi):
  `curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/pi/install.sh | bash`.
  Uninstall with `--uninstall`. It never reads stdin, so every choice is a flag: from a
  checkout it copies that tree, alone it clones. `--ref` (default `master`) and `--dir` are
  pi's; Claude Code and OpenCode resolve `$CLAUDE_CONFIG_DIR` and `$XDG_CONFIG_HOME/opencode`
  instead. Smoke check any of the three in a scratch dir, twice, then `--uninstall`:
  `./adapters/pi/install.sh --dir "$(mktemp -d)"`, or a wrapper with the env var set.
- Install the skills, global and once: `npx skills add edezacas/antz -g`. The CLI detects
  which clients are installed and links them to one shared copy in `~/.agents/skills`, with a
  symlink per client that needs one. Outside the installers on purpose: the skills are shared,
  the per-client artifacts are not.
- Run it from inside a target repo: `/antz "<prompt>"`.
- Install on Claude Code or OpenCode: same shape, the `curl` one-liner in
  `adapters/<client>/README.md`. The installers are bash, not guide markdown, and they verify
  themselves; the guide is what a hand install follows.

The artifacts are prompts: no build and no lint, and verification of the flow is manual —
install, run `/antz` against a sandbox repo, read `.antz/` mid-flight and `docs/decisions/`
after. The code that is not prompt text is `extensions/antz-subagent.ts` and the installers,
and `eval/` has an instrument for the extension: `./eval/dispatch.sh` drives the tool with the
pi SDK stubbed — four shapes, concurrency cap, per-chain handoff, failure path, panel — free,
in a second, against the working tree; `./eval/run.sh` covers the repair loop and the shape
check as a rate over
`RUNS` runs and grades what is installed in `~/.pi/agent` (`eval/README.md`). The adapters
have no such instrument: the wrapper and the engine are exercised by the same scratch-dir
smoke check, which covers the bodies, the frontmatter block and the pin.

## Structure
- `prompts/antz.md` — the slash command: routes on `.antz/` and runs every phase.
- `agents/` — scout (recon) → planner (plan) → tester → implementer per task → verifier.
- `skills/antz-clarify/` — the spec phase, the only one that talks to the user.
- `skills/antz-tdd/` — red/green rules shared by antz-tester and antz-implementer.
- `skills/antz-architecture/` — where code belongs and how it is shaped, shared by
  antz-tester, antz-implementer and antz-verifier.
- `adapters/` — the install, one directory per client: its `README.md` (the install steps,
  nothing else), its `install.sh` wrapper and its `frontmatter/<agent>.yaml`. The per-client
  detail — target dirs, frontmatter rules, dispatch tool — is in Gotchas.
  `adapters/install.sh` is the engine they all call; a new client is that directory plus its
  target and preflight in the engine.
- `extensions/antz-subagent.ts` — dispatch: single, parallel (max 4), chain, or several
  chains at once (max 4 in flight, one per task). It renders one row per agent from tool
  details — model, thinking level, skills read, files, commands, last words — collapsed with
  ctrl+o for the whole trail.

## Gotchas
- Intermediates are numbered and referenced by name: `00-recon.md`, `01-spec.md`,
  `02-plan.md`. Renaming one breaks the chain.
- `prompts/antz.md` names no dispatch tool and carries no `name:` (pi takes the command name
  from the file), so its body is byte-identical on every client and only the frontmatter
  changes. Each client maps the tool in its own frontmatter: `Task` on Claude Code, `task` on
  OpenCode, `antz_subagent` on pi. Naming a tool there puts the per-client edit back.
- pi's agent files are copied whole — their frontmatter is already pi's. The other two are
  `adapters/<client>/frontmatter/<agent>.yaml` followed by everything after the second `---`
  of `agents/<agent>.md`, and those blocks are the whole per-client edit: Claude's tool map
  is `read→Read`, `write→Write`, `edit→Edit`, `bash→Bash`, `grep→Grep`, `find→Glob` (`ls`
  drops), with `skills:` as the preload and no `Skill` in `tools:` — and never
  `disable-model-invocation: true` on a preloaded skill, which cancels it. OpenCode's is
  `mode: subagent` plus a `permission:` map: `task: deny` and `question: deny` on all five,
  `bash: deny` only on the planner, `skill: allow` on the tester, implementer and verifier,
  and `shell:` instead of `bash:` on versions that reject it.
- OpenCode: a subagent waiting on approval hangs with no output, because `external_directory`
  and `doom_loop` default to `ask`. `opencode --auto` approves everything not explicitly
  denied; where a subagent's own rules are ignored, put the `allow`s in `opencode.json`.
- Artifacts are written in English; clarify asks its questions in the user's language.
- The verifier's verdict lives in the orchestrator's context, never on disk, so a restart
  between the verdict and the repair re-runs the whole chain. Deliberate: the alternative is
  an on-disk verdict format.
- Children dispatch in-process, each its own `AgentSession`, so the frontmatter bites:
  `tools:` is enforced, `model:` is pinned. They load no extensions, so nothing recurses, and
  their `details` feed a panel the model never sees — `content` is what the orchestrator
  reads, capped at 16 KB (in chain mode that content is the handoff to the next agent).
- Only pi has been run as a real install. Claude Code and OpenCode are written from the
  vendors' docs and exercised in a scratch dir, which is as far as "the body arrived byte for
  byte" goes.
- Every installer resolves its target the way its client does — pi `--dir`, then
  `$PI_CODING_AGENT_DIR`, then `~/.pi/agent`; Claude Code `$CLAUDE_CONFIG_DIR`, then
  `~/.claude`; OpenCode `$XDG_CONFIG_HOME/opencode` — and a reinstall preserves a local
  `model:` on all three. None of them installs skills: `--uninstall` sweeps the pi copy an
  older antz left behind, but the shared one in `~/.agents/skills` is `npx skills`' to remove.
