# Change: flow-script-guards — end-to-end QA suite (one file per change dir,
# one series per user-visible surface, the archived practice).
#
# Operates at the product's real UI: the flow script's CLI affordance
# (`sh scripts/orchestration/antz-flow.sh ...`, the same temp-file-executed
# script the orchestrator runs), install.sh's CLI, and the working tree a user
# can inspect with `git status`/`git branch`. No internal API calls — there
# are none.
#
# The live-session halves (a real /antz invocation stopping on these states
# and printing the resume action) are observable only by driving a real client
# session, which no role can spawn: per the repo's established e2e convention
# their unit-level halves ship as explicit SKIP stubs (id-accounted) and the
# verifier exercises them live during Integration Verification, judging the
# mechanism they exercise. e2e-slug-01 and e2e-version-01 are fully runnable;
# e2e-tree-01's script-level half is runnable and its live-orchestrator
# routing half is judged by mechanism.

Feature: a user sees the new flow-script guards through the flow script and the 4.5.0 install surface

  # ADD - e2e-slug-01: the mechanical slug rejection a user sees when they
  # invoke the flow's ensure with an invalid slug (runnable CLI affordance).
  Scenario: e2e-slug-01
    Given a clean checkout of the repository with at least one commit
    When the user runs the flow script's "ensure" with an invalid slug (for
      example an uppercase or over-40-character slug) from the repository root
    Then it prints exactly "state=bad_slug" and exits non-zero
    And "git branch" shows no "antz/..." branch was created, the user is still
      on the branch they started on, and "git status" is unchanged — a
      non-destructive rejection
    When the user runs "ensure" again with a valid short kebab-case slug
    Then it prints "state=created", the session is on "antz/<slug>", and
      "git log" shows no new commit

  # ADD - e2e-tree-01: the tree guard a user meets at the start of a new flow,
  # and the advisory a resume carries (script-level half runnable; the live
  # orchestrator routing half judged by mechanism).
  Scenario: e2e-tree-01
    Given a clean checkout with at least one commit, no "antz/<slug>" branch,
      and no "spdd/changes/<slug>/" for the requested change, with one
      uncommitted change in the working tree
    When the user runs the flow script's "ensure" with the slug
    Then it prints exactly "state=tree_dirty" and exits non-zero, no
      "antz/<slug>" branch is created, and the uncommitted change is intact
    When the user commits or discards the dirt and re-runs "ensure"
    Then it prints "state=created" and positions the session on "antz/<slug>"
    And once "spdd/changes/<slug>/" exists (a resume) with the working tree
      dirty again, "ensure" prints "state=reused" followed by "dirty=yes" and
      still positions the session — the guard is skipped on resume
    And in a live /antz invocation that meets "state=tree_dirty" the
      orchestrator stops, reports "status=stopped", and names the resume
      action (clean, commit, or gitignore the dirt, then re-invoke); when it
      meets "state=bad_slug" it likewise stops and names choosing a valid slug
      (live-session; judged by mechanism)

  # ADD - e2e-version-01: the version surface a user sees through install.sh
  # against pre-change installed copies (runnable).
  Scenario: e2e-version-01
    Given installed antz agent and command files stamped
      "antz:generated version=4.4.0" in the user's client directories
    When the user runs "./install.sh --check"
    Then it reports the drift to 4.5.0 for both clients, prints the
      intervening "[4.5.0]" CHANGELOG entry, and writes nothing
    When the user runs "./install.sh --all"
    Then every installed file is restamped "antz:generated version=4.5.0"
      with the updated orchestrator and flow-script content rendered verbatim,
      and a fresh "--check" reports already up to date (antz 4.5.0) for both
      clients
