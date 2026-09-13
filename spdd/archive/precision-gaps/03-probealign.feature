# Change: precision-gaps — sub-spec 03 of 05 (probe id extraction).
#
# Cambio C item 9 of docs/plan-revision-2026-09.md §3, with the
# second-review note: the probe's id-extraction regex is aligned with the
# specifier's convention (<feature> contains no hyphens) so it detects
# violations instead of tolerating them, and the two artifacts that fix the
# old tolerant extraction — tests/orchestrator-status-probe_test.sh and
# spdd/specs/receipts.md — are updated in this same change (the receipts.md
# update is this sub-spec's merge). Declared destination domain: receipts.

Feature: the probe's declared-id extraction matches the specifier's id convention

  Background:
    Given "scripts/orchestration/antz-probe.sh" extracting each sub-spec's
      declared scenario ids from the tag-comment first line above each
      "Scenario:"/"Scenario Outline:" line
    And the specifier's id convention: "<feature>" is one word (letters,
      digits, underscores — no hyphens or spaces) and "<index>" is digits
      (two zero-padded from 01 per conventions-01)
    And "spdd/specs/receipts.md" as the destination domain this sub-spec's
      scenarios merge into

  # ADD - probealign-01: the extraction's feature portion admits no hyphen.
  Scenario: probealign-01
    When the probe extracts a sub-spec's declared ids
    Then the extraction matches only convention-shaped ids — the feature
      portion before the final "-<index>" admits letters, digits, and
      underscores, no hyphen (shape "[A-Za-z][A-Za-z0-9_]*-[0-9]+")
    And every conforming id extracts exactly as before: multiple ids from one
      sub-spec ("api-1", "api-2"), a single id from another ("client-1"), a
      multi-line tag's id from its first line, and a "Scenario Outline:" tag
      like a plain "Scenario:" tag

  # ADD - probealign-02: a hyphenated feature tag is no longer tolerated
  # whole — the violation surfaces instead of being smoothed over.
  Scenario: probealign-02
    When a sub-spec's tag carries a hyphenated feature name ("user-profile-1")
    Then the probe reports only the trailing convention-shaped portion
      ("ids=profile-1") — the pre-change tolerant behavior (reporting
      "user-profile-1" whole) is gone
    And the violation surfaces downstream as an id mismatch: a receipt naming
      the whole hyphenated id reads as a foreign id (complete=no) instead of
      classifying done a sub-spec whose phantom id a convention-following
      coder can never satisfy
    And every other probe output is byte-unchanged: "open_questions=",
      "rejected_count=", the "change_dir=missing" short-circuit, and the
      "receipt= covered= complete= class=" fields with their mapping

  # ADD - probealign-03: the probe suite pins the aligned extraction — the
  # second-review-mandated test update, in this same change.
  Scenario: probealign-03
    Given "tests/orchestrator-status-probe_test.sh" currently pins the
      tolerant extraction ("a hyphenated feature name survives the extraction
      whole") and carries hyphenated-feature fixture ids
    When the probe's extraction is aligned by probealign-01
    Then the suite is updated in this same change: the hyphenated-feature
      test pins both sides — a conforming "userprofile-1" extracts whole, and
      "user-profile-1" yields "profile-1" — and the fixtures carrying
      hyphenated-feature ids ("command-install-01" in the multi-line-tag
      test, "picker-cmd-01" in the tag-crossref test) are updated so each
      pinned expectation is exactly what the aligned extraction reports while
      the test's own property (multi-line pickup; cross-reference
      non-extraction) keeps being exercised
    And the aligned-extraction assertions are added to the same
      self-contained suite, tagged with this sub-spec's probealign ids in
      their reported names
    And every other assertion of the suite keeps passing unchanged: the
      open-questions, rejection-count, receipt-field, empty-ids, and
      change-dir assertions

### Invariants
- The probe runs no tests and no git — tags and receipts are read as files
  (unchanged).
- The extraction's index portion stays one-or-more digits: the probe does not
  enforce the two-digit padding (that is the specifier's authoring rule,
  conventions-01), so pre-existing single-digit ids still extract.
- The receipt grammar and the complete/class mapping are byte-unchanged.
- "scripts/orchestration/antz-flow.sh" and
  "scripts/orchestration/antz-skills.sh" are byte-unchanged (the flow suite's
  byte-unchanged guard stays scoped to them).
- The second-review-mandated "spdd/specs/receipts.md" update is delivered by
  this sub-spec's merge: the declared-id contract thereupon states the
  extraction shape (a "<feature>" with no hyphens; the index untouched by the
  probe) and that a violating tag surfaces as a mismatch instead of a
  tolerated id.
- No role ever commits anything; the work stays uncommitted in the working
  tree.

## Out of scope
- Any change to the receipt grammar, the classification mapping, or the
  doubtful-receipt exception (the receipts domain's existing content).
- The specifier's or the coder's/verifier's conventions (conventions,
  rolechecks).
- Cambio D (style rewrite) and Cambio E (install.sh/docs hardening).
