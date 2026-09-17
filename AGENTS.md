# antz

## Overview
Portable workflow definitions for the pi coding agent: they turn a vague prompt into a
spec-clarified, TDD-built, verified feature, with a single point of human contact (the
clarify phase). What ships is markdown — five subagents, two skills, one slash command —
plus the one extension file that dispatches the agents, all copied into `~/.pi/agent/`;
antz is never the base, it runs inside foreign repos.

## Design principle
**Steps and a few rules. Nothing else.** The flow says what happens in each phase and
which rules are not negotiable; it never prescribes the shape of what a model writes. No
output formats, no required fields, no "emit exactly these lines". Reasoning and the
questions to ask before adding anything are in `README.md` ("Design principle"); the
short version is:

- A **step** ("chain antz-tester into antz-implementer") stays. A **shape** ("report
  exactly these three lines", a `Verdict: fault=…` line, a `Seam:` field, an
  `{previous}` concatenation recipe) does not.
- Agents are 9–13 lines, `prompts/antz.md` is ~33, the whole flow ~111. A change that
  pushes those up needs a reason, not a reflex.
- Prefer a rule the model applies with judgement over a contract it must satisfy
  literally. If a better model would make the rule unnecessary, leave it out.

## Stack
- Markdown with YAML frontmatter — everything except `extensions/subagent.ts`, the one
  file of actual code.
- pi 0.85.x (installed: 0.85.1). `prompts/<name>.md` and `skills/<name>/SKILL.md` are pi
  built-ins; `extensions/*.ts` is pi's auto-discovery path for extensions;
  `agents/<name>.md` is the `subagent` extension's convention, not pi core.
- `bash` + coreutils for install. No runtime, no package manager, no build step.

## Commands
Install (user scope — makes antz available in every project), then `/reload` in pi:

`mkdir -p ~/.pi/agent/{agents,extensions} && cp -r extensions/* ~/.pi/agent/extensions/ && cp -r agents/* ~/.pi/agent/agents/ && cp -r skills/* ~/.pi/agent/skills/ && cp -r prompts/* ~/.pi/agent/prompts/`

The `extensions/` copy is what makes the rest work: `subagent.ts` is the extension that
provides the dispatch tool every agent is run through (see Gotchas). pi core has no
sub-agents, so without it `/antz` has nothing to run.

Use, from inside a target repo: `/antz "<prompt>"`.

There is no build, test, lint, or CI. Verification is manual: install, run `/antz` against
a sandbox repo, and read what it writes (`<repo>/.antz/` mid-flight — antz-verifier
deletes it on PASS — and `docs/decisions/<slug>.md` afterwards).

## Structure
- `prompts/antz.md` — the slash command; routes on `.antz/` and orchestrates every phase.
- `agents/` — pi subagents: `antz-scout`, `antz-planner`, `antz-tester`, `antz-implementer`, `antz-verifier`.
- `skills/antz-clarify/` — the inquiry phase; the only phase that talks to the user.
- `skills/antz-tdd/` — red/green rules shared by antz-tester and antz-implementer.
- `extensions/subagent.ts` — the dispatch tool: single, parallel (max 4), or chain.
- `README.md` — the design of record for this repo.

Flow: antz-scout (recon) → clarify (spec) → antz-planner (plan) → antz-tester→antz-implementer
per task → antz-verifier, once per round, with every task green. Independent tasks may run
in parallel (max 4). On failure the verifier names the task and whether the test or the
implementation is at fault, and the loop goes back for that task alone — a test fault to
antz-tester, an implementation fault to antz-implementer, never both. Max 3 attempts per
task. `/antz` re-enters at the right phase by reading `.antz/`, never by memory.

Per target project: `<repo>/.antz/` is scratch space, and antz-scout creates it with a
`.gitignore` containing `*` so it never appears in `git status` and the host repo's
`.gitignore` is never edited. The only artifact meant to survive is
`docs/decisions/<slug>.md`, written by antz-verifier on PASS.

## Gotchas
- Intermediates are numbered and referenced by name in the prompts: `00-recon.md`,
  `01-spec.md`, `02-plan.md`. Renaming one breaks the chain. There is no
  `03-verification-report.md` anywhere in the flow: antz-verifier returns its verdict as
  text, and on PASS it writes `docs/decisions/<slug>.md` and deletes `.antz/`.
- The verifier's verdict lives in the orchestrator's context, not on disk, so a session
  restart between the verdict and the repair loses the test-vs-implementation
  distinction and sends the task back through the full tester→implementer chain. That is
  a deliberate trade, not an oversight: persisting it would mean an on-disk verdict
  format, and the design principle says no.
- Every artifact is written in English, but clarify asks its questions in the user's
  language. Don't switch the files to the user's language or vice versa.
- `antz-verifier` runs once per verification round, never per task, and the repair loop
  stops after 3 failed attempts per task — on the 4th it leaves `.antz/` as-is and reports
  instead of retrying.
- `[x]` in `02-plan.md` means *done*, not *verified* — the orchestrator marks it when the
  tester→implementer chain returns. That is why the verifier is told to run the tests
  itself and not trust the checkmarks.
- `docs/decisions/<slug>.md` is one living document per domain, not an append-only log:
  antz-verifier folds in what's new and drops what no longer holds. The slug names the
  domain, not the feature, so related features land in the same file.
- The `model:` frontmatter is deliberate in intent — antz-scout cheap/fast, antz-tester
  and antz-implementer capable, antz-verifier a different model family from
  antz-implementer so they don't share blind spots. Omitting the line inherits the
  session's model.
- It does not work today. `buildArgs()` in `extensions/subagent.ts` passes `-m`, which pi
  0.85.1 rejects (`Error: Unknown option: -m`), so **any agent with a `model:` line fails
  to dispatch**. No agent pins one today, which is the only reason the pipeline runs:
  leave the line out. The extension's own header warns that these one-shot flags have to
  be checked against `pi --help`.
- Even once that flag is fixed, auth bounds the choice: only `nan/*` models are usable in
  this environment (`~/.pi/agent/models.json` holds the only provider key), so anything
  else fails with "No API key found" until you `/login` that provider.
- `tools:` in the agent frontmatter is parsed but never forwarded to the child process,
  so it is not enforced: every agent gets every tool regardless of what it declares. Keep
  the declarations honest anyway, because the obvious fix (forwarding `--tools`) would
  make a declaration that contradicts the body bite immediately: antz-verifier's body
  writes `docs/decisions/` and deletes `.antz/`, so it declares `read, write, edit, bash`.
- `agents/` is not pi core: `extensions/subagent.ts` is what discovers
  `~/.pi/agent/agents/*.md` (or `.pi/agents/*.md` in a host repo) and exposes the
  dispatch tool. With it missing, `/antz` has no antz-scout to run.
- The install command starts with `mkdir -p` for a reason: `~/.pi/agent/agents/` does
  not exist by default, `cp` into a missing target fails, and the copies are chained
  with `&&`, so the first failure means the rest never copy.
- Installing clobbers only antz's own files: `prompts/antz.md` and the `skills/antz-*`
  directories. The generic user-level `~/.pi/agent/skills/tdd/` is left alone — antz
  installs as `skills/antz-tdd/`, a separate skill on the same subject with narrower,
  seam-focused rules. Don't confuse the two, or point at the wrong one.
- This repo is the successor to the elaborate phase/partition/`antzspec/` flow in the
  sibling `../antz` repo. Do not port that machinery — partitions, fact gates, ledgers —
  back in; the simplification is the point.
