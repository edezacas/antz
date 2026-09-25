# antz

## Overview
Portable workflow definitions for coding agents: a vague prompt becomes a spec-clarified,
TDD-built, verified feature, with one point of human contact (clarify). Five subagents, three
skills, one slash command, pi's dispatch extension and one installer per client.
`README.md` is the design of record; antz installs into a client, never into the repo it
later runs in.

## Design principle
**Steps and a few rules. Nothing else.** A step ("chain antz-tester into antz-implementer")
stays; a shape ("report exactly these three lines", a `Seam:` field) does not. Prefer a rule
the model applies with judgement over a contract it satisfies literally, and ask whether a
better model would make it unnecessary. Agent files stay 9–13 lines and `prompts/antz.md` 32;
a change that pushes those up needs a reason, not a reflex. An adapter's guide is the install
steps and nothing else: the per-client detail lives in its `frontmatter/`, never in prose.

## Stack
Markdown with YAML frontmatter, plus bash for the install: the only code is
`extensions/antz-subagent.ts`, which imports pi's SDK only, and `adapters/install.sh` with its
three wrappers. No runtime, no build step. pi 0.87.x, and `npx skills` (Node >= 22.20) only
for the separate global skills install. `prompts/<name>.md` and `skills/<name>/SKILL.md` are
pi built-ins and `extensions/*.ts` is pi's auto-discovery path, but `agents/<name>.md` is the
extension's own convention, not pi core.

## Commands
- Install (user scope, then `/reload` in pi):
  `curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/pi/install.sh | bash`.
  `--uninstall` takes it back out. Every installer verifies what it wrote and reads nothing
  from stdin. Smoke check any client in a scratch dir, twice, then `--uninstall`:
  `./adapters/pi/install.sh --dir "$(mktemp -d)"`, or a wrapper with `$CLAUDE_CONFIG_DIR` /
  `$XDG_CONFIG_HOME` set. From a checkout the wrapper installs that working tree, not a clone.
- Install the skills, global and once: `npx skills add edezacas/antz -g`. The CLI detects
  which clients are installed and links them to one shared copy in `~/.agents/skills`, with a
  symlink per client that needs one.
- Run it from inside a target repo: `/antz "<prompt>"`.
- No build and no lint: the flow is verified by hand — install, run `/antz` against a sandbox
  repo, read `.antz/` mid-flight and `docs/decisions/` after — and by two instruments:
  `./eval/dispatch.sh`, the dispatch tool with the pi SDK stubbed, free and deterministic
  against the working tree, and `./eval/run.sh`, the repair loop and the shape check as a rate
  over `RUNS` runs, grading what is installed in `~/.pi/agent` (`eval/README.md`).

## Structure
- `prompts/antz.md` — the slash command: routes on `.antz/` and runs every phase.
- `agents/` — scout (recon) → planner (plan) → tester → implementer per task → verifier.
- `skills/antz-clarify/` — the spec phase, the only one that talks to the user;
  `skills/antz-tdd/` and `skills/antz-architecture/` — the rules the tester, the implementer
  and the verifier read.
- `adapters/` — the install: one directory per client (its `README.md`, its `install.sh`
  wrapper, its `frontmatter/<agent>.yaml`) around `adapters/install.sh`, the engine all three
  wrappers call. A new client is that directory plus its target and preflight in the engine.
- `extensions/antz-subagent.ts` — dispatch: single, parallel (max 4), chain, or several
  chains at once (max 4 in flight, one per task), and it renders one row per agent from tool
  details, ctrl+o for the whole trail.

## Gotchas
- Intermediates are numbered and referenced by name: `00-recon.md`, `01-spec.md`,
  `02-plan.md`. Renaming one breaks the chain.
- `prompts/antz.md` names no dispatch tool and carries no `name:` (pi takes the command name
  from the file), so its body is byte-identical on every client and only the frontmatter
  changes. Each client maps the tool in its own frontmatter: `Task` on Claude Code, `task` on
  OpenCode, `antz_subagent` on pi. Naming a tool there puts the per-client edit back.
- The per-client frontmatter is data, not prose: `adapters/<client>/frontmatter/<agent>.yaml`,
  spliced onto everything after the second `---` of `agents/<agent>.md`, which pi copies whole
  because it is already pi's. Editing a block means keeping its traps: `ls` drops from
  Claude's tool map, `Skill` never appears in its `tools:` — the `skills:` key is the preload,
  and `disable-model-invocation: true` cancels it — and OpenCode's `bash:` is `shell:` on
  versions that reject it.
- Every installer resolves its target the way its client does — pi `--dir`, then
  `$PI_CODING_AGENT_DIR`, then `~/.pi/agent`; Claude Code `$CLAUDE_CONFIG_DIR`, then
  `~/.claude`; OpenCode `$XDG_CONFIG_HOME/opencode` — and `--ref` (default `master`) and
  `--dir` are pi's alone. A reinstall preserves a local `model:` on all three. None of them
  installs the skills: the shared copy in `~/.agents/skills` is `npx skills`' to remove.
- Children dispatch in-process, each its own `AgentSession`, so the frontmatter bites:
  `tools:` is enforced, `model:` is pinned. They load no extensions, so nothing recurses, and
  their `details` feed a panel the model never sees — `content` is what the orchestrator
  reads, capped at 16 KB (in chain mode that content is the handoff to the next agent).
- The verifier's verdict lives in the orchestrator's context, never on disk, so a restart
  between the verdict and the repair re-runs the whole chain. Deliberate: the alternative is
  an on-disk verdict format.
- Artifacts are written in English; clarify asks its questions in the user's language.
- Claude Code and OpenCode are verified in a scratch dir, which is as far as "the body
  arrived byte for byte" goes; only pi's install has run for real.
- OpenCode: a subagent waiting on approval hangs with no output, because `external_directory`
  and `doom_loop` default to `ask`. `opencode --auto` approves everything not explicitly
  denied; where a subagent's own rules are ignored, put the `allow`s in `opencode.json`.
