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
- The script stays the prompt's first 3-space-indented bare fence (the probe is
  its "```sh" fence); both test files extract it mechanically.

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
