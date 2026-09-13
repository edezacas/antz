# Change: precision-gaps — sub-spec 05 of 05 (the mandated bump).
#
# The second-review note's mandatory minor bump: VERSION 4.5.0 → 4.6.0 with a
# matching CHANGELOG.md entry (Keep a Changelog format). Declared destination
# domain: versioning.

Feature: VERSION bumped to 4.6.0 with a matching CHANGELOG.md entry, graded minor

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.5.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.5.0] - 2026-09-12"

  # ADD - bump460-01: the bump is present.
  Scenario: bump460-01
    When the reader reads "VERSION"
    Then it reads exactly "4.6.0" (the version value plus one trailing
      newline, its only content) and agrees with the newest topmost CHANGELOG
      entry
    And "CHANGELOG.md" carries a dated "## [4.6.0] - <date>" section above
      "## [4.5.0]", in the file's Keep a Changelog style
    And the "## [4.6.0]" entry describes the precision-gap fixes: the
      specifier's conventions (the two-digit index from 01, one
      "e2e-qa.feature" per change dir, README sections per sub-spec with
      relevant files and the declared destination domain), the coder's
      mechanical checks (the literal-grep id search and the fixed plan
      threshold N=8), the verifier's mechanical "code present" criterion and
      per-domain spec-file rule with create-when-new, the orchestrator's
      bounded slug derivation, and the probe's convention-aligned id
      extraction with its test and spec updates
    And the "## [4.5.0]" section and every entry below it are byte-for-byte
      unchanged

  # ADD - bump460-02: the grade is minor, stated and justified.
  Scenario: bump460-02
    When the reader reads the "## [4.6.0]" entry
    Then it states the grade as minor, not patch and not major, naming the
      justification: role-prompt behavior changes (the specifier's
      conventions, the coder's threshold and search, the verifier's
      code-present and domain-file rules, the orchestrator's slug bullet) are
      changes to rendered agent bodies, and the probe's extraction behavior
      changes — not the wording-only patch
    And it names what survives unchanged (not major): the workflow contract,
      the "antz:generated" marker format, the access model, the directory
      layout, and the install locations
    And it states that "install.sh" itself is untouched and the bump reaches
      installed copies only through the normal "./install.sh --all"
      re-render, and that no role creates the "v4.6.0" tag (it is the human's
      commit-time follow-up, created against the bump commit and not pushed
      automatically)

### Invariants
- The versioning policy is unchanged: this bump follows the existing
  gradation, not a new rubric.
- No role commits anything; the v4.6.0 tag is the human's commit-time
  follow-up. If the human splits the work into several commits, each commit
  touching "agents/" and/or "install.sh" carries its own bump per the
  versioning rule — the modeled working-tree outcome is the single 4.6.0
  state above.
- A new self-contained suite "tests/bump460_test.sh" (one test per bump460
  id, mirroring "tests/bump440_test.sh"/"tests/bump450_test.sh" including
  their stacking-time-robustness gates) pins the bump.
- Earlier bump suites keep passing unmodified: their agreement-based checks
  survive the newer entry stacked on top.

## Out of scope
- Any change to "install.sh", "agents/meta/", or the versioning rule itself.
- Cambio D (style rewrite) and Cambio E (install.sh/docs hardening).
