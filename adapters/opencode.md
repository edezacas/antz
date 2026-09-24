# Adapter: OpenCode

User scope, so it works in every repo.

| antz source | Target |
|---|---|
| `agents/<name>.md` | `~/.config/opencode/agents/<name>.md` |
| `skills/<name>/` | `~/.config/opencode/skills/<name>/` |
| `prompts/antz.md` | `~/.config/opencode/commands/antz.md` |
| `extensions/antz-subagent.ts` | skip — `task` replaces it |

Use the plural directories (`agents/`, `skills/`, `commands/`).

## Frontmatter, per agent

Drop the frontmatter in `agents/<name>.md` and paste the block below in its place.
Keep the body exactly as it comes.

```yaml
# ~/.config/opencode/agents/antz-scout.md
---
description: Scans the repo before antz asks the user anything.
mode: subagent
permission:
  edit: allow
  bash: allow
  task: deny
  question: deny
---
```

```yaml
# ~/.config/opencode/agents/antz-planner.md
---
description: Breaks a closed spec into small, self-contained tasks.
mode: subagent
permission:
  edit: allow
  bash: deny
  task: deny
  question: deny
---
```

```yaml
# ~/.config/opencode/agents/antz-tester.md
---
description: Writes the failing test for one task. Red, not green.
mode: subagent
permission:
  edit: allow
  bash: allow
  skill: allow
  task: deny
  question: deny
---
```

```yaml
# ~/.config/opencode/agents/antz-implementer.md
---
description: Makes one failing test pass. Nothing more.
mode: subagent
permission:
  edit: allow
  bash: allow
  skill: allow
  task: deny
  question: deny
---
```

```yaml
# ~/.config/opencode/agents/antz-verifier.md
---
description: Runs once per round, after every task is green. Checks the feature against the spec, not just that the tests pass.
mode: subagent
permission:
  edit: allow
  bash: allow
  skill: allow
  task: deny
  question: deny
---
```

Rules for the blocks above:

- There is no `name:` key: the filename is the agent name.
- `mode: subagent` is required.
- `edit` covers `write`, `edit` and `apply_patch`.
- `task: deny` on all five — a child never dispatches. `question: deny` — only the
  session asks the user. `bash: deny` only on the planner. `skill: allow` on the
  tester, the implementer and the verifier.
- Anything not listed keeps OpenCode's permissive default.
- If your version rejects `bash:`, write `shell:` instead.
- No `model:` line, so the agent inherits the session. To pin one, add
  `provider/model` — thinking is a variant, e.g. `anthropic/claude-sonnet-4-5#high`.
  The verifier should be a different family from the implementer.

The command file keeps `description:` and drops `argument-hint:`, which OpenCode
does not read; the name comes from the filename and `$ARGUMENTS` works the same.
The three skills install untouched.

## Dispatch

The prompt names no tool: one agent is one `task` call, a chain is two `task`
calls in that order with the tester's report in the second, and independent tasks
are one `task` call each in one message, max 4 at a time. Keep the rule at the
end of step 4: never two tasks in flight that would touch the same files.

## Differences from pi

- `task` is always available, so any session can call antz-scout, not only a
  `/antz` run.
- No 16 KB cap on what a subagent returns, no chain handoff substitution, no live
  panel.

## If a run stalls

A subagent waiting on approval hangs with no output. Check `external_directory`
and `doom_loop` — both default to `ask`. `opencode --auto` approves everything not
explicitly denied for the session. On versions where a subagent's own permission
rules are ignored, put the `allow`s in `opencode.json` instead.

## Verify

```sh
# Everything after the second `---`, whatever the frontmatter grew to.
body() { awk 'n<2 && /^---$/ {n++; next} n>=2' "$1"; }

for n in antz-scout antz-planner antz-tester antz-implementer antz-verifier; do
  f=~/.config/opencode/agents/$n.md
  test -f "$f" || echo "missing $n"
  grep -q '^mode:[[:space:]]*subagent' "$f" || echo "not a subagent: $n"
  grep -q '^  task: deny' "$f" || echo "missing task: deny on $n"
  body "$f" | diff -q - <(body agents/$n.md) || echo "body differs $n"
done

body ~/.config/opencode/commands/antz.md | diff -q - <(body prompts/antz.md) || echo "command body differs"
```

Then check in OpenCode that the five agents are listed as subagents, `/antz`
exists, and a trivial repo gets `.antz/00-recon.md`.
