# Change: style-rewrite — sub-spec 02 of 07 (the coder's orphan bullets fold
# into "## Receipt" and the mirror clause is stated once).
#
# Implements the coder-side half of Cambio D (docs/plan-revision-2026-09.md
# §3): the two orphaned bullets after the "## Output" list in
# agents/prompts/coder.prompt (the receipt-naming bullet and the 100-130-word
# closing-block bullet, separated from the list by a blank line) fold into the
# "## Receipt" section they already belong to; the closing-block bullet is
# broken into a short list; and the Receipt section's closing statement stops
# restating the mirror clause. The closing-block vocabulary, the receipt
# grammar, and every machine-line format are unchanged — style only.
#
# Known intermediate red: after this sub-spec lands,
# tests/skills-activation-prompts_test.sh's prompts-06 coder-half pins ("never
# an input to any routing state or count" / "disk state" in the coder's
# "## Output" extract) fail until sub-spec 04 re-scopes them. This is the
# flow's normal mid-change state; no suite is left red at the change's end.
#
# Declared destination domain: receipts (the closing-block scenarios live in
# spdd/specs/receipts.md).

Feature: the coder's report-closing duty lives in "## Receipt", stated once and listed

  Background:
    Given "agents/prompts/coder.prompt" whose "## Output" section ends with a
      blank line followed by two orphaned bullets — the receipt-naming bullet
      ("Name the receipt file you wrote or updated...") and the
      100-130-word closing-block bullet with its nested parentheses — and
      whose "## Receipt" section closes with the classification statement
      that ends "this session's conversational report mirrors the receipt
      only — the receipt is what routes"
    And tests/closingblock_test.sh extracting the coder's report section by
      the "Output" heading and pinning the closing-block grammar, the
      vocabularies, and the mirror clause inside that extract

  # MODIFY - coder-01: the orphan bullets fold into "## Receipt"; the
  # closing-block bullet becomes a short list carrying every pinned string.
  Scenario: coder-01
    When the two orphan bullets move under the "## Receipt" heading (the
      blank-line orphan is gone; the "## Output" section keeps exactly the
      files-changed bullet and the skills bullet)
    Then the receipt-naming bullet keeps its content: the report body names
      the receipt file written or updated (see "## Receipt"), because the
      receipt is the classification authority on disk
    And the closing-block bullet is rewritten as a short list — one item per
      closing-block line plus the match rule — that keeps every pinned
      string: "closing block", "three consecutive lines", "`status=<value>`",
      "`ids=<id,id,...>`", "`results=<value>`", "grep-able", "`done`",
      "`blocked`", "your sub-spec's declared ids",
      "id=<id> result=<green|skip|blocked>", "mirroring your receipt",
      "in receipt order", "match", "exactly", "the disk receipt is the
      authority", "REJECTED.md", "status=blocked", "BLOCKED:", and "closes
      honestly"
    And the list still states the full duty: the results= tokens match the
      receipt's id lines exactly, a deviation between the block and the
      receipt is a bug absorbed by the bounded REJECTED.md retry, and a
      session that refused before touching the sub-spec still closes honestly
      with status=blocked and the BLOCKED: reason in the report prose
    And no item carries nested parentheticals deeper than one level — the
      100-130-word single sentence is gone

  # MODIFY - coder-02: the Receipt section's closing statement keeps the
  # classification-authority meaning and drops the variant restatement of the
  # mirror clause.
  Scenario: coder-02
    When the "## Receipt" section's final bullet is reworded
    Then it still states that the disk receipt is the classification
      authority — the orchestrator classifies sub-specs by reading receipts
      instead of running the unit suite
    And the variant restatements no longer appear anywhere in the prompt:
      "mirrors the receipt only" and "the receipt is what routes"

  # ADD - coder-03: the mirror clause is stated exactly once in the prompt.
  # (The fourth clause string, "never an input to any routing state or
  # count", is still duplicated by the skills-line tail at this sub-spec's
  # boundary — its once-per-prompt count is sub-spec 04's skillsline-03 pin,
  # verifiable once the tail is gone.)
  Scenario: coder-03
    When the whole of agents/prompts/coder.prompt is read
    Then each of these strings appears exactly once: "The block is a mirror
      only", "no routing, count, or decision ever derives from it", and "the
      receipt is the authority"
    And each single occurrence lives in the folded closing-block list under
      "## Receipt"

  # MODIFY - coder-04: the closingblock suite follows the fold loudly — the
  # coder's extract anchor moves to "## Receipt"; the receipts suite needs no
  # edit.
  Scenario: coder-04
    When tests/closingblock_test.sh is updated in the same change and runs
    Then the coder's report-section extract is keyed on the "Receipt"
      heading instead of "Output", so closingblock-01/02/03/04's coder checks
      read the folded list where the duty now lives, with the same required
      strings as before
    And the specifier, verifier, and orchestrator extracts are unchanged
    And tests/receipts_test.sh passes unmodified — its "## Receipt" extract
      requirements (the receipt grammar, the sentinel, the id lines) are all
      still satisfied by the section's retained prose, and its refusals
      ("record that honestly rather than leaving the line empty", "honestly
      undiscoverable") are still absent
    And both suites exit 0

### Invariants
- The closing-block vocabulary is unchanged: `status=` values (`done` |
  `blocked`), the ids= content, and the `id=<id> result=<green|skip|blocked>`
  token form are byte-stable.
- The receipt grammar is unchanged: exactly one `test_command=` line (or the
  literal `none` sentinel), one `id=` line per declared id, the in-place
  rewrite rule, and the planning-refusal receipt.
- Every machine-line format is unchanged (`test_command=`,
  `id=... result=... reason=...`).
- The mirror clause lives once, in the folded closing-block list; the skills
  line keeps its mandatory-reporting rule in "## Output" (its tail is
  sub-spec 04's edit).
- agents/prompts/specifier.prompt, agents/prompts/verifier.prompt,
  agents/prompts/orchestrator.prompt, agents/meta/*, install.sh, and
  scripts/orchestration/* are byte-unchanged by this sub-spec.

## Out of scope
- The skills-line tail removal and the skills-suite re-scope (sub-spec 04) —
  until then, prompts-06's coder half is the documented intermediate red.
- The verifier's and orchestrator's prose rewrites (sub-specs 03 and 05).
