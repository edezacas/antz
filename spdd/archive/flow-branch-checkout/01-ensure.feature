Feature: ensure creates the flow branch AND checks it out, refusing never forcing, while every other subcommand and the never-commits law hold unchanged
  # Layer: the embedded "antz-flow.sh" script inside
  # agents/prompts/orchestrator.prompt (the flow's git plumbing). This is a
  # NEW standalone spec domain: spdd/specs/ holds no governing spec for the
  # flow script (posixsh.md covers install.sh, set-model.md the
  # /antz-set-model command, specifier-role.md the specifier's Output
  # section, versioning.md the repo policy docs). Every scenario below is
  # therefore ADD at merge; the verifier creates the new domain file (see
  # README.md "Governing spec situation").
  #
  # What changes: only the "ensure" subcommand -- it now positions the
  # session on the branch (create-then-switch on the fresh path, plain
  # switch on the resume path), refuses machine-readably when git would
  # have to destroy uncommitted work, and reports truthfully when no branch
  # could be ensured. Everything else -- discover, state, release, the
  # preflight, the one-line stdout contract, and the never-commits law --
  # is pinned here unchanged as regression guards.
  #
  # The coder's unit suite is tests/antz-flow_test.sh, rewritten to carry
  # these ensure-<index> ids in the reported test names (the old flow-<n>
  # ids retire with the old assertions; the no-checkout assertion in
  # particular is inverted, never deleted). The script must stay the
  # prompt's first 3-space-indented bare ``` fence -- both test files
  # extract it mechanically (the "extracted" guard test).

  Background:
    Given "agents/prompts/orchestrator.prompt" embeds the "antz-flow.sh"
      script in its first 3-space-indented fenced block, with the four
      subcommands discover / ensure <slug> / state <slug> <probe-path> /
      release <slug> and a preflight that fail-closes every subcommand with
      "state=no_git" (git not on PATH) or "state=no_repo" (not inside a git
      repository)
    And every subcommand prints exactly one machine line on stdout (discover:
      one "candidate=" line per match, possibly none), with exit status 0 on
      success and nonzero on every stop state

  # ADD - ensure-01: the fresh path creates the marker branch at the current
  # HEAD and positions the session on it, with zero new commits.
  Scenario: ensure-01
    Given a git repository with at least one commit, the session on branch
      "master", and no "antz/<slug>" branch
    When the flow script runs "ensure <slug>"
    Then stdout is exactly "state=created" with exit status 0
    And the session is now on branch "antz/<slug>"
    And "refs/heads/antz/<slug>" points at the same commit HEAD pointed at
      before the call
    And no new commit exists anywhere in the repository (HEAD's commit count
      is unchanged)

  # ADD - ensure-02: uncommitted working-tree work survives the positioning
  # untouched -- the switch carries it over rather than destroying or
  # stashing it.
  Scenario: ensure-02
    Given a git repository with the session on "master" and a tracked file
      whose working-tree content differs from its committed content (an
      uncommitted change)
    And no "antz/<slug>" branch
    When the flow script runs "ensure <slug>"
    Then stdout is exactly "state=created" and the session is on
      "antz/<slug>"
    And the file's working-tree content is byte-identical to before the call
    And the change is still uncommitted (git status still reports it
      modified) and no stash entry was created

  # ADD - ensure-03: the resume path positions the session onto the existing
  # branch without ever rewriting it.
  Scenario: ensure-03
    Given a git repository where branch "antz/<slug>" already exists,
      pointing at the flow's base commit from an earlier session
    And the session is currently on a different branch (e.g. "master")
    When the flow script runs "ensure <slug>"
    Then stdout is exactly "state=reused" with exit status 0
    And the session is now on branch "antz/<slug>"
    And "refs/heads/antz/<slug>" still points at the same commit it pointed
      at before the call (never rewritten, no -B semantics)
    And no new commit exists

  # ADD - ensure-04: re-running ensure mid-flow (the orchestrator runs it on
  # every invocation) is a safe no-op when already positioned.
  Scenario: ensure-04
    Given a git repository where the session is already on branch
      "antz/<slug>" from an earlier ensure
    When the flow script runs "ensure <slug>"
    Then stdout is exactly "state=reused" with exit status 0
    And the session is still on "antz/<slug>", HEAD and every branch ref are
      unchanged, and the working tree is untouched

  # ADD - ensure-05: when git refuses the positioning (a destructive-checkout
  # conflict -- uncommitted changes the switch would overwrite), the script
  # stops with the machine-readable refused state and forces nothing.
  Scenario: ensure-05
    Given a git repository where the session is on "master" at a commit
      whose committed content of "a.txt" differs from the content committed
      on existing branch "antz/<slug>"
    And the working tree holds an uncommitted change to "a.txt" that
      switching to "antz/<slug>" would overwrite
    When the flow script runs "ensure <slug>"
    Then stdout is exactly "state=checkout_refused" with exit status 1
    And the working tree still holds the uncommitted change to "a.txt",
      byte-identical to before the call
    And the session is still on "master" at the same commit, and
      "antz/<slug>" still points at its original commit
    And nothing was forced, stashed, reset, or deleted (no new commits, no
      stash entries, every branch ref unchanged)

  # ADD - ensure-06: the script is statically free of destructive mechanisms
  # -- the refusal path above is backed by the absence of any force, reset,
  # clean, stash, restore, or branch-delete capability in the script itself.
  Scenario: ensure-06
    When the script's git invocations are scanned mechanically over the
      extracted fence
    Then no invocation carries the flags "-B", "--force", or "-f", and no
      invocation is "git reset", "git clean", "git stash", "git restore",
      or "git branch" with "-d"/"-D"
    And "git branch" appears only to create the marker branch (plain
      "git branch antz/<slug>", no flags) and the positioning appears only
      as a plain, flagless switch onto "antz/<slug>"

  # ADD - ensure-07: no subcommand ever commits -- HEAD and every branch ref
  # hold steady across ensure (now with the switch), state, and release, on
  # both a refused release and a successful one.
  Scenario: ensure-07
    Given a git repository with marker branch "antz/<slug>" and a change
      dir "spdd/changes/<slug>", one commit in history, and the session
      positioned wherever an earlier ensure left it
    When discover, ensure, and state run in sequence, then release (refused:
      the change dir is still present), then release again after the change
      dir has been moved to "spdd/archive/<slug>" (successful)
    Then HEAD's commit count is unchanged (still one) and every branch ref
      is byte-identical before and after the whole sequence
    And the working tree keeps every uncommitted change throughout

  # ADD - ensure-08: the preflight fail-close is unchanged -- every
  # subcommand, both environments.
  Scenario Outline: ensure-08
    Given <environment>
    When the flow script runs <subcommand>
    Then stdout is exactly "<machine-line>" with exit status 1

    Examples:
      | environment                          | subcommand          | machine-line     |
      | git absent from PATH                 | discover            | state=no_git     |
      | git absent from PATH                 | ensure <slug>       | state=no_git     |
      | the directory is not a git repo      | discover            | state=no_repo    |
      | the directory is not a git repo      | ensure <slug>       | state=no_repo    |

  # ADD - ensure-09: the unborn-repo fail-close is unchanged -- no branch,
  # no positioning attempt.
  Scenario: ensure-09
    Given a git repository with no commits
    When the flow script runs "ensure <slug>"
    Then stdout is exactly "state=no_commits" with exit status 1
    And no "antz/<slug>" branch exists and no positioning was attempted

  # ADD - ensure-10: when the branch cannot be made to exist (the creation
  # attempt fails and the branch is still absent), ensure fail-closes
  # truthfully -- never a success state, never a false "reused".
  Scenario: ensure-10
    Given a git repository with no "antz/<slug>" branch where the branch
      creation attempt is made to fail without creating anything (e.g. a
      git shim that exits nonzero on "git branch")
    When the flow script runs "ensure <slug>"
    Then stdout is exactly "state=no_branch" with exit status 1
    And the session's branch position is unchanged and nothing destructive
      happened

  # ADD - ensure-11: the release gate is unchanged -- every refusal reason,
  # exact machine line, and nothing ever removed on a refusal.
  Scenario Outline: ensure-11
    Given <fixture>
    When the flow script runs "release <slug>"
    Then stdout is exactly "gate=refused reason=<reason>" with exit status 1
    And nothing changed on disk (no branch, directory, or file removed or
      altered)

    Examples:
      | fixture                                                          | reason                |
      | marker branch exists, "spdd/archive/<slug>" absent               | archive-missing       |
      | marker branch, archive present, "spdd/changes/<slug>" present    | change-still-present  |
      | archive present, no marker branch                                | branch-missing        |

  # ADD - ensure-12: a successful release prints exactly the branch line,
  # removes nothing, and prints no commands for anyone to run.
  Scenario: ensure-12
    Given marker branch "antz/<slug>", "spdd/archive/<slug>" present, and
      no "spdd/changes/<slug>"
    When the flow script runs "release <slug>"
    Then stdout is exactly "released branch=antz/<slug>" with exit status 0
    And the branch still exists and the archive directory still exists
    And stdout carries no command suggestion of any kind

  # ADD - ensure-13: discover is unchanged -- branch markers and on-disk
  # change dirs, nothing when neither exists.
  Scenario: ensure-13
    Given a git repository with no "antz/*" branches and no change
      directories
    When the flow script runs "discover"
    Then stdout is empty
    Given a git repository with marker branch "antz/listed-slug" and change
      dir "spdd/changes/listed-slug"
    When the flow script runs "discover"
    Then stdout is exactly one "candidate=branch slug=listed-slug" line and
      one "candidate=on-disk slug=listed-slug" line

  # ADD - ensure-14: state is unchanged -- it verifies the marker branch,
  # resolves the repo root, and runs the probe verbatim with CHANGE_DIR at
  # the working tree's change dir.
  Scenario: ensure-14
    Given marker branch "antz/<slug>" and change dir "spdd/changes/<slug>"
      containing a "01-x.feature" file
    When the flow script runs "state <slug> <probe-path>"
    Then stdout contains "working_root=<repo root>" and the probe's own
      output with CHANGE_DIR pointing at the working tree's
      "spdd/changes/<slug>"
    When the flow script runs "state <slug> <probe-path>" in a repository
      with no "antz/<slug>" branch
    Then stdout is exactly "branch=missing" with exit status 1

### Invariants
- Stdout is exactly one machine line per subcommand invocation (discover: one
  "candidate=" line per match, possibly none); git's own chatter is never
  part of the contract on stdout.
- No subcommand ever commits anything; the marker branch still points at the
  commit the flow started from forever.
- No destructive git ever: no "-B", no "--force"/"-f" on any invocation, no
  "reset", no "clean", no "stash", no "restore", no "branch -d"/"-D"
  (ensure-06 is the static backstop; ensure-05/07 the behavioral ones).
- Success states imply positioned: "state=created" and "state=reused" are
  printed only once the session actually sits on "antz/<slug>".
- A refused or failed ensure alters nothing: working tree content, HEAD
  position, and every branch ref are identical before and after.
- "state=reused" is never printed when the branch does not exist: the old
  loose arm (a failed create printing a blind "state=reused") is replaced by
  the truthful "state=no_branch" stop; a create that loses a concurrent race
  re-checks and proceeds through the same positioning as the resume path,
  terminating in a single truthful state line.
- The preflight (no_git/no_repo) runs before every subcommand and is
  unchanged; "state=no_commits" keeps its exact meaning and output.
- discover, state, and release keep their exact output contracts, gates, and
  no-removal guarantee; release prints no commands to run (the human
  follow-ups live in the orchestrator prompt's prose, sub-spec
  "orchestrator" below).
- The script stays the prompt's first 3-space-indented bare fence, and the
  probe its "```sh" fence -- the mechanical extraction in both test files
  depends on those shapes.
