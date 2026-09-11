Feature: the orchestrator prompt's instructions reflect the checkout contract and the user-controlled human follow-ups
  # Layer: agents/prompts/orchestrator.prompt's prose that consumes the
  # embedded antz-flow.sh (step 1's discover/ensure instructions and tables,
  # step 5's release table and human follow-up print, "## Owns", and the
  # script's own header comment). Depends only on the machine lines defined
  # identically in sub-spec "ensure" (shared contract; see README.md) --
  # implementable and verifiable alone once 01's vocabulary is fixed. All
  # scenarios are ADD (new domain at merge).
  #
  # Reading-based scenarios ("the reader reads ...") are the standard form
  # for prompt/doc content in this repo, verified by static assertions on
  # the prompt file in the coder's unit suite (precedent:
  # tests/versioning-rule_test.sh, tests/entities-operations-table_test.sh).

  Background:
    Given "agents/prompts/orchestrator.prompt" as published before this
      change, carrying the embedded script, the step-1 discover table and
      ensure paragraph, the step-5 release-output table and human
      follow-up print, and the "## Owns" / "## What you don't do" sections
    And the embedded script updated per sub-spec "ensure" (ensure positions
      the session on "antz/<slug>" and stops machine-readably on a refused
      positioning)

  # ADD - orchestrator-01: step 1's ensure instructions document the new
  # state meanings, including the refused stop and its user-controlled
  # resolution.
  Scenario: orchestrator-01
    When the reader reads step 1's ensure instructions (the paragraph after
      the slug-derivation bullet and the discover-output table's ensure
      references)
    Then "state=created" and "state=reused" are each described as having
      positioned the session on branch "antz/<slug>" (the flow's work now
      happens on that branch, uncommitted)
    And a "state=checkout_refused" outcome is documented: git refused the
      positioning because it would overwrite uncommitted changes, the
      orchestrator stops and reports, the user resolves the conflict
      themselves (e.g. commit or stash) and re-invokes, and nothing is ever
      forced
    And a "state=no_branch" outcome is documented as a stop-and-report the
      same way
    And "state=no_commits" keeps its stop-and-report meaning unchanged

  # ADD - orchestrator-02: step 5's human follow-up print reflects that the
  # user is already on the flow branch, and hands every follow-up to the
  # user.
  Scenario: orchestrator-02
    When the reader reads step 5's human follow-up print (the fenced block
      and its surrounding prose after the release-output table)
    Then it states the finished work sits uncommitted in the working tree
      and the user sees it on branch "antz/<slug>" via "git status"
    And committing is presented as the user's own decision of whenever and
      how (review and commit selectively), not one mandated command form
    And merging is presented as the user's own decision of whether and
      where, with the example target shown as a placeholder (e.g. "git
      switch <integration> && git merge antz/<slug>")
    And deleting the marker branch "antz/<slug>" is presented as the user's
      own optional cleanup
    And the prose states these are suggestions for the human to run
      themselves -- the orchestrator never runs them

  # ADD - orchestrator-03: no integration branch name is hardcoded anywhere
  # in the prompt -- the merge target is always the user's to name.
  Scenario: orchestrator-03
    When the reader reads the whole orchestrator prompt
    Then no concrete integration branch name (no specific branch such as
      "master" or "main") appears as a merge target anywhere in the prose,
      tables, or printed follow-ups
    And every merge/delete example that names a branch names only the
      flow's own "antz/<slug>" marker branch or a placeholder target

  # ADD - orchestrator-04: the law wording is updated to the new contract
  # (no checkouts -> never a forced checkout) while the never-commits law
  # and the four-subcommand boundary survive verbatim in meaning.
  Scenario: orchestrator-04
    When the reader reads the "## Owns" section and the embedded script's
      header comment
    Then the branch is described as created AND checked out by ensure
      (re-positioned onto on resume), still a marker of the commit the
      flow started from, with the work staying uncommitted in the main
      checkout's working tree
    And the destruction law reads: no "-B", no "--force", no resets, no
      merges, no branch deletes, and never a forced or overwriting
      checkout -- the one checkout ensure performs is refused, not forced,
      when it would destroy uncommitted work
    And "no role ever commits anything" is stated, in meaning verbatim, in
      both the law list and the owns section
    And the "## What you don't do" bullet still confines the orchestrator
      to the embedded script's four subcommands with no ad-hoc git

  # ADD - orchestrator-05: everything not named above is unchanged -- no new
  # subcommand, step, probe, or routing row.
  Scenario: orchestrator-05
    When the reader reads the discover table, the state-output table,
      step 3's sub-spec classification, step 4's rejection routing, the
      release-output table, and the Report Format section
    Then their rows and meanings are unchanged by this change (the
      release-output table keeps its four exact machine lines; discover
      keeps "candidate=branch"/"candidate=on-disk"; state keeps
      "branch=missing")
    And no new subcommand, no new probe script, and no new process step
      was added

### Invariants
- The orchestrator never runs git beyond the embedded script's four
  subcommands, never runs any of the human follow-up commands, and never
  hardcodes an integration branch name.
- The follow-up print is print-only: it instructs the human and nothing in
  the prompt asks the orchestrator to execute it.
- Steps 2-4 (probe, classification, rejection routing) are untouched; the
  change adds no subcommand and no probe.
- The user-facing statement of the flow's position is honest: the prompt may
  state that the user is on "antz/<slug>" at release time only because
  ensure (per sub-spec "ensure") positions and re-positions the session on
  every invocation.
- The prompt keeps its fence shapes: the script remains the first
  3-space-indented bare fence, the probe the "```sh" fence.
