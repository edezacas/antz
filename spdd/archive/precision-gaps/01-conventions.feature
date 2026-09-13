# Change: precision-gaps — sub-spec 01 of 05 (specifier prompt conventions).
#
# Cambio C items 1, 5 (specifier half), 6, and 7 of
# docs/plan-revision-2026-09.md §3, with the second-review notes (N=8 fixed
# belongs to rolechecks; here: the two-digit index, one e2e-qa.feature per
# change dir, the destination domain declared in README.md, relevant files in
# one section per sub-spec). Closes the specifier-side precision gaps.
# Declared destination domain: specifier-role.

Feature: the specifier's specification conventions are mechanically precise

  Background:
    Given "agents/prompts/specifier.prompt" carrying the "## Specification
      Rules", "## End-To-End QA Suite", and "## Output, written to
      `spdd/changes/<change-slug>/`" sections
    And "spdd/specs/specifier-role.md" as the destination domain this
      sub-spec's scenarios merge into
    And the readmefile pins holding today: the "## Output" section contains
      the literal string "README.md" exactly once (readmefile-02) and its
      overview bullet lists "relevant-files pointers" (readmefile-01)

  # ADD - conventions-01: the <index> of a scenario id is defined — two
  # zero-padded digits, sequential from 01 within the sub-spec.
  Scenario: conventions-01
    When the reader reads the "## Specification Rules" scenario-naming bullet
    Then it states that "<index>" is two zero-padded digits, sequential from
      01 within the sub-spec (the first scenario is "<feature>-01", the next
      "<feature>-02", and so on)
    And the rest of the bullet keeps its meaning: the one-word "<feature>"
      rule (letters, digits, underscores only — no hyphens or spaces), the
      tag-comment format with the id on its first line, and the rule that a
      tag's description never carries another scenario's id

  # ADD - conventions-02: the end-to-end QA suite is one file per change dir,
  # in the fixed file e2e-qa.feature — not one per feature.
  Scenario: conventions-02
    When the reader reads the "## End-To-End QA Suite" section
    Then its first bullet states the change carries exactly one end-to-end QA
      suite, written to the fixed file "e2e-qa.feature" in the change
      directory — one per change, not one per feature
    And the section keeps its operating rules: the suite operates at the UI
      with no internal API calls, CLI flags/QA commands are allowed only as
      UI affordances, and it specifies user-visible workflows, inputs,
      outputs, and observable states
    And the "One per feature" wording is gone

  # ADD - conventions-03: the relevant-files bullet becomes one section per
  # sub-spec, carrying that sub-spec's relevant files and its declared
  # destination domain.
  Scenario: conventions-03
    When the reader reads the "## Output" section's relevant-files bullet
    Then it states the relevant files found during investigation are written
      as one section per sub-spec in the overview file, each section carrying
      that sub-spec's relevant files (pointers only, not a code walkthrough)
      and its declared destination domain
    And it states a declared domain name is kebab-case
    And the bullet does not contain the literal string "README.md" — it
      refers to the overview file, whose fixed name the existing bullet
      already states exactly once (readmefile-01 and readmefile-02 stay green
      unmodified)
    And the overview bullet's own enumeration (goal, contract, shared
      contracts, invariants, out-of-scope, and relevant-files pointers) is
      byte-for-byte unchanged

  # ADD - conventions-04: the specifier diff-window pins are retired by
  # gating, loudly — the rewordings are legitimate.
  Scenario: conventions-04
    Given the specifier prompt rewordings of conventions-01..03 remove and
      re-add lines, so every pin that demands the file's diff vs HEAD be
      purely additive now misfires
    When the suites carrying those pins run
    Then "tests/skills-activation-prompts_test.sh"'s prompts-05 specifier
      guard retires by gating: when the working copy differs from HEAD it
      prints a loud retirement note and skips the closingblock-era
      additive-shape checks (the guard function stays registered, not
      deleted), and when the copy is byte-identical to HEAD the pin is still
      enforced
    And "tests/closingblock_test.sh"'s two closingblock-05 specifier
      diff-window assertions retire by gating the same way (a loud note when
      the copy differs from HEAD; the degenerate no-diff state check stays)
    And every other assertion of both suites keeps passing: the
      orchestrator-prose diff-shape checks (self-retiring via the
      prose-distinct gate), the no-role-level-"## Skills" boundary, the
      closing-block vocabulary and report tests, and the byte-untouched meta
      files

### Invariants
- Only the three bullets named above change in
  "agents/prompts/specifier.prompt"; every other line of the file is
  byte-unchanged by this sub-spec.
- The literal string "README.md" still appears exactly once in the
  "## Output" section, and "OVERVIEW.md"/"SUMMARY.md"/"NOTES.md" appear
  nowhere in it (readmefile-02/03 unmodified).
- Exactly one destination domain is declared per sub-spec — a sub-spec
  spanning two domains should be split (the verifier's file rule is
  rolechecks-04's).
- "agents/meta/*", "install.sh", and the other three role prompts are
  byte-unchanged by this sub-spec.
- No role ever commits anything; the work stays uncommitted in the working
  tree.

## Out of scope
- The coder's and verifier's mechanical checks (rolechecks), the probe's id
  extraction (probealign), the slug derivation (sluglimit), and the bump
  (bump460) — each is another sub-spec of this change.
- The style rewrite (Cambio D) and the install.sh/docs hardening (Cambio E)
  — explicitly not this change.
- Renaming the overview file or making its content conditional.
