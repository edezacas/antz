# Orchestrator

Supplementary detail for the `orchestrator` prompt. The prompt states the
flow; this file holds the reasoning behind two choices that are easy to
"fix" into something worse.

## Two modes, one flow

The orchestrator picks the cheapest mode that fits the request, once, before
delegating anything.

| mode | when | sessions |
|---|---|---|
| `direct` (default) | a bounded change to behavior that already exists and is understood | coder, then verifier |
| `spec` | an externally visible contract is introduced or changed, the request spans more than one layer, or its own text does not pin down the behavior | specifier, then one coder per sub-spec, then verifier |

`direct` exists because the spec pipeline is priced like insurance against
ambiguity: worth it for a cross-cutting change, pure overhead for a three-line
one. When in doubt the orchestrator starts `direct`, and the coder escalates
with `ESCALATE: <why>` if the work turns out larger than one session — one
cheap signal instead of a mode guess made from a vague request.

`direct` writes no `spdd/changes/<slug>/` and no Gherkin. The request text is
the acceptance basis the verifier walks against the working tree's diff.
Merging into `spdd/specs/` and archiving do not apply: there is nothing to
merge.

## Why there is no probe and no receipts

Earlier versions had the coder write a `NN-<feature>.result` receipt and a
probe script classify each sub-spec from it (`covered=n/N`, `complete=yes`,
`class=done|blocked|in_progress`), so the orchestrator would never re-run a
test suite between steps. The saving was seconds — one suite run — while the
cost was a grammar, a sentinel, a doubtful-receipt path, a classification
table, and a mirrored closing block nothing ever read.

The flow now reconstructs state by reading three things straight from the
working tree, at no protocol cost:

- `spdd/changes/<slug>/OPEN_QUESTIONS.md` — stop, the human resolves it;
- `spdd/changes/<slug>/REJECTED.md` — count `## Rejection <n>` headings, the
  retry bound (1 = relay and retry once, 2 = stop for good);
- the tests already on disk — the coder greps its scenario ids and treats a
  sub-spec with passing tests as a no-op, so a re-invocation is idempotent by
  construction rather than by classification.

Reading the disk stays mandatory: a role's conversational claim is never the
input to a routing decision.

## Delegation contract

Every delegation carries the same two-line check-in first:

```
Working root: <repo root absolute path>
Change slug: <slug>
```

plus, in `spec` mode, `Sub-spec: <file>` or `Mode: direct`. Nothing else —
in particular, never a skills list: each role discovers and activates its own
skills from its session. The shell's cwd can reset between Bash calls on some
clients, so the roles re-`cd` to the working root before any `spdd/...`
relative path.

## Git

`sh "<libdir>/antz-flow.sh" start <slug>` is the only mutating git command in
the whole flow, and it does one thing: create and check out the marker branch
`antz/<slug>`. No worktrees, no commits, no merges, no deletes. Read-only git
(`rev-parse`, `status`, `branch --list`, `diff`) is fine anywhere. Committing,
merging, and deleting the branch are the human's follow-ups, printed at the
end of every run and never executed by the flow.
