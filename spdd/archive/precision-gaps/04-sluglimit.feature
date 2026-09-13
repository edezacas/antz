# Change: precision-gaps — sub-spec 04 of 05 (orchestrator slug derivation).
#
# Cambio C item 8 of docs/plan-revision-2026-09.md §3. The collision rule's
# ask-on-unclear-continuation half is already prompt law (the bullet survived
# fix-orchestrator-flow unchanged); the length-limit half lands here by
# stating the flow script's mechanical limit (landed in flow-script-guards,
# at most 40) where the slug is derived, replacing the undefined "short".
# Declared destination domain: flow-branch.

Feature: the orchestrator's slug derivation is bounded by the mechanical rule

  Background:
    Given "agents/prompts/orchestrator.prompt" step 1's slug-derivation
      bullet ("For new work: derive a short kebab-case slug ...")
    And the flow script's mechanical slug rule ("state=bad_slug"): lowercase
      letters, digits, and hyphen only; no leading/trailing or doubled
      hyphen; length at most 40
    And "spdd/specs/flow-branch.md" as the destination domain this sub-spec's
      scenarios merge into

  # ADD - sluglimit-01: the derivation states the length limit.
  Scenario: sluglimit-01
    When the reader reads the slug-derivation bullet
    Then it states the derived slug is at most 40 characters — the flow
      script's mechanical limit — in place of the undefined "short"
    And the intent holds: a derived slug passes the "state=bad_slug" gate
      rather than relying on the gate as a catch

  # ADD - sluglimit-02: the collision rules keep their pinned meaning.
  Scenario: sluglimit-02
    When the reader reads the slug-derivation bullet
    Then it keeps: suffixing ("-2", ...) only when the request continues an
      existing, already-claimed change, with the slug checked against
      "spdd/changes/", "spdd/archive/", and "git branch --list 'antz/*'" for
      collisions
    And it keeps: a semantically unclear continuation of an already-claimed
      slug stops and asks the user (the waiting-user slug-ambiguity stop,
      flow-07) — never a bare "-2" suffix without semantic continuation

### Invariants
- Only the derivation bullet changes in "agents/prompts/orchestrator.prompt";
  the ensure-state meanings, the four tables, the numbered steps ending at 6,
  the fence count, and the dedup guard's exactly-two exceptions keep their
  pinned content (flow-09, orchestrator-06).
- "scripts/orchestration/antz-flow.sh" is byte-unchanged (the mechanical rule
  already landed in flow-script-guards).
- The render-injection and prompts suites' orchestrator-prose gates
  self-retire with loud notes for this prose edit (the established
  mechanism) — no test edit is required for them.
- No role ever commits anything; the work stays uncommitted in the working
  tree.

## Out of scope
- Any change to the flow script's validation, the bad_slug vocabulary, or
  the latch/stop machinery (flow-branch's existing content).
- Cambio D (style rewrite) and Cambio E (install.sh/docs hardening).
