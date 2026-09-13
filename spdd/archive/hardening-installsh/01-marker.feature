# Domain: install-render (new)

## Feature: Header-anchored antz:generated marker detection and the .bak.<ts> backup policy

  Background:
    Given the repo's "install.sh"
    And the marker line install.sh renders into every installed file's
      frontmatter reads "# antz:generated version=<X.Y.Z> -- do not edit by
      hand; regenerate with install.sh" -- a line-start header comment whose
      format is unchanged by this change
    And an isolated HOME with staged destination paths, never the real
      "~/.claude" or "~/.config/opencode"

  # ADD - marker-01: the managed-file overwrite-in-place behavior is
  # preserved under the anchored detection: a destination whose content
  # carries the marker as a line-start header comment is recognized as
  # antz-managed and overwritten in place with no backup.
  Scenario: marker-01
    Given a destination file whose frontmatter carries the marker line
      "# antz:generated version=1.2.3 -- do not edit by hand; regenerate
      with install.sh" at line start
    When install.sh installs a generated file at that destination
    Then the destination is overwritten in place with the new render
    And no ".bak.<timestamp>" file is created for it

  # ADD - marker-02: the hole is closed: detection is anchored to the
  # line-start header comment ("grep -q '^# antz:generated '" shape), so a
  # file that merely mentions "antz:generated" anywhere else -- mid-line,
  # mid-body, indented, inside prose or a string -- is NOT recognized as
  # antz-managed and is backed up before being overwritten, exactly like
  # any other unmanaged file.
  Scenario: marker-02
    Given a destination file that is not antz-generated and whose content
      mentions the text "antz:generated" only somewhere other than a
      line-start header comment (for example inside its body prose)
    When install.sh installs a generated file at that destination
    Then the pre-existing file is backed up to "<destination>.bak.<timestamp>"
      holding the original content byte-for-byte
    And the destination is then overwritten with the fresh managed render
    And the console output states the file was backed up as not
      antz-managed

  # ADD - marker-03: installed_version_of reads the embedded version only
  # from the line-start header comment, so a stale version mentioned in a
  # file body can no longer pass as the installed version. The "--check"
  # report classifies such a file as a fresh install rather than "already
  # up to date".
  Scenario: marker-03
    Given the installed specifier agent file for a client carries no
      line-start header marker, but its body contains the text
      "antz:generated version=9.9.9"
    When the user runs "./install.sh --check"
    Then that client's report says the antz copy is a fresh install of the
      current VERSION, not "already up to date (antz 9.9.9)"
    And a file whose frontmatter does carry the line-start header marker
      still reports the version embedded in that header comment

  # ADD - marker-04: the .bak.<ts> policy, as behavior: a backup is created
  # exactly when the destination exists and does not carry the line-start
  # header marker; backups are never read, rewritten, renamed, or deleted
  # by install.sh, and re-runs over managed files create none. Accumulated
  # backups are left exactly as the user left them.
  Scenario: marker-04
    Given a destination with two pre-existing backups from earlier runs,
      "<destination>.bak.20260101010101" and "<destination>.bak.20260202020202"
    When install.sh runs twice in a row against a managed destination
    Then no new backup is created by either run
    And both pre-existing backups survive byte-for-byte under their
      original names
    And a run against an unmanaged destination still creates exactly one
      backup named "<destination>.bak.<YYYYMMDDHHMMSS>" of the content it
      overwrites

  # ADD - marker-05: the .bak.<ts> policy, as documentation: install.sh's
  # header comment states the policy -- backups exist so no overwritten
  # user content is ever lost, install.sh never prunes them automatically,
  # and cleaning them up is the user's job.
  Scenario: marker-05
    When the reader reads install.sh's header comment
    Then it states that pre-existing unmanaged files are backed up as
      "<file>.bak.<timestamp>" before being overwritten
    And it states that install.sh never deletes or prunes those backups
      automatically -- accumulating them is accepted and their cleanup is
      the user's

  # ADD - marker-06: the header comment is completed: the opening sentence
  # names all four installed agents (specifier, coder, verifier, AND
  # orchestrator) and both installed commands (/antz and /antz-set-model),
  # not just the three older roles.
  Scenario: marker-06
    When the reader reads install.sh's header comment
    Then its description of what gets installed names antz-specifier,
      antz-coder, antz-verifier, and antz-orchestrator
    And it names the /antz command and the /antz-set-model command among
      what install.sh installs

### Invariants
- The marker constant ("antz:generated") and the rendered marker line's
  format are unchanged -- only the detection is anchored. The versioning
  gradation therefore stays minor (detection logic), never major (the
  marker format survives).
- The backup trigger condition sharpens to the anchored header marker;
  every destination that legitimately carried the header marker before
  this change keeps being overwritten in place with no backup.
- The set-model command's install-side backup behavior
  (command-install-04 in spdd/specs/set-model.md) keeps passing unchanged:
  its fixture carries no marker at all.
- Tests/renderinject_test.sh's renderinject-06 pins every header line
  except the tracked-set sentence byte-identical to the base tree. This
  sub-spec (the change's first header-editing sub-spec) retires that
  byte-identity window with the repo's loud-note convention, so the
  legitimate header edits here and in the refpin sub-spec do not fail the
  suite; the tracked-set sentence assertion itself stays enforced.
- install.sh stays parseable POSIX sh (posixsh-01..03 stay green).

## Out of scope
- Any change to the marker line's rendered format, the VERSION embedding,
  or the --check machinery beyond the anchored version read.
- Automatic pruning, capping, or rotation of ".bak.<timestamp>" files
  (the decided policy is the opposite: never auto-delete; document).
- The /antz-set-model embedded script's marker check and temp-file trap --
  owned by the setmodel sub-spec (04), which consumes the header-marker
  contract defined here.
- Any change to agents/prompts/ or agents/meta/.
