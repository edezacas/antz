# Change: orchestrator-fast-path — sub-spec 04 (orchestrator prose, patch)
#
# Two session-level guards added to agents/prompts/orchestrator.prompt as
# prose law (no script, no probe field, no new subcommand):
#   (a) dedup — the orchestrator never delegates the same (sub-spec, role)
#       pair twice within one orchestrator invocation;
#   (b) latch — after any stop, no further delegation of any kind in that
#       same session.
#
# Resolved decision (recorded here, not an open question): the dedup guard
# has exactly one carve-out — step 4's bounded-retry relay (rejected_count=1
# relays each attributable blocker to the coder session for the sub-spec it
# names, "unconditionally" per the current prompt). Reaching step 4 in one
# session necessarily means that pair (sub-spec, coder) was already
# delegated earlier in the same session, so a literal no-second-delegation
# rule would defeat the bounded retry the request explicitly preserves
# ("The bounded REJECTED.md retry continues to absorb any deviation"). The
# relay is therefore the single permitted second delegation of a pair, and
# it stays bounded by the existing REJECTED.md machinery (at most one relay
# per pair per entry; rejected_count=2 stops the flow for good).
#
# Both guards are prompt-level law, like the existing never-delegate-outside-
# the-three-roles rule: not tool-enforced on every client, binding regardless
# of what the tool grant technically allows.

Feature: sessionguards — dedup and latch govern one orchestrator session's delegations

  Background:
    Given "agents/prompts/orchestrator.prompt"'s Process sections: step 3
      classifies sub-specs and delegates in-progress ones to fresh coder
      sessions, step 4 routes on rejected_count, and every stop-and-report
      outcome ends the invocation's work

  # ADD - sessionguards-01: the dedup law, stated in the Process (or an
  # adjacent guards section) of the prompt.
  Scenario: sessionguards-01
    When the reader reads "agents/prompts/orchestrator.prompt"
    Then it states that within one orchestrator invocation the same
      (sub-spec, role) pair is never delegated twice: once a pair has been
      delegated, later flow steps route by the existing state machine
      (fresh classification from disk, the bounded retry, the stops) and
      never by re-delegating that pair
    And it states the single carve-out: step 4's bounded-retry relay of
      attributable blockers to the named sub-spec's coder session is the
      one permitted second delegation of a pair, still bounded by
      REJECTED.md (at most one relay per pair per entry; a second entry
      stops the flow for good)

  # ADD - sessionguards-02: the latch law — any stop freezes all further
  # delegation in that session.
  Scenario: sessionguards-02
    When the reader reads "agents/prompts/orchestrator.prompt"
    Then it states that after any stop-and-report outcome the session
      performs no further delegation of any kind, reporting and ending
      instead, with resumption always a fresh invocation
    And the stop outcomes it names include at least: "open_questions=yes";
      the flow script's machine-line stops ("state=no_git", "state=no_repo",
      "state=no_commits", "state=checkout_refused", "state=no_branch",
      "branch=missing", "change_dir=missing", "gate=refused reason=...");
      a "BLOCKED:"-reasoned sub-spec found in classification;
      "rejected_count=2"; a non-attributable blocker in a rejected entry;
      and a slug-ambiguity stop (no unambiguous on-disk candidate)

  # ADD - sessionguards-03: the guards are pure prose law — no new
  # machinery, nothing written to disk.
  Scenario: sessionguards-03
    When the implementation of this sub-spec is inspected
    Then the guards are stated in the prompt's prose only — no new embedded
      or extracted script, no new flow subcommand, no new probe field, and
      no file under "spdd/" records delegation history for them
    And the session's own account of the delegations it already made is the
      mechanism the prompt instructs it to apply

  # ADD - sessionguards-04: everything else in the prompt keeps its meaning.
  Scenario: sessionguards-04
    When the reader compares the prompt before and after this sub-spec
    Then the step ordering, the discover/state tables, the classification
      rules, the rejection routing, the release handling, and the Report
      Format keep their existing meaning
    And the guards add constraints only (forbidding duplicate and
      post-stop delegations), never re-routing an existing outcome

### Invariants
- The guards bind regardless of the client's tool grant (prompt-level law,
  same standing as the never-delegate-outside-the-three-roles rule).
- The latch covers delegation only: the orchestrator's own read-only
  probing (re-running the flow/probe scripts) is unchanged, since state
  reconstruction from disk is every invocation's starting duty.
- Dedup is per (sub-spec, role) pair per invocation: a later orchestrator
  invocation starts with a clean slate and may delegate the same pair
  again (resume is a fresh session, per the latch's resumption rule).

## Out of scope
- Any change to the embedded/extracted scripts or install.sh (sub-specs
  01–03).
- Any change to the rejection machinery's own bounds (REJECTED.md's
  bounded retry is preserved exactly).
- A machine-readable delegation ledger under spdd/ (deliberately not
  introduced; disk state stays role-artifact-owned).

## Relevant files
- "agents/prompts/orchestrator.prompt" — the dedup and latch law in the
  Process (or an adjacent guards subsection), plus the step-4 carve-out.
- "spdd/specs/flow-branch.md" — the orchestrator feature this sub-spec
  extends (its scenarios stay valid; the guards are additive).
