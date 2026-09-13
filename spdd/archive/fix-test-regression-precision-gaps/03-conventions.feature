# Change: fix-test-regression-precision-gaps — sub-spec 03 of 03 (the
# conventions suite's differs-fixture synthesizes the diff instead of
# reading the real HEAD).
#
# Fixes the test regression Change C (precision-gaps) left on master once
# committed: tests/conventions_test.sh's make_fixture_differs builds its
# "working copy differs from HEAD" fixture by writing the REAL repo's
# HEAD:agents/prompts/specifier.prompt into the fixture's commit and then
# copying the working specifier.prompt over it. With Change C committed,
# HEAD's copy already is the reworded working copy -- the fixture no longer
# differs, the gated retirements never trigger, and the two
# "..._when_copy_differs" tests fail (no loud retirement note where one is
# required).
#
# Fix: make_fixture_differs synthesizes the diff inside the fixture --
# copy the working tree (minus .git and spdd/, unchanged), commit the copy
# as-is as the fixture's one local commit, then mutate the fixture's
# working agents/prompts/specifier.prompt so it differs from the fixture's
# own HEAD -- reading nothing from the real repository's git HEAD. The
# retirement path ("cambio pendiente -> retiro ruidoso con nota") stays
# covered whether or not the change is committed. The mutation is a fixed,
# deterministic reword that no ungated assertion of either exercised suite
# pins (e.g. a line outside the specifier prompt's report/Output section),
# so the suites exit 0 with only the gated retirements firing.
#
# Scope: tests/conventions_test.sh only. The suites it exercises
# (tests/skills-activation-prompts_test.sh, tests/closingblock_test.sh) and
# agents/prompts/specifier.prompt are byte-unchanged by this sub-spec --
# the gates under test are already landed and correct.
#
# Declared destination domain: specifier-role.

Feature: conventions-04's differs-fixture synthesizes the diff inside the fixture, never from the real HEAD

  Background:
    Given "tests/conventions_test.sh" whose conventions-04 exercises
      prompts-05's specifier guard and closingblock-05's two diff-window
      assertions against throwaway git-repo fixtures under "mktemp -d" (the
      real repo is never committed to and nothing under the repo root is
      mutated)
    And git HEAD carrying the committed specifier-prompt rewordings, so a
      fixture built from the real HEAD can no longer differ from its
      working copy

  # MODIFY - conventions-04: the specifier diff-window pins stay retired by
  # gating, loudly -- and the differs-fixture is now synthesized inside the
  # fixture (commit the copy, then mutate the working copy), reading no
  # real HEAD, so the retirement path is covered post-commit too.
  Scenario: conventions-04
    When tests/conventions_test.sh runs -- whether the specifier-prompt
      rewordings are pending (uncommitted) or committed
    Then make_fixture_differs builds its fixture by copying the working
      tree (minus .git and spdd/), committing the copy as-is as the
      fixture's one local commit, and then mutating the fixture's working
      "agents/prompts/specifier.prompt" so it differs from the fixture's
      own HEAD -- reading no content from the real repository's git HEAD
    And the mutation is a fixed, deterministic reword touching only that
      fixture file, altering text no ungated assertion of either exercised
      suite pins (a line outside the specifier prompt's report/Output
      section), so every ungated assertion keeps passing
    And the two "..._when_copy_differs" tests pass in both repo states:
      prompts-05 stays registered and passes printing its loud retirement
      note, and both closingblock-05 assertions stay registered and pass
      printing their two loud retirement notes, with both exercised suites
      exiting 0 (only the gated retirements fire)
    And the byte-identical and degenerate fixtures keep their semantics
      without reading the real HEAD either: make_fixture_identical's
      fixture commits the copy as-is (the pin enforced quietly, no note),
      and make_fixture_no_bullet's fixture commits a copy lacking the
      closing-block bullet (the degenerate no-diff state check still fails
      it, with no note)
    And the working-suites test keeps keying its note expectation on the
      real tree's own pending state (notes expected exactly while the real
      specifier.prompt differs from HEAD)
    And every other assertion of both exercised suites keeps passing in
      every fixture

### Invariants
- The fixture builder reads no content from the real repository's git HEAD:
  the fixture's diff window is synthesized, so the retirement path is
  covered regardless of where the real HEAD sits.
- The fixture repositories are throwaways under "mktemp -d"; the real repo
  is never committed to and nothing under the repo root is mutated.
- The gates under test (prompts-05's specifier guard, closingblock-05's two
  assertions) are byte-unchanged by this sub-spec -- it changes only how
  the fixture that exercises them is built.
- No new diff-window assertion may be born ungated: any new working-vs-HEAD
  window assertion must carry a change_pending-style gate from birth.

## Out of scope
- The gates themselves (prompts-05's specifier guard, closingblock-05's two
  assertions) and their retirement notes -- already landed with Change C.
- The sluglimit and rolechecks suites (sub-specs 01 and 02).
- Any change to agents/prompts/specifier.prompt,
  tests/skills-activation-prompts_test.sh, tests/closingblock_test.sh,
  VERSION, or CHANGELOG.md.
