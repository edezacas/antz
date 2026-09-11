# Domain: description-keyed match narrowing in the orchestrator's
# antz-skills.sh snippet (descmatch layer)

## Goal
Close the implementation caution recorded in `spdd/specs/skills-activation.md`
("Implementation caution (verifier, 2026-09-11)"): the `antz-skills.sh`
snippet embedded in `agents/prompts/orchestrator.prompt` lowercases and
greps the ENTIRE YAML frontmatter block (`desc_l=$(printf '%s\n' "$fm" | lc)`),
while the already-merged contract (prompts-02, orchestrator-02) keys
matching to the skill's **description** only. Verified against the real
`~/.agents/skills/` tree on 2026-09-11: the keyword `apache` (which lives
only in `license: Apache-2.0` of angular-conventions and init-project) and
`edezacas` (only in their `metadata:`) each list those skills today — false
positives that can displace a genuinely matching skill given the cap of 5.
The fix narrows the lowercased match text to the `description:` field's
content, correctly handling multi-line YAML block scalars (`description: >`
/ `>-` with indented continuation lines — real skills omarchy and
diagnose-crash use this style; a naive line-only extraction returns just
">" and would make those skills unmatchable, so the extraction must
accumulate indented continuation lines until the next top-level key or the
end of the frontmatter). This is a patch-grade implementation fix: the
rendered prose is already description-keyed, the merged spec text does not
change, only the snippet's code is aligned to it.

## Shared contracts
The snippet's output contract is unchanged and stays identical across the
layers: same `skill=<name> path=<absolute SKILL.md path> matched=<kw,...>`
lines, same explicit `Skills: none matched` line, same cap of five with the
alphabetical tie-break, same temp-file POSIX sh convention. The delegated
sessions (coder/verifier prompts) and the docs gotcha consume the block
unchanged. Only the matching text source inside the snippet changes.

## Feature: matching is keyed to the description field only, with block-scalar support

  Background:
    Given the embedded antz-skills.sh snippet inside
      "agents/prompts/orchestrator.prompt", extracted marker-to-fence and
      run as POSIX sh ("sh <tempfile> <working-root> <keyword> ...")
    And a temp skills tree with fixture SKILL.md files whose frontmatter
      carries the fields named in each scenario
    And the output contract of the snippet is unchanged: the same
      "skill=<name> path=<path> matched=<kw,...>" lines, the same
      "Skills: none matched" line, the same cap of five with the
      alphabetical tie-break, and case-insensitive keyword matching

  # MODIFY - descmatch-01: matching is keyed to the description field only —
  # a keyword that appears only in the frontmatter name: no longer matches.
  # This is the point of the fix (the defect per the recorded caution).
  Scenario: descmatch-01
    Given a fixture skill whose "name:" field contains the keyword
      "searchtool" and whose "description:" field is a single line that
      does not contain it ("Reads configuration files.")
    When the snippet is run with the keyword "searchtool"
    Then the output is exactly "Skills: none matched" (exit 0)
    When the snippet is run with the keyword "configuration"
    Then that same skill is listed with "matched=configuration" and its
      absolute SKILL.md path — description hits still match exactly as
      before

  # ADD - descmatch-02: multi-line YAML block scalars are matched — the
  # extraction accumulates indented continuation lines of the description
  # until the next top-level key or the end of the frontmatter, so a
  # keyword living only in a continuation line matches. Verified today:
  # a naive line-only extraction returns just ">" for the real omarchy and
  # diagnose-crash skills (both use "description: >") and would make them
  # unmatchable.
  Scenario: descmatch-02
    Given a fixture skill whose frontmatter reads
      "description: >" followed by indented continuation lines, with the
      keyword "keybinding" appearing only on a continuation line
    When the snippet is run with the keyword "keybinding"
    Then that skill is listed with "matched=keybinding"
    Given a second fixture skill using the folded-strip style
      "description: >-" with the keyword "segfault" only in a continuation
      line
    When the snippet is run with the keyword "segfault"
    Then that skill is listed with "matched=segfault"
    Given a third fixture skill whose description block scalar is followed
      by a later top-level key ("license: Apache-2.0") and whose
      continuation lines end before it
    Then the extraction stops at the next top-level key: the description
      text contains neither the ">" indicator line nor any text after the
      "license:" key, so "license" as a keyword does not match that skill
    And the skill body below the closing "---" fence is still never matched
      (the pre-existing body-never-read invariant keeps holding)

  # ADD - descmatch-03: other frontmatter keys are excluded from matching —
  # the false positives verified on the real tree (keyword "apache" only in
  # "license: Apache-2.0"; keyword "edezacas" only in "metadata:" author)
  # become no-matches. Real-tree positives are pinned by e2e-01; these
  # fixture scenarios are the deterministic unit-level twins.
  Scenario: descmatch-03
    Given a fixture skill whose frontmatter carries
      "license: Apache-2.0" and a "metadata:" block (author, version) and
      whose description does not mention them
    When the snippet is run with the keyword "apache"
    Then the output is exactly "Skills: none matched"
    When the snippet is run with the keyword "edezacas"
    Then the output is exactly "Skills: none matched"
    When the snippet is run with a keyword that appears in that skill's
      description
    Then the skill is listed with that keyword as its match reason

  # MODIFY - descmatch-04: scope of the edit — only the lines inside the
  # antz-skills.sh fenced snippet change; the prose is already
  # description-keyed and stays byte-for-byte, and no other tracked file
  # moves. (Verified today: the orchestrator prose bullet already says it
  # "reads only each candidate SKILL.md's YAML frontmatter name:/description:
  # fields, and matches case-insensitively against its description"; the
  # AGENTS.md/CLAUDE.md skills gotcha is byte-identical between the two
  # files and stays truthful.)
  Scenario: descmatch-04
    When the diff of "agents/prompts/orchestrator.prompt" against the
      pre-change tree is inspected
    Then every changed line lies inside the antz-skills.sh fenced snippet
      (between the fence that follows the "# antz-skills.sh" marker comment
      and the closing fence)
    And the derivation prose bullets (the "## Skills to load before work"
      duty, the derivation-keywords bullet, the none-matched shape, the
      match-reason shape, the temp-file convention bullet) are
      byte-for-byte unchanged
    And "agents/prompts/specifier.prompt", "agents/prompts/coder.prompt",
      "agents/prompts/verifier.prompt", "agents/meta/" (all four),
      "install.sh", "AGENTS.md", and "CLAUDE.md" are byte-for-byte
      unchanged

  # MODIFY - descmatch-05: the runtime tests evolve with the fix —
  # tests/orchestrator-skills-block_test.sh's fixtures/expectations are
  # description-keyed already (its fixtures put keywords only in
  # descriptions, so cap/tie-break/none-matched assertions stay green), but
  # its additive-vs-HEAD guard on orchestrator.prompt would now fail (the
  # snippet lines change), so that guard is scoped to exclude the snippet,
  # and the new negative/block-scalar behavior is encoded as unit tests
  # carrying the descmatch-01..03 ids in their reported test names.
  Scenario: descmatch-05
    When "tests/orchestrator-skills-block_test.sh" is run directly
    Then it passes, reporting every pre-existing test (orchestrator-01..04
      block/derivation/matching/none-matched/constraint tests and the
      body-never-read invariant) as still passing with the fixed snippet
    And it reports new tests embedding the ids "descmatch-01", "descmatch-02",
      and "descmatch-03" covering the name-only negative, the block-scalar
      positives, and the license/metadata exclusions
    And its orchestrator.prompt additive-vs-HEAD guard no longer asserts
      that no lines were removed repo-wide: removed lines are permitted only
      inside the antz-skills.sh fenced snippet, and the guard still fails if
      any line outside it is removed
    And the snippet still parses as POSIX sh ("sh -n") in the constraint
      test

  ### Invariants
  - The output contract is unchanged: line shapes, "Skills: none matched"
    (exit 0), cap of five, alphabetical-by-name tie-break, best-score-first
    ordering, per-entry match reasons, case-insensitive matching.
  - The derivation stays stateless: nothing written to disk, no registry,
    nothing under "spdd/", no cache; re-derived fresh per run.
  - The orchestrator still never reads or follows a SKILL.md's instructions:
    only frontmatter name/description data is parsed; skill bodies are
    never matched.
  - The snippet remains a temp-file-executed POSIX sh snippet embedded in
    the prompt — no installed CLI, hook, or plugin.
  - No role commits anything; the human's follow-ups are unchanged.
  - The descmatch fix does not touch "spdd/specs/skills-activation.md"
    itself: the merged contract text was already description-keyed; only
    the implementation drifts back onto it.

## Out of scope
- Any change to role prompt prose (the prose already says
  description-keyed), to "AGENTS.md"/"CLAUDE.md" (the gotcha stays
  truthful), to "install.sh", or to "agents/meta/*".
- YAML coverage beyond what real skills use: plain single-line
  descriptions and folded block scalars (">" / ">-"). Literal ("|")
  descriptions, quoted multi-line values, anchors/aliases, and exotic YAML
  are not required to match (a non-matching description can only under-
  include, never falsely match).
- Any change to the cap, tie-break, output shapes, directories enumerated,
  or the delegation-block duty itself (all pinned by orchestrator-01..04 in
  "spdd/specs/skills-activation.md").
- Authoring or editing any real skill; the "worktree" branch variant.
