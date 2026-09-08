# Change: set-model-interactive-picker

## Goal
Today `/antz-set-model` requires exactly one of `--model <value>` / `--clear`;
omitting both is a usage error (scenario `set-model-cmd-09`, "neither" row) and
the user must type the model value blind — the embedded script writes it
verbatim without validation.

This change turns the no-flag form into an **interactive picker**: when
`--model` is omitted and `--clear` is not given, the invoking session asks the
USER which model to assign, using each client's native question mechanism, then
feeds the chosen value to the **same embedded POSIX script** as `--model`. The
explicit-flag forms keep working exactly as before — they are the preserved
non-interactive/scripted bypass.

## Agreed design decisions (user-resolved; specified here, not redesigned)
- **Client asymmetry for the option source:**
  - *Claude Code:* there is NO runtime/scriptable model enumeration. The option
    list is the documented alias vocabulary from
    `https://code.claude.com/docs/es/model-config`, embedded in the command
    body at install time: `best`, `fable`, `opus`, `sonnet`, `haiku`, plus the
    advanced `sonnet[1m]`, `opus[1m]`, `opusplan`. The list is refreshed by the
    normal re-run-`install.sh` release cadence, never queried at runtime.
  - *OpenCode:* the command body runs `opencode models` via the session's Bash
    tool to enumerate models at invocation time (output is `provider/model` ids
    like `anthropic/claude-opus-4-5`), filters/presents them, plus a free-form
    option and the same "clear" option.
- **Mechanism:** each client's native question tool — `AskUserQuestion` in the
  Claude Code main session; the `question` tool in the OpenCode session. The
  command continues to NEVER delegate to any `antz-*` subagent; the question is
  asked in the invoking session.
- **Ordering:** argument validation, agent-installed check, and
  `antz:generated` marker check all happen BEFORE any question is asked (fail
  fast: no file written, no question shown for a doomed request). The existing
  refusal outcomes (`set-model-cmd-06`, `-07`, `-08`) are unchanged; only their
  sequencing relative to the interactive flow is specified here.
- **Embedded script unchanged in behavior:** it still accepts
  `--agent <role>` with exactly one of `--model <value> | --clear`, and writes
  verbatim with no validation. Interactive selection is only a new way to
  PRODUCE the `--model` value. Therefore `set-model-cmd-01..05`, `-10`, `-11`,
  `-12` outcomes hold unchanged.
- **Behavior change:** `set-model-cmd-09` changes. "Neither `--model` nor
  `--clear` given" is no longer a usage error at command level — it is the
  interactive picker. A usage error now occurs only for: unknown agent name,
  `--agent` missing, both `--model` and `--clear` given, unknown/malformed
  options. When `--model` IS given (or `--clear`), no question is asked and the
  output message is unchanged.
- **Current-model indication:** the picker indicates which option corresponds
  to the currently configured model (if any), read from the installed file's
  frontmatter before asking.

## Resolved specifier decisions (delegated by the user; rationale documented)
1. **Advanced aliases (`sonnet[1m]`, `opus[1m]`, `opusplan`) are free-form-
   reachable, not explicit question options on Claude Code.** Rationale:
   Claude Code's `AskUserQuestion` schema hard-caps explicit options at 4 per
   question and auto-provides a free-text row ("Other") on every question, so
   an explicit "type another value" option must not spend a slot; after the
   mandated clear option, only 3 alias slots remain, and the three stable
   family aliases (`sonnet`, `opus`, `haiku`) are the highest-value explicit
   options. `best`/`fable`/the advanced aliases are named verbatim in the
   question text so free-form entry of them carries no typo risk. All 8
   aliases remain embedded in the command body (the install-time vocabulary
   contract), so if the platform cap is ever lifted the full list can become
   options without another spec change. The free-form escape hatch already
   covers list staleness.
2. **Claude Code explicit option set (one question): `sonnet`, `opus`,
   `haiku`, and the revert-to-default (clear) option, in that order.** Same
   4-slot rationale as above; the clear option is mandated by the agreed
   design, which leaves exactly 3 alias slots.
3. **Dismissed or empty answers cancel the operation** — the script is never
   invoked, nothing is written, and the reply states nothing was changed.
   (Writing without an answer is never acceptable; an empty value would also
   produce a malformed `model: ` line.)
4. **The `argument-hint` becomes `--agent <specifier|coder|verifier|orchestrator> [--model <value>|--clear]`**
   (optional group in brackets) — the no-flag form is now a first-class
   interactive mode, not a missing-argument error.
5. **The literal value `default` gets no dedicated picker option.** The
   "revert to default (clear)" option maps to the script's `--clear` (line
   removal), which is the revert-to-default affordance; writing `model:
   default` literally remains possible only via free-form input. Two paths to
   the same outcome would be redundant.

## Sub-specs, in dependency order
1. `01-interactive-picker.feature` — the entire feature: the updated command
   body `install.sh` renders for each client (argument validation and fail-fast
   ordering, the interactive flow, and each client's option source and question
   mechanism), with separate scenario groups where the two clients genuinely
   differ. The embedded POSIX script (`set_model_script`) is NOT re-specced —
   it is unchanged; only its command-level packaging changes.

There is no further layer split: this is one artifact (the rendered command
body) parameterized by client, exactly as `set-model-native-command` was one
sub-spec. The two clients differ in option source and question mechanism, so
those differences are separate scenario groups inside the one file rather than
separate sub-specs — no group is independently implementable without the shared
validation/ordering contract.

## Shared contracts

**Client binding (unchanged)** — each installed copy of `/antz-set-model` is
permanently scoped to the client it was installed for (Claude Code:
`~/.claude/agents/antz-<agent>.md`, `model:` after `description:` before
`tools:`; OpenCode: `~/.config/opencode/agents/antz-<agent>.md`, `model:` after
`description:` before `mode:`). The invoker never supplies a client flag.

**Command argument contract (MODIFIED)**
```
 /antz-set-model --agent <specifier|coder|verifier|orchestrator> [--model <value>|--clear]
```
- `--agent` is required and must name one of the four role agents (unchanged).
- `--model` and `--clear` are mutually exclusive; **at most one** may be given
  (was: exactly one).
- **Neither given → interactive picker** (was: usage error). The picker still
  requires a syntactically valid `--agent` and a passing file pre-flight; see
  Ordering below.
- Usage errors (no question asked, no file written): unknown agent name;
  `--agent` missing; `--agent` or `--model` given without a value; both
  `--model` and `--clear`; unknown options.

**Embedded script contract (unchanged)** — the script embedded in the command
body still requires exactly one of `--model <value>` / `--clear` whenever it is
invoked (its "neither" usage error remains as a backstop, e.g. if someone runs
the extracted temp file directly). The command body never invokes the script
without exactly one of the two: `--model <chosen|given>` or `--clear`. The
script remains the sole authority for the actual file edit and its printed
output is the reply, relayed verbatim.

**Model value contract (extended source, same rule)** — the value written is
the exact `--model` value, **verbatim**, never validated or translated. This
now applies equally to a value that came from the picker (a listed alias, an
enumerated `provider/model` id, or a free-form answer). An empty or
whitespace-only picker answer never reaches the script (it cancels instead).

**Picker contract** — the question is asked in the invoking session via that
client's native question tool; the command never delegates to any `antz-*`
subagent. Before asking, the session runs a pre-flight (see Ordering) that also
reads the target file's current frontmatter `model:` line. The question text
always states the current state (the configured value, or that none is
configured); when the current value exactly equals an offered option's value
string, that option is marked as the current one; otherwise no option is
marked. A "revert to default (clear)" option is always offered and maps to the
script's `--clear`. A free-form "type another value" affordance is always
available (explicit option on OpenCode; the tool's built-in free-text row on
Claude Code). Dismissing the question, or answering with an empty value,
cancels: no script invocation, no file written, reply states nothing changed.

**Ordering (fail-fast) contract** — for any invocation, before any question is
asked the invoking session must have: (1) validated the arguments per the
argument contract, (2) confirmed the target file exists and carries the
`antz:generated` marker, (3) read the current frontmatter `model:` line. A
doomed request is refused with the same observable outcome as today
(`set-model-cmd-06/07/08` outcomes) and no question is shown. The script
re-validates everything at write time and remains the authority; the pre-flight
is only a gate so the user is never asked about a request that cannot succeed.

**Option-source asymmetry** — Claude Code: the alias vocabulary
(`best`, `fable`, `opus`, `sonnet`, `haiku`, `sonnet[1m]`, `opus[1m]`,
`opusplan`, per `https://code.claude.com/docs/es/model-config`) is embedded in
the command body at install time and refreshed only by re-running
`install.sh`; nothing is queried at runtime. OpenCode: models are enumerated at
invocation time via `opencode models` run through the session's Bash tool; no
catalog is embedded. Presentation/filtering of the OpenCode catalog (grouping,
prioritizing, trimming a large list) is a prompt-level instruction to the
session, not a hard rule the script enforces — but the free-form affordance and
the clear option must always remain offered so no value is unreachable.

## Invariants
- The embedded POSIX script in the rendered command body is unchanged in
  behavior (and byte-for-byte unchanged in `install.sh`'s
  `set_model_script`): exactly one of `--model`/`--clear` when invoked,
  verbatim write, no validation. `set-model-cmd-01..05`, `-10`, `-11`, `-12`
  outcomes hold unchanged, and the existing unit tests for them (including
  both `set-model-cmd-09` script-level rows) pass untouched.
- Only the `model:` line (added, replaced, or removed) may differ before and
  after; the marker/version comment, the rest of the frontmatter, and the body
  are byte-for-byte preserved (existing invariant, restated).
- The command never delegates to any `antz-*` subagent, before or after
  asking; the question is asked in the invoking session. (On Claude Code,
  `AskUserQuestion` is a main-session tool and is unavailable to subagents —
  consistent with this invariant.)
- No question is ever asked for a request that has already failed validation
  or pre-flight; no refusal ever writes a file.
- No persistence of the chosen model anywhere except the agent file's
  `model:` line; no new runtime dependencies beyond what each client already
  has (its native question tool and its Bash tool).
- No validation of the final written value beyond "it came from the user" —
  the verbatim-value contract covers picker-sourced values too.
- Installing the updated command reuses `install.sh`'s existing
  `MARKER`/`install_file` overwrite/backup convention; no new mechanism.
- The Claude Code alias vocabulary embedded at install time can go stale
  between releases; the free-form affordance is the designed escape hatch
  (acknowledged caveat, not solved here). A chosen model may still be
  unavailable for the user's account/plan: Claude Code degrades softly
  (subagent frontmatter override falls back to the inherited model with a
  warning); OpenCode fails at spawn. Both are outside this command's control.
- **Versioning:** per `AGENTS.md`, a `VERSION`/`CHANGELOG.md` bump is
  **required only** for changes to `agents/prompts/` or `agents/meta/`. This
  change touches `install.sh` (the command-body rendering), the rendered
  command files, tests, and docs — none of those directories — so **no bump is
  required**. `install.sh --check`'s version-drift report stays keyed off the
  specifier agent file only, and re-running `install.sh` overwrites the
  antz-managed command files in place regardless of version, so users receive
  the new body on any re-install. (Precedent note: the `set-model-native-
  command` change did bump to 1.2.0 for an install.sh-only change, presumably
  to surface its changelog entry via `--check`; whether to make a courtesy
  minor bump here is the maintainer's call, not a policy requirement.)

## Out of scope
- Any change to `agents/prompts/*.prompt` or `agents/meta/*.yaml`, or to the
  four role agents' behavior.
- Any change to the embedded script's behavior, including new flags or a
  read-only/check mode.
- Validation of the final written value beyond "it came from the user"
  (including availability checks against the user's account/plan).
- Persistence of the chosen model anywhere except the agent file's `model:`
  line (no config files, no cache, no cross-session memory).
- Solving the acknowledged platform caveats: a chosen model being unavailable
  for the account/plan; the embedded Claude Code alias list going stale;
  OpenCode's `opencode models` catalog being large (presentation guidance is
  prompt-level only).
- An explicit "keep current / cancel" picker option (dismissal already
  cancels; inventing a second cancel path is unnecessary).
- Gracefully handling an invoking session/agent/mode that lacks the question
  tool or edit capability — the failure is whatever the client's own
  tool-permission error surfaces.
- A `--all`-style affordance applying one value to both clients (each copy
  stays scoped to one client by construction).
- Making a configured model survive a later `install.sh` run (still
  unsupported, unchanged).

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/install.sh` — `render_set_model_command`
  (the command-body template: intro, relay rule, and the new pre-flight/picker
  instructions, per client) and the client-specific strings it composes
  (`short_desc`, `intro`, `extra_frontmatter`). `set_model_script` (the
  embedded POSIX script) must NOT change. The Claude Code copy's body gains the
  embedded alias vocabulary + `AskUserQuestion` instructions; the OpenCode
  copy's body gains the `opencode models` enumeration + `question`-tool
  instructions.
- `/home/edezacas/Projects/edezacas/antz/tests/set-model-command_test.sh` —
  update the exact `argument-hint` assertion in `test_command_install_01` to
  the new hint string; add tests for `picker-render-01..05` (rendered-body
  content assertions, same extraction/grep style as the existing suite). Every
  existing test keeps passing unchanged (the script is untouched, including
  both `set-model-cmd-09` rows).
- `~/.claude/commands/antz-set-model.md` and
  `~/.config/opencode/commands/antz-set-model.md` — installed copies, reference
  only (rendered output of the above).
- `/home/edezacas/Projects/edezacas/antz/spdd/specs/set-model.md` — the domain
  spec this change modifies; see the mapping table at the end of
  `01-interactive-picker.feature` for exactly what the verifier merges
  (principally `set-model-cmd-09`, `command-install-01`, the argument
  contract, and the now-invalidated out-of-scope bullet).

## Verification levels
- Unit-testable (coder's suite): `command-install-01` (modified),
  `picker-render-01..05`, and the script-level rows of the modified
  `set-model-cmd-09` (existing tests stand).
- End-to-end only (verifier, live sessions): the command-level interactive
  behaviors — `picker-cmd-01..13`, `picker-claude-*`, `picker-opencode-*` —
  because question-asking is observable only in a real client session; see
  `e2e-qa.feature`.
