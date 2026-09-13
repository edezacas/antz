# End-to-end QA suite for change hardening-installsh (Cambio E only).

Operates through the real product UI: install.sh's own CLI (its flags are a
UI affordance, not an internal API call -- the established convention of
spdd/specs/versioning.md's and spdd/specs/set-model.md's e2e suites), the
installed slash command typed in a live client session, and the repo's
policy docs read by a user. All scenarios tagged ADD; no prior e2e series
exists for this change, so ids start at 01.

  Background:
    Given a local checkout of the antz repo with the change applied
      ("install.sh", "README.md", "AGENTS.md", "CLAUDE.md", "VERSION",
      "CHANGELOG.md" all at their post-change state)
    And isolated HOME directories for every scenario, so QA never touches
      the real "~/.claude" or "~/.config/opencode"

  # ADD - e2e-qa-01: a fresh install carries the header marker everywhere
  # and quotes every description -- the change's two render-side outcomes,
  # visible in the user's own installed files.
  Scenario: e2e-qa-01
    When the user runs "./install.sh --all" with HOME set to an isolated
      empty directory
    Then the exit status is 0 and the report lists all twelve installs
      (4 agents x 2 clients, plus 2 antz.md and 2 antz-set-model.md
      commands) under that HOME
    And every installed file's frontmatter carries the marker line
      "# antz:generated version=4.7.0 -- do not edit by hand; regenerate
      with install.sh" as a line-start header comment
    And every installed file's frontmatter description line is a
      double-quoted scalar (starts `description: "`, ends `"`)

  # ADD - e2e-qa-02: the closed hole, seen from the user's seat: their own
  # same-named agent file that merely mentions "antz:generated" in its
  # body is backed up before being overwritten, while a genuinely
  # antz-generated file is overwritten in place with no backup.
  Scenario: e2e-qa-02
    Given the user's own hand-written agent exists at
      "~/.claude/agents/antz-coder.md" whose body prose contains the text
      "antz:generated" but no line-start header marker
    When the user runs "./install.sh --claude"
    Then a backup "~/.claude/agents/antz-coder.md.bak.<timestamp>" exists
      and holds the user's original content byte-for-byte
    And "~/.claude/agents/antz-coder.md" is now the managed render
    And the console output stated the file was backed up as not
      antz-managed
    When the user runs "./install.sh --claude" again
    Then the managed file is overwritten in place and no new backup is
      created for it

  # ADD - e2e-qa-03: the backup policy is observable: install.sh never
  # touches backups it finds -- they survive re-runs byte-for-byte under
  # their original names, and cleaning them up is the user's job.
  Scenario: e2e-qa-03
    Given e2e-qa-02's backup "antz-coder.md.bak.<timestamp>" exists
    When the user runs "./install.sh --claude" twice more
    Then the backup still exists, byte-for-byte unchanged, under its
      original name
    And no additional backup for antz-coder.md exists (the destination is
      antz-managed now)
    And the user deletes the backup themselves and install.sh recreates
      none of it on the next run

  # ADD - e2e-qa-04: the quoted frontmatter and /antz-set-model keep
  # working together: a model configured on a quoted-description agent
  # file lands at the fixed frontmatter position and the reply confirms
  # it.
  Scenario: e2e-qa-04
    Given the fresh install of e2e-qa-01
    When the user, in a Claude Code session, runs "/antz-set-model --agent
      coder --model opus"
    Then "~/.claude/agents/antz-coder.md" contains the line "model: opus"
      immediately after its quoted "description:" line and immediately
      before its "tools:" line
    And the quoted description line is byte-for-byte unchanged
    And the reply confirms antz-coder now has "model: opus"

  # ADD - e2e-qa-05: the tag-pin surface, user-visible: the documented
  # ANTZ_REF invocation exists in README and install.sh's header, and a
  # local-checkout install is unaffected by the variable (no fetch is
  # ever attempted, proven by a failing curl stub that would abort any).
  Scenario: e2e-qa-05
    When the user reads README.md's install section and install.sh's
      header usage comment
    Then both document installing from a tag: fetch install.sh from the
      tag's raw URL and pass ANTZ_REF=<tag> to sh
    Given a failing curl stub earlier on PATH (any fetch attempt aborts
      the install loudly)
    When the user runs "./install.sh --all" from the checkout with
      ANTZ_REF=bogus-ref and HOME set to a fresh isolated directory
    Then the install succeeds reading every file from the checkout, the
      stub is never invoked, and the rendered files match the staged
      tree's content

  # ADD - e2e-qa-06: the docs tell the truth about spdd/: the Structure
  # bullet describes the real state, identically in both policy docs, and
  # the false "not present yet" claim is gone.
  Scenario: e2e-qa-06
    When the user opens AGENTS.md and CLAUDE.md
    Then each file's "spdd/" Structure bullet states the three directories
      exist in the checkout -- spdd/changes/ holding in-flight changes
      (empty between flows), spdd/specs/ holding the governing per-domain
      specs, spdd/archive/ holding the archived changes -- and states who
      creates what
    And the bullet is byte-identical between the two files
    And neither file claims anywhere that "spdd/specs/" or
      "spdd/archive/" do not exist yet

  # ADD - e2e-qa-07: the bump is visible through install.sh's own update
  # report: copies marked 4.6.0 report the drift to 4.7.0 with the new
  # changelog entry, and --all re-renders them at 4.7.0.
  Scenario: e2e-qa-07
    Given an isolated HOME seeded with installed copies of every agent
      and command file whose header markers read version=4.6.0
    When the user runs "./install.sh --check"
    Then the exit status is 0 and no file under that HOME changes
    And the report reads "Claude Code: antz 4.6.0 -> 4.7.0" and "OpenCode:
      antz 4.6.0 -> 4.7.0"
    And the report prints the "## [4.7.0]" CHANGELOG entry
    When the user runs "./install.sh --all"
    Then every installed file is re-rendered and marked
      "antz:generated version=4.7.0", with quoted description lines
    And a fresh "./install.sh --check" reports "already up to date (antz
      4.7.0)" for both clients
