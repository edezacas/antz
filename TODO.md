# TODO

Known gaps. Nothing here blocks a run; the flow works as documented in `README.md`.

## Client-agnostic prompt assembly

Everything antz ships is pi-only. `extensions/antz-subagent.ts` is the only way the
five agents get dispatched, and `agents/*.md` is that extension's own convention, not
a format anyone else reads. Concurrency is not the gap: every client's cap sits above
antz's 4, and the rule that actually carries the safety — never two tasks that touch
the same file — is already in `prompts/antz.md` and is harness-independent. The gap is
installation: no client has a portable subagent format, so a second harness needs its
own registration files.

The next idea is to let the client write them. `INSTALL.md` says "you are one of pi,
claude, opencode; read `adapters/<you>.md`", and each adapter is a short spec: paths,
the frontmatter field map, what to verify. Adding a client is then a `.md`, not code,
and `install.sh` stays where it is — it is pi's adapter and pi's bootstrap. It stays
deterministic by having the agent copy the agent bodies byte for byte and synthesize
only the frontmatter, then run the same check `install.sh` runs: the files exist,
`name:` matches the filename, the body is identical, a previous `model:` survived. It
is testable the way the rest is: `eval/install.sh`, a stubbed HOME in a scratch
directory, assert the tree and the byte-identity of the bodies.

Only the harnesses we actually use ship an adapter; the structure is the spec for the
next one. The agent still needs the spec in context before any of this, so there is a
clone and a prompt before the install.

Revisit only if a second harness is a real target.
