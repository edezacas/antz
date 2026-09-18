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
- Markdown with YAML frontmatter — everything except `extensions/antz-subagent.ts`, the one
  file of actual code.
- pi 0.85.x (installed: 0.85.1). `prompts/<name>.md` and `skills/<name>/SKILL.md` are pi
  built-ins; `extensions/*.ts` is pi's auto-discovery path for extensions;
  `agents/<name>.md` is the `antz-subagent` extension's convention, not pi core.
- `bash` + coreutils for install. No runtime, no package manager, no build step. The
  extension imports only pi's own bundled modules (`@earendil-works/pi-coding-agent`,
  `@earendil-works/pi-tui`, `typebox`) — nothing to `npm install`.

## Commands
Install (user scope — makes antz available in every project), then `/reload` in pi:

`curl -fsSL https://raw.githubusercontent.com/edezacas/antz-pi/master/install.sh | bash`

`install.sh` is the installer: it checks for `pi`, resolves the target
(`--dir`, else `$PI_CODING_AGENT_DIR`, else `~/.pi/agent`), and copies `agents/`,
`extensions/`, `skills/` and `prompts/` there. Run from a checkout it copies that working
tree; run on its own — the curl one-liner — it fetches `--ref` (default `master`) into a
temporary clone. Uninstall is `install.sh --uninstall`, which removes only antz's files.

It never reads stdin — under a pipe stdin is the script itself — so every choice is a flag.

The `extensions/` copy is what makes the rest work: `antz-subagent.ts` is the extension that
provides the dispatch tool every agent is run through (see Gotchas). pi core has no
sub-agents, so without it `/antz` has nothing to run.

Use, from inside a target repo: `/antz "<prompt>"`.

There is no build, lint or CI, and no unit tests: the artifacts are prompts. Verification
is manual: install, run `/antz` against a sandbox repo, and read what it writes
(`<repo>/.antz/` mid-flight — the orchestrator deletes it on PASS, once the decision is
written — and `docs/decisions/<slug>.md` afterwards). The installer is checked the same way, without
touching the real agent dir: `./install.sh --dir "$(mktemp -d)"`, twice for the
reinstall, then `--uninstall`.

The one exception is `eval/`: it seeds `.antz/` with a plan already complete and a
deliberate fault, so `/antz` enters at step 5 and the dispatch order — read back from the
session file — shows which agent the repair went to. That is the only part of the flow a
normal run never exercises, because a normal run almost never fails. It is an eval, not a
test: the routing is model judgement, so the result is a rate over `RUNS` runs and one
green run proves nothing. It costs money and minutes, it measures what is installed in
`~/.pi/agent` rather than the working tree (and refuses to run when the two disagree),
and it is the regression net for `prompts/`, `agents/` and `skills/`. The scenarios and
what each one asserts are in `eval/README.md`.

## Structure
- `prompts/antz.md` — the slash command; routes on `.antz/` and orchestrates every phase.
- `agents/` — pi subagents: `antz-scout`, `antz-planner`, `antz-tester`, `antz-implementer`, `antz-verifier`.
- `skills/antz-clarify/` — the inquiry phase; the only phase that talks to the user.
- `skills/antz-tdd/` — red/green rules shared by antz-tester and antz-implementer.
- `extensions/antz-subagent.ts` — the dispatch tool: single, parallel (max 4), or chain;
  every agent runs in-process as its own session, never as a child `pi`, and the tool is
  only offered during an `/antz` run. While it runs, a panel shows what each child is
  doing — files, commands, its own text — collapsed to one line per agent and expanded
  with `app.tools.expand` (ctrl+o).
- `README.md` — the design of record for this repo.
- `install.sh` — the only way in: preflight, copy or clone, verify, uninstall. Bash and
  coreutils only, like the manual copy it replaced; the gotchas below are the parts that
  must not regress.
- `eval/` — the repair-loop eval: seeded `.antz/` states that force a verification
  failure, and the dispatch trace that shows where the repair was routed. Bash, jq and a
  tiny Node fixture. Not part of the install — the installer copies only its four
  directories — and not a gate, because it needs models and minutes to run.
- `TODO.md` — known gaps, deliberate deferrals, and decisions not to re-open.

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
  text, and on PASS it writes `docs/decisions/<slug>.md` and stops; the orchestrator
  deletes `.antz/` once that document exists. The deletion is the orchestrator's because
  the run is over when the artifact is on disk, and because a step that forgets a
  trailing `rm` costs a whole repair round to notice.
- The panel is fed by `details`, not `content`: `details` is rendered and persisted
  with the session but never sent to the model, while `content` is what the orchestrator
  reads — which is why the trail can be shown while `content` stays capped at 16 KB. The
  cap applies to single and tasks only; chain is exempt because `{previous}` is the
  handoff between agents. `details` holds the tool trail plus the child's last message
  (capped the same way), not every text block — the full transcript was tried and reverted
  because it duplicated the report in the session file without bound. The trail comes from
  `session.subscribe` on the child, and only boundaries count (tool start/end, finished
  messages), never `text_delta` — plus a 1 s tick while a child runs, so the clock keeps
  moving through a long LLM call or command. A panel that shows less than expected means
  the child's events stopped matching `ChildEvent`, not that it did nothing.
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
- `extensions/antz-subagent.ts` dispatches in-process: each agent is its own `AgentSession`,
  built with pi's SDK (`createAgentSession` + a `DefaultResourceLoader`), not a child
  `pi` process. That is why there is no CLI flag to keep in sync with `pi --help` — and
  why `tools:` and `model:` bite for real. The tool is named `antz_subagent`, so it does
  not collide with the `subagent` tool that third-party packages (including pi's own
  example) install globally. The tool is registered but starts inactive: only an `/antz`
  input activates it, so no other session sees it.
- The deactivation is gated on `.antz/` being gone, not on the run merely settling.
  Settling also happens when a clarify turn hands the conversation back to the user and
  when a run stops mid-way; either would lose the tool the repair loop needs. Failing
  open — a tool that lingers after a finished run — is the deliberate trade over failing
  closed, where an in-flight run cannot dispatch. Because of that, a session where antz
  stopped without PASS keeps the tool until the next `/antz` finishes cleanly.
- Children load the repo's skills and `AGENTS.md` but **no extensions**
  (`noExtensions: true`), so a subagent cannot recurse into `antz_subagent` and no
  other extension's side effects run inside one. A capability that exists only as an
  extension tool is therefore unavailable to subagents.
- Auth still bounds the pinned model: only `nan/*` models are usable in this environment
  (`~/.pi/agent/models.json` holds the only provider key), so anything else fails with
  "No API key found" until you `/login` that provider. A `model:` line that doesn't
  resolve fails that agent by name instead of falling back to the session's model.
- `tools:` in the agent frontmatter is enforced: the child gets exactly the tools it
  declares, and pi's default four when it declares none. Keep the declarations honest,
  because a declaration that contradicts the body bites immediately: antz-verifier's body
  writes `docs/decisions/`, so it declares `read, write, edit, bash`.
- `agents/` is not pi core: `extensions/antz-subagent.ts` is what discovers
  `~/.pi/agent/agents/*.md` (or `.pi/agents/*.md` in a host repo) and exposes the
  dispatch tool. With it missing, `/antz` has no antz-scout to run.
- `install.sh` creates its target directories with `mkdir -p` before copying for a reason:
  `~/.pi/agent/agents/` does not exist by default and `cp` into a missing target fails.
  The manual copy it replaced also chained the four `cp`s with `&&`, so the first failure
  meant the rest never ran; the script instead fails once, after copying, by listing what
  is missing — which is why its verification step, not the copy, is the thing that catches
  a tree that lost a file.
- The installer resolves the target the way the extension does — `--dir`, then
  `$PI_CODING_AGENT_DIR`, then `~/.pi/agent` — because `findAgentFile` reads `getAgentDir()`.
  Hard-coding `~/.pi/agent` would install everything correctly into the directory nothing
  is looking at.
- Installing writes only antz's own files: `prompts/antz.md`, `agents/antz-*.md`,
  `skills/antz-*` and `extensions/antz-subagent.ts`. The generic user-level
  `~/.pi/agent/skills/tdd/` is left alone — antz
  installs as `skills/antz-tdd/`, a separate skill on the same subject with narrower,
  seam-focused rules. Don't confuse the two, or point at the wrong one. A copy never
  removes anything, so a reinstall is an upgrade over what was there and nothing else in
  the agent dir is touched in either direction.
- The `model:` line in an agent file is the one thing a reinstall does not overwrite: the
  pin is read from the file before the copy and written back after it. That is why
  `install.sh` has `local_pins`/`restore_pins` at all, and it is the reason a copy is not
  a plain `cp`. The pin is whatever the file says, so an agent whose model changes
  upstream keeps the old value until the line is deleted and the installer run again —
  and there is no flag for that, because a flag is one more thing to document and the
  line is already editable by hand.
- This repo is the successor to the elaborate phase/partition/`antzspec/` flow in the
  sibling `../antz` repo. Do not port that machinery — partitions, fact gates, ledgers —
  back in; the simplification is the point.
