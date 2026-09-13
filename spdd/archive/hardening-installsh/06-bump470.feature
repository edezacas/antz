# Domain: versioning (existing; the bump440/450/460 precedent)

## Feature: VERSION bumped to 4.7.0 with a matching CHANGELOG.md entry describing the install.sh hardening, graded minor

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.6.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.6.0] - 2026-09-13"

  # ADD - bump470-01: the bump is present -- VERSION reads 4.7.0 and
  # CHANGELOG.md gains a matching [4.7.0] section above [4.6.0],
  # describing the change's substance: the header-anchored marker
  # detection (three sites: install_file, installed_version_of, the
  # /antz-set-model embedded script) closing the overwrite-without-backup
  # hole; the quoted description frontmatter (render_claude,
  # render_opencode, render_set_model_command); the ANTZ_REF ref pinning
  # replacing the hardcoded master RAW_BASE; the embedded script's
  # temp-file cleanup trap; the stated .bak.<ts> policy and the completed
  # install.sh header; and the AGENTS.md/CLAUDE.md spdd/ state-line fix.
  Scenario: bump470-01
    When the reader reads "VERSION"
    Then it reads exactly "4.7.0" (the version value plus one trailing
      newline, its only content) and agrees with the newest topmost
      CHANGELOG entry
    And "CHANGELOG.md" carries a dated "## [4.7.0] - <date>" section above
      "## [4.6.0]", in the file's Keep a Changelog style (category
      headings with bold lead-in bullets)
    And the "## [4.7.0]" entry describes each of: the header-anchored
      marker detection at the three sites and the backup-before-overwrite
      hole it closes; the quoted description scalars at the three render
      sites; the ANTZ_REF ref derivation replacing the hardcoded master
      (a tagged install no longer reads master content); the embedded
      script's mktemp cleanup trap; the stated .bak.<ts> policy and the
      header completion (orchestrator and commands named); and the
      AGENTS.md/CLAUDE.md "not present yet" correction
    And the "## [4.6.0]" section and every entry below it are byte-for-byte
      unchanged

  # ADD - bump470-02: the grade is minor, stated and justified against the
  # versioning table -- and no tag is created by any role.
  Scenario: bump470-02
    When the reader reads the "## [4.7.0]" entry against the versioning
      gradation
    Then the change grades as "minor": install.sh's detection logic and
      rendered output both change (anchored marker detection, quoted
      descriptions, ANTZ_REF-driven fetch URLs), which the gradation
      reserves for minor, not patch (not wording-only)
    And it does not grade as "major": the workflow contract, the
      "antz:generated" marker format, the access model, the directory
      layout, and the install locations are all unchanged -- the marker
      line's shape, the flags, the frontmatter field set, and the install
      paths all survive, so no consumer breaks
    And it states that "agents/prompts/" and "agents/meta/" are untouched
      and no role creates the "v4.7.0" tag: the local tag is the human's
      commit-time follow-up, created against the human's bump commit and
      not pushed automatically

### Invariants
- The versioning policy is unchanged: this bump follows the existing
  gradation (detection logic + rendered output = minor), not a new rubric.
- No role commits anything; the v4.7.0 tag is the human's commit-time
  follow-up.
- The earlier bump suites' install.sh-untouched guards (bump440/450/460)
  retire vacuously on their own change_pending gates once HEAD carries
  their entries -- they need no edit from this change.
- The new bump suite follows the tests/bump460_test.sh pattern: VERSION
  asserted as semver agreeing with the newest topmost entry (never a
  cross-change pinned literal), the [4.6.0]-down tail pinned byte-identical
  to git HEAD.

## Out of scope
- Any change to the versioning policy docs (the "## Versioning" sections
  are byte-identical before and after).
- Retroactive entries or tags for past changes.
- Tag creation or push by any role.
