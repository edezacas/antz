# Orchestrator: design notes

This is a historical design record, not living documentation — it explains
*why* the `orchestrator` role and its supporting conventions
(`REJECTED.md`, `BLOCKED: <why>`, numbered sub-spec filenames, scenario-id
test tags) look the way they do. What they *are* and how to use them is
documented in `CLAUDE.md` (source of truth: `agents/prompts/orchestrator.prompt`
and the current code). This file won't be kept in sync with future changes
to that behavior — treat it as an explanation of the reasoning behind the
`1.0.0` design, not a spec.

## The core problem

`specifier`, `coder`, and `verifier` each start every invocation with an
empty context — no memory of prior turns, even within "the same" logical
task. An `orchestrator` that sequences them can't rely on remembering what
it already did either, because its own session can be interrupted and
resumed at any point with no warning. So its entire `Process` had to be
designed as a **stateless reconciliation routine**: every invocation
reconstructs the full picture from `spdd/` alone and takes the one next
action needed — no "first run" vs. "resume" branching, because there's no
way to reliably tell the difference.

That constraint forced a "can this be derived from something that already
exists?" pass over every piece of state the orchestrator needs:

| Question | Derived how |
|---|---|
| What change/slug is this? | Diff `spdd/changes/` before/after delegating a new request to `specifier`. |
| What order are sub-specs implemented in? | Numbered filenames (`01-`, `02-`, ...) — an earlier `ORDER.md` design was rejected as pure duplication of what the filename already encodes. |
| Is sub-spec N done, in progress, or not started? | Grep its scenario ids against `coder`'s unit-level test suite for presence (ids live in the test *name*, not a comment, since comments don't surface in runner output), then actually run the suite to resolve "something present" into red vs. green/skip. |
| Did `coder` refuse/escalate sub-spec N? | A `BLOCKED: <why>` skip reason — distinct from an ordinary "not unit-testable" skip. |
| Was this change approved and merged? | `spdd/changes/<slug>/` gone + `spdd/archive/<slug>/` present — `verifier`'s own archive step already moves the directory. |
| Was this change rejected before, how many times? | `REJECTED.md`'s entry count — the one piece of state that genuinely couldn't be derived from anything else, since a rejection leaves `spdd/changes/` untouched (indistinguishable from "never verified"). |

Net effect: the orchestrator never writes to `spdd/` at all. It only reads
and dispatches. Every artifact is owned by the role that naturally produces
it.

## Why `REJECTED.md` is append-only with a counted retry

An earlier design relayed a rejection's blockers to `coder` only within the
same session that observed the rejection. That breaks under interruption:
if the orchestrator's session dies between `verifier` writing the rejection
and the relay happening, a resumed run has no way to tell "rejected, not
yet relayed" from "rejected and relayed, now on the retry" — both look
identical from presence alone. Two fixes, both necessary:

1. **Content, not presence.** `verifier` appends a full numbered entry
   (blockers, severity, evidence, sub-spec attribution) instead of just
   touching a marker file. A resumed orchestrator reads the actual
   blockers from disk instead of trusting its own — or anyone's —
   conversational memory of what happened.
2. **Relay is unconditional and idempotent.** The orchestrator relays the
   latest entry's attributable blockers every time it sees one it hasn't
   followed with a `verifier` re-run yet, regardless of whether it looks
   like a prior session might already have done so. Relaying twice is
   free — `coder` just no-ops if there's nothing left to fix. The actual
   bound on retries is the **entry count**, read fresh from disk every
   time: 1 → relay + one retry; 2 → stop for good. Not a flag inferred
   from one session's memory, which is exactly the thing that doesn't
   survive interruption.

A blocker that doesn't trace to a single sub-spec (cross-feature
coherence, an e2e QA step) makes that one retry a **manual, user-invoked**
`verifier` pass instead of an orchestrated one — the orchestrator has no
`coder` session to relay it to, and burning the automatic retry on a
rejection that's certain to recur while the issue is unaddressed would
just waste it.

## Why `BLOCKED: <why>` uses a colon, not an em dash

Cheap insurance: a colon is a character an LLM asked to reformat or
summarize text is unlikely to silently drop or paraphrase away. An em dash
is exactly the kind of stylistic flourish a model might "clean up" in a
skip reason, which would quietly turn a blocked sub-spec into an ordinary
skip — and the orchestrator would then treat it as unit-testable-but-
skipped instead of stopping and asking the user to route it back to
`specifier`. The failure mode is self-correcting at worst (one wasted
`verifier` pass), but avoiding it costs nothing.

## Platform delegation scoping: verified, not assumed

Both target clients were checked against their actual current docs before
committing to a design, not assumed from memory:

- **Claude Code** (confirmed via `code.claude.com/docs/en/sub-agents.md`):
  a subagent's `tools:` list is a strict, enforced allowlist — the verified
  platform fact, which is why the old readonly denial was real. But the
  *parenthesized* form, `Agent(name1, name2, ...)`, which would scope *which* subagents a
  spawned agent can further spawn, only takes effect when the spawning
  agent runs as the main thread via `claude --agent`. `antz-orchestrator`
  is always invoked as a subagent itself (via `/antz` or auto-delegation),
  so that parenthesized list would render into the frontmatter but be
  silently unenforced at runtime — a false sense of least-privilege worse
  than an honest one. **Decision**: grant plain, unrestricted `Agent`, and
  rely on `orchestrator.prompt`'s "What you don't do" as a prompt-level
  (not tool-enforced) boundary. This is a known, accepted platform
  limitation, not a bug to fix later — `permissions.deny` in a user's own
  `settings.json` is the documented way to hard-block a specific agent
  name in Claude Code, but that lives outside any file `install.sh` owns.

- **OpenCode** (confirmed via `opencode.ai/docs/permissions/`,
  `/docs/agents/`, and `/docs/commands/`): subagent-to-subagent delegation
  is a recent, version-dependent feature — not safe to rely on. The
  stable path is a `mode: primary` agent invoking subagents via
  `permission.task`, which turned out to support more than a bare
  `allow`/`deny` string: a glob-pattern-keyed object, evaluated
  last-match-wins (`{"*": "deny", "antz-specifier": "allow", ...}`). That
  closes the gap Claude Code can't — OpenCode's scoping is genuinely
  runtime-enforced, not just documentation. Confirmed separately: an
  unset `subtask` on a command targeting a `mode: primary` agent runs it
  natively in the primary context rather than as a nested subagent (the
  docs describe `subtask`'s effect when set, not literally the unset
  case, so this was treated as implied rather than confirmed until
  checked against the actual behavior).

## Why `verifier` runs once per change, not once per sub-spec

Caught during design review, not obvious from the original three prompts:
`verifier`'s Merge & Archive step moves the *entire*
`spdd/changes/<slug>/` directory in one shot. An orchestrator invoking
`verifier` immediately after each individual `coder` sub-spec would have
had the *first* approval archive the whole change directory out from under
sub-specs not yet implemented. Fixed by restructuring the process:
implement every sub-spec first, then invoke `verifier` exactly once for
the whole change — which is also why `verifier`'s Input Rule needed a
"whole-change form" (verify every sub-spec with code present, don't stop
just because no single sub-spec was named).

## Validation

Beyond prompt review, the full design was exercised against a real,
installed `antz-orchestrator` (not a simulation) across an organic
end-to-end run plus five targeted disk-state fixtures covering: mid-change
resume, the `BLOCKED:` path, an attributable rejection's relay-and-retry,
the two-entry retry bound, and a non-attributable blocker's forced manual
pass. All six produced the behavior this document describes.
