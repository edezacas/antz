# Adapter: Claude Code

User scope, so it works in every repo.

| antz source | Target |
|---|---|
| `agents/<name>.md` | `~/.claude/agents/<name>.md` |
| `skills/<name>/` | `~/.claude/skills/<name>/` |
| `prompts/antz.md` | `~/.claude/commands/antz.md` |
| `extensions/antz-subagent.ts` | skip — `Task` replaces it |

## Frontmatter, per agent

Drop the frontmatter in `agents/<name>.md` and paste the block below in its place.
Keep the body exactly as it comes.

```yaml
# ~/.claude/agents/antz-scout.md
---
name: antz-scout
description: Scans the repo before antz asks the user anything.
tools: Read, Grep, Glob, Write, Bash
---
```

```yaml
# ~/.claude/agents/antz-planner.md
---
name: antz-planner
description: Breaks a closed spec into small, self-contained tasks.
tools: Read, Write, Grep, Glob
---
```

```yaml
# ~/.claude/agents/antz-tester.md
---
name: antz-tester
description: Writes the failing test for one task. Red, not green.
tools: Read, Write, Edit, Bash
skills: antz-tdd, antz-architecture
---
```

```yaml
# ~/.claude/agents/antz-implementer.md
---
name: antz-implementer
description: Makes one failing test pass. Nothing more.
tools: Read, Write, Edit, Bash
skills: antz-tdd, antz-architecture
---
```

```yaml
# ~/.claude/agents/antz-verifier.md
---
name: antz-verifier
description: Runs once per round, after every task is green. Checks the feature against the spec, not just that the tests pass.
tools: Read, Write, Edit, Bash
skills: antz-architecture
---
```

Rules for the blocks above:

- `name:` must match the filename.
- The tool map is `read→Read`, `write→Write`, `edit→Edit`, `bash→Bash`,
  `grep→Grep`, `find→Glob`; `ls` drops.
- Keep `Skill` out of `tools:`. `skills: antz-tdd, antz-architecture` on the tester
  and the implementer, and `antz-architecture` on the verifier, is how those three
  get the skills; the scout and the planner need none.
- No `model:` line, so the agent inherits the session. To pin one, add
  `model: sonnet` (or `opus`, `haiku`, a model id) — the verifier should be a
  different family from the implementer.
- Don't set `disable-model-invocation: true` on `antz-tdd` or `antz-architecture`:
  it cancels the preload.

The command file installs as it comes. Claude Code reads `description:` and
`argument-hint:`, takes the command name from the filename, and runs `$ARGUMENTS`
the same way. The three skills install untouched.

## Dispatch

The prompt names no tool: one agent is one `Task` call, a chain is two `Task`
calls in that order with the tester's report in the second, and independent tasks
are one `Task` call each in one message, max 4 at a time. Keep the rule at the
end of step 4: never two tasks in flight that would touch the same files.

## Differences from pi

- `Task` is always available, so any session can call antz-scout, not only a
  `/antz` run.
- No 16 KB cap on what a subagent returns, no chain handoff substitution, no live
  panel.

## Verify

```sh
# Everything after the second `---`, whatever the frontmatter grew to.
body() { awk 'n<2 && /^---$/ {n++; next} n>=2' "$1"; }

for n in antz-scout antz-planner antz-tester antz-implementer antz-verifier; do
  f=~/.claude/agents/$n.md
  test -f "$f" || echo "missing $n"
  test "$(basename "$f" .md)" = "$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1)" || echo "name mismatch $n"
  body "$f" | diff -q - <(body agents/$n.md) || echo "body differs $n"
done

cmp -s prompts/antz.md ~/.claude/commands/antz.md || echo "command file differs"
```

Then check in Claude Code that the five agents are listed, `/antz` exists, and a
trivial repo gets `.antz/00-recon.md`.
