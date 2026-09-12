# Domain: flow-branch

The orchestrator's embedded `antz-flow.sh` (the flow's git plumbing) and the
orchestrator prompt's prose that consumes it, plus the policy-doc surface of
the flow contract. Merged from change `flow-branch-checkout` (all scenarios
ADD; no prior domain spec existed). Behavior level `4.0`; VERSION 4.0.0.

## Feature: ensure (from 01-ensure.feature)

### ADD ensure-01
Given a git repository with at least one commit, the session on branch "master", and no "antz/<slug>" branch
When the flow script runs "ensure <slug>"
Then stdout is exactly "state=created" with exit status 0
And the session is now on branch "antz/<slug>"
And "refs/heads/antz/<slug>" points at the same commit HEAD pointed at before the call
And no new commit exists anywhere in the repository

### ADD ensure-02
Uncommitted working-tree work survives the positioning: on the fresh path, the
dirty files carry over rather than being destroyed or stashed ("state=created",
byte-identical contents, change still uncommitted, no stash entry).

### ADD ensure-03
The resume path reports "state=reused", positions the session onto the existing
branch, and never rewrites the branch ref (no -B semantics).

### ADD ensure-04
Re-running ensure while already positioned is a safe no-op: "state=reused",
HEAD and every branch ref unchanged, working tree untouched.

### ADD ensure-05
When git refuses the positioning (a destructive-checkout conflict), the script
prints exactly "state=checkout_refused" with exit status 1; the working tree,
HEAD position, and every branch ref are identical before and after; nothing was
forced, stashed, reset, or deleted.

### ADD ensure-06
Static backstop: no git invocation carries "-B", "--force", or "-f"; no
"git reset", "git clean", "git stash", "git restore", or "git branch" with
"-d"/"-D"; "git branch" appears only flaglessly to create the marker branch and
the positioning only as a plain flagless switch.

### ADD ensure-07
No subcommand ever commits: HEAD's commit count and every branch ref hold
steady across discover/ensure/state/release (refused and successful).

### ADD ensure-08 (outline)
Preflight fail-close, every subcommand:
| environment | subcommand | machine-line |
|---|---|---|
| git absent from PATH | discover | state=no_git (exit 1) |
| git absent from PATH | ensure <slug> | state=no_git (exit 1) |
| not a git repo | discover | state=no_repo (exit 1) |
| not a git repo | ensure <slug> | state=no_repo (exit 1) |

### ADD ensure-09
Unborn repo: "ensure <slug>" prints "state=no_commits" (exit 1); no branch
created, no positioning attempted.

### ADD ensure-10
A failed branch-creation attempt (branch still absent) fail-closes with
"state=no_branch" (exit 1) — never a success state, never a false "reused". A
concurrent-race create re-checks and proceeds through the resume positioning.

### ADD ensure-11 (outline)
Release gates, unchanged, nothing changed on disk:
| fixture | reason |
|---|---|
| marker branch exists, "spdd/archive/<slug>" absent | archive-missing |
| marker branch, archive present, "spdd/changes/<slug>" present | change-still-present |
| archive present, no marker branch | branch-missing |

### ADD ensure-12
Successful release prints exactly "released branch=antz/<slug>" (exit 0),
removes nothing (branch and archive survive), and prints no command suggestions.

### ADD ensure-13
Discover is unchanged: empty when no "antz/*" branches and no change dirs; one
"candidate=branch slug=…" and one "candidate=on-disk slug=…" line when both exist.

### ADD ensure-14
State is unchanged: verifies the marker branch, resolves the repo root, runs
the probe verbatim with CHANGE_DIR at the working tree's "spdd/changes/<slug>";
"branch=missing" (exit 1) when the marker branch is absent.

### Invariants
- Stdout is exactly one machine line per invocation (discover: one "candidate="
  line per match, possibly none); one-line vocabulary: `state=created` (0),
  `state=reused` (0), `state=no_commits` (1), `state=checkout_refused` (1),
  `state=no_branch` (1), `state=no_git`/`state=no_repo` (1),
  `branch=missing` (1), `gate=refused reason=…` (1),
  `released branch=antz/<slug>` (0).
- No subcommand ever commits; the marker branch points at the commit the flow
  started from forever.
- No destructive git ever (-B/--force/-f, reset, clean, stash, restore,
  branch -d/-D); the one checkout ensure performs is refused, not forced, when
  it would destroy uncommitted work.
- Success states imply positioned: "state=created"/"state=reused" are printed
  only once the session sits on "antz/<slug>".
- "state=reused" is never printed when the branch does not exist.
- ~~The script stays the prompt's first 3-space-indented bare fence (the probe is
  its "```sh" fence); both test files extract it mechanically.~~
  **Superseded** by change `orchestrator-fast-path` (scriptsource-01..03,
  testharness-01..02): the flow script and the probe now live as source files
  `scripts/orchestration/antz-flow.sh` and `scripts/orchestration/antz-probe.sh`
  (byte-equal dedents of the former fenced snippets), the prompt's three script
  fences carry one `# antz-include: scripts/orchestration/<name>.sh` marker line
  each, `install.sh` injects the file content at render time (renderinject-01..05
  below), and the test suites read the files directly instead of extracting from
  the prompt. The runtime contract is unchanged (temp file + `sh <tempfile> ...`,
  nothing installed standalone).

## Feature: orchestrator (from 02-orchestrator.feature)

### ADD orchestrator-01
Step 1's ensure instructions document "state=created"/"state=reused" as having
positioned the session on "antz/<slug>" (work uncommitted on that branch),
document the "state=checkout_refused" stop (git refused the positioning because
it would overwrite uncommitted changes; user resolves themselves and
re-invokes; never forced) and the "state=no_branch" stop the same way, and
"state=no_commits" keeps its meaning.

### ADD orchestrator-02
Step 5's human follow-up print states the finished work sits uncommitted on
"antz/<slug>" (seen via git status); committing is the user's own whenever/how
decision; merging the user's own whether/where decision with a placeholder
target (`git switch <integration> && git merge antz/<slug>`); branch deletion
the user's own optional cleanup; the orchestrator never runs them.

### ADD orchestrator-03
No concrete integration branch name appears anywhere in the prompt as a merge
target; every example names only "antz/<slug>" or a placeholder.

### ADD orchestrator-04
The law wording: the branch is created AND checked out by ensure
(re-positioned onto on resume), a marker of the flow's base commit, with the
work uncommitted in the main checkout's working tree; the destruction law reads
no "-B", no "--force", no resets, no merges, no branch deletes, and never a
forced or overwriting checkout; "no role ever commits anything" stated in both
the law list and the owns section; the "## What you don't do" bullet confines
the orchestrator to the four subcommands with no ad-hoc git.

### ADD orchestrator-05
Everything else in the prompt is unchanged: the discover and state-output
tables, step 3 classification, step 4 rejection routing, the release-output
table's four machine lines, the Report Format; no new subcommand, probe, or
process step.

## Feature: orchestrator — flow routing and stop vocabulary (from 01-flow.feature, change `fix-orchestrator-flow`)

The orchestrator routes a never-specified flow to the specifier, detects
verifier outcomes from disk, and defines its stop vocabulary. Plan items
1.1–1.3, 1.5. No script changes; `scripts/orchestration/antz-flow.sh` and
`scripts/orchestration/antz-probe.sh` are byte-unchanged.

### ADD flow-01
After `ensure`, a never-specified flow delegates the whole change to the
specifier, then re-probes and continues through the unchanged state machine:
when neither `spdd/changes/<slug>/` nor `spdd/archive/<slug>/` exists, the
flow was never specified (covers both a `state=created` flow and the
branch-only `state=reused` candidate that never wrote anything). The
orchestrator delegates the whole change to the `specifier` (which creates the
change dir by authoring the sub-specs), carrying the standard delegation
message — the `Working root` and `Change slug` lines plus the `## Skills to
load before work` block — then re-probes (re-runs step 2's `state`
subcommand) and continues through the unchanged state machine from its fresh
output. The Report Format's `delegated-specifier` status is produced by this
step: the closing block of an invocation that stopped here reads
`status=delegated-specifier`. The specifier is delegated at most once per
invocation.

### ADD flow-02
`change_dir=missing` with an on-disk candidate at discover time means the
change dir was deleted mid-session — a hard stop: when this invocation's
`discover` listed an on-disk candidate for this slug (the change dir existed
when the flow resumed) and the verifier has not been delegated in this
invocation, the flow stops and asks the user instead of delegating the
specifier. The stop is a hard state stop, reported as such in the closing
block (`status=stopped`), with the latch applying: no further delegation of
any kind, resumption only as a fresh invocation.

### ADD flow-03
After a verifier delegation, `change_dir=missing` never re-triggers the
specifier rule — step 5's disk-based outcome detection routes it instead: a
`change_dir=missing` outcome observed after this invocation has delegated the
`verifier` does not apply the never-specified rule and does not delegate the
specifier.

### ADD flow-04
Step 5 detects the verifier's approval from disk — re-probe plus the release
gate — never from the verifier's report: the orchestrator re-probes (the
step-2 probe; read-only probing is always allowed) and routes on the fresh
output. When the probe reports `change_dir=missing` (the verifier's archive
step moved the change dir), the orchestrator runs `sh <tempfile> release
<slug>` and routes on its line: a green `released branch=antz/<slug>` means
the change is approved — approved-with-warnings included, since its archive
move is identical on disk — and the flow is done, printing the existing human
follow-up print unchanged. A `gate=refused reason=archive-missing` line is
an anomalous state (the change dir is gone but no archive exists): stop and
report. Any other `gate=refused reason=...` line stops per the release table.
The release-output table and the human follow-up print keep their exact
pinned content.

### ADD flow-05
A fresh rejection is detected from a new `REJECTED.md` entry; any other
post-verifier state fail-closes: when the re-probe shows the change dir still
present, the orchestrator compares `rejected_count` with the value it read
from disk before that verifier delegation — disk reads on both sides; nothing
is taken from the verifier's report. A greater count is a fresh rejection and
routes to step 6 (loop back to step 2, which picks the freshly written entry
up on the next pass). Any other state — the change dir present with no new
rejection — is an anomalous state (the verifier neither archived nor
rejected): stop fail-closed and report.

### ADD flow-06
The dedup guard enumerates exactly two exceptions — the step-4 coder relay
and the step-4 single verifier retry: the never-twice rule stays ("the same
(sub-spec, role) pair is never delegated twice" within one invocation, routing
instead by the existing state machine), and the bullet enumerates exactly two
exceptions, both step 4's: relaying each attributable blocker to the `coder`
session for the sub-spec it names (at most one relay per pair per entry; a
second entry stops the flow for good), and the one bounded whole-change
`verifier` retry when a rejected entry holds only attributable blockers
(bounded by `REJECTED.md`: the count reaching 2 stops the flow for good). No
third exception exists: the specifier is never re-delegated within an
invocation, and a `change_dir=missing` outcome persisting after the specifier
delegation stops the session rather than re-delegating.

### ADD flow-07
`waiting-user` is defined — the stop variant that hands a decision to the
user — and the latch applies identically to both variants: `waiting-user` is
the stop variant whose stop hands a decision to the user, produced by exactly
these stops: an `open_questions=yes` outcome; a slug-ambiguity stop (no
unambiguous on-disk candidate, or a semantically unclear continuation of an
already-claimed slug); and a receipt-doubt stop (the doubtful-receipt path
that can neither be settled from the receipt's id lines nor by a suite run,
and asks the user once). `stopped` is defined as the hard state stop — every
other stop-and-report outcome. The latch applies identically to both variants:
a `waiting-user` stop ends the session's delegation exactly like a `stopped`
one; `waiting-user` changes only the closing block's status value, never stop
behavior. The vocabulary itself is unchanged — the same six status values stay
pinned — and the tests and docs that name the vocabulary stay valid without
edits (the definition lives in the prompt).

### ADD flow-08
Every other stop reports `status=stopped` — the hard state stops are
enumerated, so the classification is closed: the stops reported as
`status=stopped` include at least: the flow script's machine-line stops
(`state=no_git`, `state=no_repo`, `state=no_commits`,
`state=checkout_refused`, `state=no_branch`), `branch=missing`, the
mid-session change-dir deletion stop, the post-verifier fail-closed stop, any
`gate=refused reason=...` line, a `BLOCKED:`-reasoned sub-spec found in
classification (stop at the first one found, relay its reason),
`rejected_count=2`, a non-attributable blocker in a rejected entry, and the
empty-ids stop-and-ask. Each of those stops still names the resume action in
the report body; `stopped` versus `waiting-user` changes only the closing
status value.

### ADD flow-09
The unchanged surface stays unchanged — the probe keeps `change_dir=missing`
as an output, the tables and fences survive, the steps still end at 6: the
step-2 probe table still lists `change_dir=missing` as an output (only its
routing meaning changed: the wrong-slug stop is replaced by the directory-based
routing), and the probe script itself still prints it exactly as before. The
latch still names `change_dir=missing` among the stop outcomes. The discover
table, the state-output table, the rejection-routing table, and the
release-output table survive with their headers and machine lines. The numbered
steps still end at 6 and no new fenced block was added (still 14 fence lines
across 7 blocks, exactly one `sh` fence). Step 1's ensure-state meanings
(created/reused positioned, checkout_refused/no_branch/no_commits stops) keep
their pinned wording.

### ADD flow-10
The historical design record's derivation table reflects the specifier
delegation as a first-class, disk-routed step (docs only): the "What
change/slug is this?" row no longer describes diffing `spdd/changes/` before
and after delegating a new request to the specifier — the specifier delegation
is a first-class flow step routed from disk: the orchestrator delegates the
change to the specifier when neither the change dir nor the archive exists,
then re-probes. The row keeps the file's historical-record framing (an
explanation of the design's reasoning, not living documentation). No other row
of that table is edited by this change.

## Feature: docs (from 03-docs.feature)

### ADD docs-01
AGENTS.md and CLAUDE.md's branch-marker gotcha bullet states ensure creates the
branch AND checks it out (session on "antz/<slug>", work uncommitted in the
working tree; resume re-positions), that a refused positioning stops the flow
machine-readably ("state=checkout_refused") and never forces anything, keeps
no "-B"/"--force", no merges, no resets, no deletes and adds never a forced or
overwriting checkout (no longer "no checkouts"), marks the behavior level "4.0",
and is textually identical in both files.

### ADD docs-02
The release-gating gotcha bullet states the user-controlled follow-ups (user on
"antz/<slug>", reviews via git status, commits whenever/how, decides whether
and where to merge with "<integration>" as placeholder, optional delete), that
the orchestrator never merges and never resets a branch, names no concrete
integration branch, and is identical in both files.

### ADD docs-03
VERSION reads exactly "4.0.0"; CHANGELOG.md carries a dated "## [4.0.0]" entry
with a "### Changed" section labelling the change breaking (workflow contract),
describing create-and-checkout / re-positioning, the checkout_refused stop,
the intact never-commits law, the inverted no-checkout test assertion, and the
updated user-controlled follow-ups; every earlier entry is byte-untouched.

## Feature: e2e-qa (from e2e-qa.feature)

### ADD e2e-ensure-01
"state=created", puts the session on "antz/my-slug" with the dirty files listed
in git status and contents unchanged; a later re-run prints "state=reused";
git log shows no new commits.

### ADD e2e-ensure-02
The refused off-ramp is user-controlled: "ensure stuck-slug" prints
"state=checkout_refused" (nonzero), the modification intact, session unmoved;
the user's own switch fails with git's conflict message, they commit, and a
re-run "ensure" prints "state=reused" on "antz/stuck-slug".

### ADD e2e-orchestrator-01
A live orchestrated run leaves the user on "antz/<flow slug>" with the roles'
artifacts pending and uncommitted; on approval the final report prints the
human follow-ups (review-and-commit, placeholder merge target, optional
deletion); no commit from any role, no merge run by the orchestrator, marker
branch intact at the flow's base commit.

### ADD e2e-docs-01
"install.sh --check" reports "Claude Code: antz 3.0.0 -> 4.0.0" and
"OpenCode: antz 3.0.0 -> 4.0.0", prints the new CHANGELOG entry, writes nothing;
"--all" re-renders with the new contract and "antz:generated version=4.0.0"
markers; a fresh "--check" reports "already up to date (antz 4.0.0)" for both
clients; AGENTS.md/CLAUDE.md carry the updated bullets identically.

## Feature: scriptsource (from 01-scriptsource.feature, change `orchestrator-fast-path`)

The orchestrator prompt's three embedded scripts become source files. Merged
2026-09-11; VERSION 4.3.0. No behavior change.

### ADD scriptsource-01
`scripts/orchestration/antz-flow.sh`, `scripts/orchestration/antz-probe.sh`, and
`scripts/orchestration/antz-skills.sh` exist, each parses with `sh -n`, and each
keeps the header comment its embedded counterpart carried in the prompt
(including the `sh <tempfile> ...` usage lines).

### MODIFY scriptsource-02
Each file is a byte-equal dedent of its fenced snippet in the pre-change prompt
(change-time verification, like descmatch-04 — not a permanent regression test).
This superseded the flow-branch invariant that the flow script "stays the
prompt's first 3-space-indented bare fence" and the skills-activation invariant
that antz-skills.sh "remains a temp-file-executed POSIX sh snippet embedded in
the prompt" — both merged as superseded above/in `spdd/specs/skills-activation.md`.
Verified at merge: flow and skills byte-identical to their base-commit dedents;
the probe differs from its base dedent only by sub-spec 05's declared extension
(classify_receipt + the extended `subspec=` line).

### MODIFY scriptsource-03
Each of the three script fences' bodies in `agents/prompts/orchestrator.prompt`
is exactly the single line `# antz-include: scripts/orchestration/<name>.sh`
(antz-flow, antz-skills, antz-probe), in the position its fenced script
previously occupied; fence styles unchanged (flow stays the first 3-space bare
fence, the probe stays the "```sh" fence); every line outside those fenced
bodies byte-unchanged at this sub-spec's boundary (later sub-specs' declared
prose edits — session guards, receipts classification, closing block — are the
only further deltas, verified at merge by rebuilding the base prompt with
markers and diffing).

### ADD scriptsource-04
The extraction is scoped: the sub-spec's diff touches only
`scripts/orchestration/` (three new files) and the three fenced bodies of
`agents/prompts/orchestrator.prompt`; specifier/coder/verifier prompts, all four
meta files, and install.sh are byte-unchanged by it (transient change-time
guard; the later sub-specs' own declared deltas are the only further changes).

### Invariants
- The scripts' runtime contract is untouched: POSIX sh, save-to-temp-file and
  `sh <tempfile> ...`, nothing installed as a standalone CLI/hook/plugin (the
  files are repo source, never installed anywhere).
- Script behavior is unchanged: every pre-existing script-level assertion holds
  against the files.
- The prompt remains framework-neutral: include markers carry no client-specific
  syntax; the same body renders into both clients.

## Feature: renderinject (from 02-renderinject.feature, change `orchestrator-fast-path`)

`install.sh` injects the orchestration scripts into the rendered orchestrator
body, for both clients. No behavior change beyond the render source.

### ADD renderinject-01
The rendered Claude Code `antz-orchestrator` body contains, inside each of the
three script fences, the verbatim content of the corresponding
`scripts/orchestration/` file (each non-empty line carrying the fence's
three-space indent, blank lines empty, exactly as the embedded snippet rendered
before); no `# antz-include:` line survives anywhere; the rendered body is
byte-identical to the pre-change render (same version marker).
- **Render carve-out (recorded at merge — not present in the delivering
  sub-spec's text)**: antz-skills.sh's embedded counterpart carried a
  pre-existing under-fence-indent line (the loop-closer `  done` at two spaces,
  base prompt line ~217), whose dedent left it untouched; byte-identity pins it
  verbatim, so `install.sh`'s `inject_includes` carries one pinned exception
  keyed to `scripts/orchestration/antz-skills.sh` (`s/^     done$/  done/`
  after the indent re-application), documented in install.sh's comment. The
  file content alone cannot distinguish that historical line from a genuinely
  dedented one, hence the file-and-shape-keyed exception.

### ADD renderinject-02
The same injection for OpenCode at its own frontmatter: same three verbatim
script contents at the same fences, no marker surviving; the frontmatter keeps
its pre-change shape (`mode: primary`, `permission:` with `edit: deny` and the
deny-by-default `task:` allowlist).

### ADD renderinject-03
The runtime contract is unchanged: the rendered body still instructs saving each
script to a temp file and running `sh <tempfile> ...` (flow subcommand line,
skills invocation, probe run by `state` with CHANGE_DIR at the change
directory); the install writes no file beyond its pre-change set (four agents
plus `/antz` and `/antz-set-model` per client) — no standalone script, CLI,
hook, or plugin.

### ADD renderinject-04
The scripts resolve through the one `fetch_file` helper (local read or RAW_BASE
fetch); when any of the three is missing or cannot be fetched, install.sh exits
non-zero naming the file, with no rendered orchestrator body written and no
`# antz-include:` fallback anywhere.

### ADD renderinject-05
The injection is keyed to the orchestrator only: the specifier, coder, and
verifier bodies and both command copies are byte-identical to their pre-change
renders (same version marker; the byte-identity assertions for role prompts
whose prose a later sub-spec of the same change legitimately extended are
retired with a loud note, structural assertions enforced — the
retirement-note precedent); no other prompt contains a marker, and markers are
substituted only for the orchestrator.

### MODIFY renderinject-06
install.sh's header comment states that VERSION + CHANGELOG.md track changes to
`agents/prompts/`, `agents/meta/`, AND `install.sh`; the stale two-item sentence
is gone; no other header line changes meaning. This closes the drift recorded in
`spdd/specs/versioning.md` (see the supersession note there).

### MODIFY renderinject-07
AGENTS.md and CLAUDE.md's orchestrator-script gotcha wording (the branch-marker
gotcha's antz-flow.sh sentence and the probe gotcha's sourcing sentence) state
the scripts' source of truth is `scripts/orchestration/<name>.sh` and that
install.sh injects their content into the rendered `antz-orchestrator` body for
both clients, keep the unchanged runtime wording (temp file + `sh <tempfile>
...`, nothing installed standalone), and state it identically in both files.

### Invariants
- No behavior change: at the render layer the orchestrator body is byte-identical
  to the pre-change render (same version marker); the flow's runtime contract,
  law wording, and output vocabulary are untouched.
- `--check` stays keyed off the installed specifier agent's marker version; the
  injection adds no new report line.
- install.sh stays POSIX sh and bash-3.2-safe: script content is read from files
  via `fetch_file`, never pasted into heredocs captured inside command
  substitutions (the posixsh-01 hazard).
- Nothing is ever installed outside the orchestrator's rendered body.

## Feature: testharness (from 03-testharness.feature, change `orchestrator-fast-path`)

The script test suites read `scripts/orchestration/` files directly.

### MODIFY testharness-01
`tests/antz-flow_test.sh` loads `scripts/orchestration/antz-flow.sh` (and the
probe file for the state tests) as real files, with no extraction step reading
`agents/prompts/orchestrator.prompt`; every pre-existing flow assertion keeps
passing unchanged against the file. (Supersedes the "both test files extract it
mechanically" invariant above.)

### MODIFY testharness-02
`tests/orchestrator-status-probe_test.sh` runs `scripts/orchestration/antz-probe.sh`
directly with CHANGE_DIR pointed at fixture change dirs, no extraction from the
prompt; every pre-existing probe assertion keeps passing unchanged, plus the
suite's file-source guard (`sh -n`, shebang, prompt fence is exactly its marker).

### MODIFY testharness-03
`tests/orchestrator-skills-block_test.sh` runs `scripts/orchestration/antz-skills.sh`
directly (the marker-to-fence-close extractor — which dropped the shebang — is
gone); every pre-existing block/derivation/matching/none-matched/constraint and
body-never-read assertion passes unchanged. Its orchestrator.prompt
additive-vs-HEAD guard is re-scoped (superseding the descmatch-05 wording in
`spdd/specs/skills-activation.md`): each of the three script fences must carry
exactly its `# antz-include:` marker line naming an existing file, and removed
lines are permitted only inside those three fenced bodies (any removal outside
them still fails the guard); the snippet still parses with `sh -n`.

### ADD testharness-04
A render-consistency guard (`tests/orchestrator-render-sync_test.sh`): with
install.sh run for both clients into an isolated temp HOME, each installed
`antz-orchestrator` body's three script fences are byte-identical to the current
`scripts/orchestration/` files (indentation re-applied, sharing install.sh's one
pinned antz-skills.sh carve-out); tampering one byte of one installed fence
reports exactly that script out of sync, so a file change without a matching
re-render fails the suite.

### Invariants
- Assertion coverage is unchanged: every pre-existing scenario id keeps being
  reported and passing; only the source of the script under test changes.
- No test extracts a script from the prompt anymore.
- The suites stay self-contained, mirroring the repo's harness style.

## Feature: sessionguards (from 04-sessionguards.feature, change `orchestrator-fast-path`)

Two session-level guards in the orchestrator prompt's prose (no script, no probe
field, no new subcommand): dedup and the post-stop latch.

### ADD sessionguards-01
Within one orchestrator invocation the same (sub-spec, role) pair is never
delegated twice: once a pair has been delegated, later flow steps route by the
existing state machine (fresh classification from disk, the bounded retry, the
stops) and never by re-delegating that pair. The single carve-out: step 4's
bounded-retry relay of attributable blockers to the named sub-spec's coder
session is the one permitted second delegation of a pair, still bounded by
REJECTED.md (at most one relay per pair per entry; a second entry stops the flow
for good). Per-invocation clean slate on resume; tool-grant-independent binding
(same standing as the never-delegate-outside-the-three-roles rule).

### ADD sessionguards-02
After any stop-and-report outcome the session performs no further delegation of
any kind, reporting and ending instead; resumption is always a fresh invocation.
The named stop outcomes include at least: `open_questions=yes`; `state=no_git`,
`state=no_repo`, `state=no_commits`, `state=checkout_refused`,
`state=no_branch`, `branch=missing`, `change_dir=missing`,
`gate=refused reason=...`; a `BLOCKED:`-reasoned sub-spec found in
classification; `rejected_count=2`; a non-attributable blocker in a rejected
entry; and a slug-ambiguity stop (no unambiguous on-disk candidate). The latch
covers delegation only — the orchestrator's own read-only probing is unchanged.

### ADD sessionguards-03
The guards are prompt prose only: no new embedded or extracted script, no new
flow subcommand (the usage line still names exactly discover/ensure/state/release),
no new probe field, and no file under `spdd/` records delegation history; the
session's own account of the delegations it already made is the mechanism.

### ADD sessionguards-04
Everything else keeps its meaning: step ordering, the discover/state tables, the
classification rules, the rejection routing, the release handling, and the
Report Format survive; the guards add constraints only, never re-routing an
existing outcome.

## Feature: receipts — orchestrator flow edges (from 05-receipts.feature, change `orchestrator-fast-path`)

The coder-side receipt duty and grammar live in `spdd/specs/receipts.md`; the
flow-side edges merge here.

### MODIFY receipts-06
The probe (`scripts/orchestration/antz-probe.sh`) extends every `subspec=` line
with `receipt=<NN-<feature>.result|missing> covered=<n>/<N> complete=<yes|no>
class=<done|blocked|in_progress>`: complete=yes requires the receipt to exist
with exactly one non-empty `test_command=` line and exactly the declared id set
(a foreign id is a mismatch — covered may read N/N with complete=no); class=
applies the mapping (any `result=blocked` line → blocked, checked first
regardless of coverage; else complete=yes with all results green/skip → done;
else in_progress). The literal sentinel `test_command=none` is accepted as a
well-formed non-empty value: complete may be yes with `none` (the probe script
is byte-unchanged — any non-empty `test_command=` value is already well-formed).
The probe's other outputs are unchanged (`open_questions=`,
`rejected_count=`, the `change_dir=missing` short-circuit, the empty-ids
stop-and-ask rule). Verified live at merge on a fixture matrix: missing receipt,
all-green done, ordinary-skip done, blocked-first regardless of coverage,
uncovered id, foreign id, empty ids (complete=no, class=in_progress — never
vacuously done), and none-sentinel all-green done.

### MODIFY receipts-07
The orchestrator's step 3 classifies each sub-spec from the probe's receipt
fields alone — done (complete receipt, green/ordinary-skip), blocked (any
`result=blocked` line: stop at the first one found, relay its `BLOCKED:` reason,
route to specifier as today), in_progress (delegate to a fresh coder session as
today) — and no longer instructs discovering the unit-suite command or running
the suite for classification; the old run-for-classification sentence is gone.

### ADD receipts-08
The doubtful-receipt exception: a sub-spec whose receipt is missing, incomplete,
or mismatched (complete=no) gets exactly one suite re-run, for that sub-spec
only — using the receipt's `test_command=` value when it carries one, else
discovering the command the way any contributor would — classified from the
actual run result, with the receipt doubt reported; the orchestrator never
writes, fixes, or fabricates the receipt (it stays the coder's artifact).

### MODIFY receipts-09
No pre-verifier gate: once every sub-spec is done, step 4 routes to the verifier
without running the unit suite at all; the verifier's own e2e Integration
Verification suite remains the independent gate.

### ADD receipts-11
The orchestrator never executes the sentinel — with `none` and a doubtful
receipt it classifies from the id lines or asks the user once: the sentinel
is never executed; a doubtful receipt whose `test_command=` value is the
literal `none` is never run by the orchestrator. With `none` and a doubtful
receipt, the orchestrator classifies from the receipt's `id=` lines where they
settle the outcome — any `result=blocked` line still stops at the first one
found and relays its `BLOCKED:` reason the same way a well-formed blocked
receipt would — and when the id lines cannot settle it, the orchestrator asks
the user once rather than guessing: the receipt-doubt stop, reported
`status=waiting-user`. The rest of the doubtful-receipt exception is
unchanged: a doubtful receipt carrying a real command is still re-run once for
that doubtful sub-spec only, a receipt carrying no `test_command=` line at all
still falls to discovering the command the way any contributor would, the
sub-spec is classified from the actual run result, the doubt is reported, and
the orchestrator still never writes, fixes, or fabricates the receipt.

## Feature: e2e — orchestrator-fast-path (from 07-e2e.feature)

Verified at merge (2026-09-11) by the verifier against a temp HOME holding a
genuine pre-change install rendered from the flow's base commit (marker 4.2.1):

- **e2e-01** executed fully: `--check` wrote nothing (md5-verified) and reported
  the 4.2.1 → 4.3.0 drift for both clients printing the [4.3.0] entry; `--all`
  installed exactly the pre-change 12-file inventory, every file stamped
  `antz:generated version=4.3.0`, no `# antz-include:` survivor; both clients'
  orchestrator bodies carry the three scripts byte-identically at their fences
  (flow and skills fences byte-equal to the base render; the probe fence differs
  only by the declared receipts extension); the flow script extracted from the
  installed copy parses and its `discover` prints the same machine lines as
  `sh scripts/orchestration/antz-flow.sh discover` (`candidate=branch
  slug=orchestrator-fast-path` / `candidate=on-disk slug=orchestrator-fast-path`).
- **e2e-02** executed fully: all three script suites pass reading the files
  directly (26+34+11 assertions), in-repo `discover` matches the temp-file
  invocation, and `sh -n` passes for each of the three files.
- **e2e-05** executed fully: see e2e-01's `--check`/`--all` halves; a fresh
  `--check` against the new install reports "already up to date (antz 4.3.0)"
  for both clients.
- **e2e-03 / e2e-04** (live-session halves) judged by the mechanism they
  exercise, per the repo's established e2e convention (no role can spawn a live
  client session): the receipt grammar and the probe's mechanical
  classification were exercised live on fixture change dirs (receipts-06 above);
  this change's own seven receipts are well-formed and classify `done` from
  disk via the flow `state` probe; the coder prompt's receipt duty and the
  closing-block vocabularies are pinned and unit-tested (receipts_test.sh,
  closingblock_test.sh); the guards' stop outcomes and the REJECTED.md counting
  mechanism are unit-tested (orchestrator-sessionguards_test.sh,
  orchestrator-status-probe_test.sh). Machine-observability-limited, not
  reducible here.

### ADD e2e-01
A fresh `./install.sh --all` renders both clients' antz-orchestrator with the
three scripts byte-identical at their fences under the unchanged
`antz:generated version=4.3.0` marker; the extracted flow script's `discover`
prints the same machine lines as the direct source run; nothing is installed
beyond the pre-change set.

### ADD e2e-02
The three script suites pass reading `scripts/orchestration/` files directly;
in-repo `discover` prints the same `candidate=` lines as the temp-file
invocation; `sh -n` passes for each of the three files.

### ADD e2e-03
A live /antz flow's coder sessions write `NN-<feature>.result` receipts that the
orchestrator classifies from disk without running the unit suite, and every
report's closing block mirrors its receipt (live-session half judged by
mechanism; see the verification record above).

### ADD e2e-04
In a live flow a `BLOCKED:` planning refusal stops the session for good with no
further delegation, and a twice-rejected change appends two `## Rejection <n>`
entries and is never retried again (live-session half judged by mechanism).

### ADD e2e-05
Against pre-change 4.2.1 installed copies, `--check` reports the drift to 4.3.0
for both clients and prints the [4.3.0] entry writing nothing; `--all` restamps
every installed file; a fresh `--check` reports already up to date (antz 4.3.0).

## Feature: e2e-qa — fix-orchestrator-flow (from e2e-qa.feature, change `fix-orchestrator-flow`)

Verified at merge (2026-09-12) by the verifier. e2e-version-01 executed fully
against a temp HOME with 4.3.0-stamped installed copies; e2e-delegation-01
and e2e-approval-01 are live-session halves judged by mechanism.

- **e2e-version-01** executed fully: with 4.3.0-stamped specifier agent files
  in both client directories, `./install.sh --check` reported
  "Claude Code: antz 4.3.0 -> 4.4.0" and "OpenCode: antz 4.3.0 -> 4.4.0",
  printed the full [4.4.0] CHANGELOG entry, wrote nothing; `./install.sh --all`
  restamped every installed file; a fresh `--check` reported "already up to date
  (antz 4.4.0)" for both clients; AGENTS.md and CLAUDE.md carry the updated
  strict-ownership gotcha bullet identically in both files.
- **e2e-delegation-01 / e2e-approval-01** (live-session halves) judged by the
  mechanism they exercise, per the repo's established e2e convention (no role
  can spawn a live client session): the orchestrator prompt's post-ensure routing
  (flow-01..03), the dedup guard's two exceptions (flow-06), step 5's disk-based
  detection (flow-04..05), the waiting-user/stopped definitions (flow-07..08),
  and the unchanged surface (flow-09) are all pinned by the existing test suites
  and verified live against the working tree. Machine-observability-limited, not
  reducible here.

### ADD e2e-delegation-01
A fresh change gets its flow reaching the specifier instead of dying at
`change_dir=missing` (live-session; judged by mechanism).

### ADD e2e-approval-01
Approval is decided from disk, so the user sees the same observable outcome
whether the verifier said approved or approved-with-warnings, and gets the
human follow-ups (live-session; judged by mechanism).

### ADD e2e-version-01
Against pre-change 4.3.0 installed copies, `--check` reports the drift to
4.4.0 for both clients and prints the [4.4.0] entry; `--all` restamps every
installed file; a fresh `--check` reports already up to date (antz 4.4.0) for
both clients; AGENTS.md and CLAUDE.md carry the updated strict-ownership
gotcha bullet identically in both files.
