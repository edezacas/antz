# Change: fix-orchestrator-flow — sub-spec 01 (flow: the specifier delegation,
# the dedup carve-outs, disk-based verifier-outcome detection, waiting-user)
#
# Plan items 1.1, 1.2, 1.3 and 1.5 of docs/plan-revision-2026-09.md §3 Cambio A.
#
# Layer: agents/prompts/orchestrator.prompt's prose — step 1's post-ensure
# routing, step 2's probe-table row for change_dir=missing, the Session guards
# (dedup carve-outs, latch wording), step 5's outcome detection, the Report
# Format's status vocabulary — plus one historical-record row in
# docs/orchestrator.md. No script changes: scripts/orchestration/antz-flow.sh
# and antz-probe.sh are byte-unchanged; change_dir=missing stays a probe
# output and release keeps its exact machine lines — only the orchestrator's
# routing on them changes.
#
# Edit-shape constraints (the existing suites pin them and must stay green):
# the specifier delegation folds into the existing steps 1–2 without
# renumbering (the numbered steps still end at 6) and without adding any
# fenced block (still 14 fence lines across 7 blocks, exactly one ```sh); the
# four tables survive; every stop outcome the latch names stays named,
# including change_dir=missing; step-1's state meanings and step-5's human
# follow-up print keep their pinned strings. The prompt-prose diff guards vs
# HEAD self-retire with a loud note when the prose changes (the established
# gate), so rewording outside the three script fences is permitted; the
# structural assertions stay enforced.
#
# All scenarios are ADD against spdd/specs/flow-branch.md (the orchestrator
# flow domain): no existing scenario id there is modified — this sub-spec
# amends the flow's behavior with new, additive ids.

Feature: the orchestrator routes a never-specified flow to the specifier, detects verifier outcomes from disk, and defines its stop vocabulary

  Background:
    Given "agents/prompts/orchestrator.prompt" as published before this
      change, carrying step 1's discover/ensure instructions, step 2's probe
      output table, the Session guards, steps 3–6, and the Report Format
    And the flow scripts unchanged: "scripts/orchestration/antz-flow.sh"
      (discover/ensure/state/release) and "scripts/orchestration/antz-probe.sh"
      (change_dir=missing short-circuit, open_questions=, rejected_count=,
      subspec= lines with their receipt fields)

  # ADD - flow-01: after ensure, a never-specified flow delegates the whole
  # change to the specifier, then re-probes and continues through the
  # unchanged state machine.
  Scenario: flow-01
    When the reader reads the routing that follows `ensure` in steps 1–2
    Then a `change_dir=missing` probe outcome routes by the directories that
      exist on disk: when neither "spdd/changes/<slug>/" nor
      "spdd/archive/<slug>/" exists, the flow was never specified — this
      covers both a `state=created` flow and the branch-only `state=reused`
      candidate that never wrote anything
    And in that case the orchestrator delegates the whole change to the
      `specifier` (which creates the change dir by authoring the sub-specs),
      carrying the standard delegation message: the "Working root" and
      "Change slug" lines plus the "## Skills to load before work" block,
      identical in shape to every other delegation
    And the orchestrator then re-probes (re-runs step 2's `state` subcommand)
      and continues through the unchanged state machine from its fresh output
      — classification (step 3) onward
    And the Report Format's `delegated-specifier` status is produced by this
      step: the closing block of an invocation that stopped here reads
      "status=delegated-specifier"
    And the specifier is delegated at most once per invocation

  # ADD - flow-02: change_dir=missing with an on-disk candidate at discover
  # time means the change dir was deleted mid-session — a hard stop.
  Scenario: flow-02
    When the reader reads the same routing
    Then a `change_dir=missing` probe outcome stops and asks the user
      instead — never delegating the specifier — when this invocation's
      `discover` listed an on-disk candidate for this slug (the change dir
      existed when the flow resumed) and the verifier has not been delegated
      in this invocation
    And the stop is a hard state stop, reported as such in the closing block
      ("status=stopped"), with the latch applying: no further delegation of
      any kind, resumption only as a fresh invocation

  # ADD - flow-03: after a verifier delegation, change_dir=missing never
  # re-triggers the specifier rule — step 5's disk detection routes it.
  Scenario: flow-03
    When the reader reads the same routing and step 5
    Then a `change_dir=missing` probe outcome observed after this invocation
      has delegated the `verifier` does not apply the never-specified rule
      and does not delegate the specifier
    And it routes through step 5's disk-based outcome detection instead

  # ADD - flow-04: step 5 detects the verifier's approval from disk — re-probe
  # plus the release gate — never from the verifier's report.
  Scenario: flow-04
    When the reader reads step 5
    Then it opens by detecting the verifier's outcome from disk, never from
      the verifier's conversational verdict: the orchestrator re-probes (the
      step-2 probe; read-only probing is always allowed) and routes on the
      fresh output
    And when the probe reports `change_dir=missing` (the verifier's archive
      step moved the change dir), the orchestrator runs
      "sh <tempfile> release <slug>" and routes on its line: a green
      "released branch=antz/<slug>" means the change is approved —
      approved-with-warnings included, since its archive move is identical on
      disk — and the flow is done, printing the existing human follow-up
      print unchanged
    And a "gate=refused reason=archive-missing" line is an anomalous state
      (the change dir is gone but no archive exists): stop and report
    And any other "gate=refused reason=..." line stops per the release table
    And the release-output table and the human follow-up print keep their
      exact pinned content

  # ADD - flow-05: a fresh rejection is detected from a new REJECTED.md entry;
  # any other post-verifier state fail-closes.
  Scenario: flow-05
    When the reader reads step 5
    Then when the re-probe shows the change dir still present, the
      orchestrator compares "rejected_count" with the value it read from disk
      before that verifier delegation: a greater count is a fresh rejection
      and routes to step 6 (loop back to step 2, which picks the freshly
      written entry up on the next pass)
    And any other state — the change dir present with no new rejection — is
      an anomalous state (the verifier neither archived nor rejected): stop
      fail-closed and report
    And the comparison values are disk reads on both sides; nothing is taken
      from the verifier's report

  # ADD - flow-06: the dedup guard enumerates exactly two exceptions — the
  # step-4 coder relay and the step-4 single verifier retry.
  Scenario: flow-06
    When the reader reads the Session guards' dedup bullet
    Then the never-twice rule stays ("the same (sub-spec, role) pair is never
      delegated twice" within one invocation, routing instead by the existing
      state machine), and the bullet enumerates exactly two exceptions, both
      step 4's: relaying each attributable blocker to the `coder` session for
      the sub-spec it names (at most one relay per pair per entry; a second
      entry stops the flow for good), and the one bounded whole-change
      `verifier` retry when a rejected entry holds only attributable blockers
      (bounded by "REJECTED.md": the count reaching 2 stops the flow for good)
    And no third exception exists: the specifier is never re-delegated within
      an invocation, and a `change_dir=missing` outcome persisting after the
      specifier delegation stops the session rather than re-delegating
    And the guards keep their standing wording: prompt-level law, binding
      regardless of what the tool grant technically allows, per-invocation
      clean slate on resume, constraints only

  # ADD - flow-07: waiting-user is defined — the stop variant that hands a
  # decision to the user — and the latch applies identically to both variants.
  Scenario: flow-07
    When the reader reads the Report Format's status vocabulary and the
      Session guards' latch bullet
    Then "waiting-user" is defined as the stop variant whose stop hands a
      decision to the user, produced by exactly these stops: an
      "open_questions=yes" outcome; a slug-ambiguity stop (no unambiguous
      on-disk candidate, or a semantically unclear continuation of an
      already-claimed slug); and a receipt-doubt stop (the doubtful-receipt
      path that can neither be settled from the receipt's id lines nor by a
      suite run, and asks the user once)
    And "stopped" is defined as the hard state stop — every other
      stop-and-report outcome
    And the latch applies identically to both variants: a waiting-user stop
      ends the session's delegation exactly like a stopped one;
      "waiting-user" changes only the closing block's status value, never
      stop behavior
    And the vocabulary itself is unchanged — the same six status values stay
      pinned — and the tests and docs that name the vocabulary stay valid
      without edits (the definition lives in the prompt)

  # ADD - flow-08: every other stop reports status=stopped — the hard state
  # stops are enumerated, so the classification is closed.
  Scenario: flow-08
    When the reader reads the Report Format's status vocabulary
    Then the stops reported as "status=stopped" include at least: the flow
      script's machine-line stops ("state=no_git", "state=no_repo",
      "state=no_commits", "state=checkout_refused", "state=no_branch"),
      "branch=missing", the mid-session change-dir deletion stop, the
      post-verifier fail-closed stop, any "gate=refused reason=..." line, a
      "BLOCKED:"-reasoned sub-spec found in classification (stop at the first
      one found, relay its reason), "rejected_count=2", a non-attributable
      blocker in a rejected entry, and the empty-ids stop-and-ask
    And each of those stops still names the resume action in the report body;
      "stopped" versus "waiting-user" changes only the closing status value

  # ADD - flow-09: the unchanged surface stays unchanged — the probe keeps
  # change_dir=missing as an output, the tables and fences survive, the steps
  # still end at 6.
  Scenario: flow-09
    When the reader reads the whole orchestrator prompt and compares it with
      the pre-change prompt
    Then the step-2 probe table still lists "change_dir=missing" as an output
      (only its routing meaning changed: the wrong-slug stop is replaced by
      the directory-based routing), and the probe script itself still prints
      it exactly as before
    And the latch still names "change_dir=missing" among the stop outcomes
    And the discover table, the state-output table, the rejection-routing
      table, and the release-output table survive with their headers and
      machine lines
    And the numbered steps still end at 6 and no new fenced block was added
      (still 14 fence lines across 7 blocks, exactly one ```sh fence)
    And step 1's ensure-state meanings (created/reused positioned,
      checkout_refused/no_branch/no_commits stops) keep their pinned wording

  # ADD - flow-10: the historical design record's derivation table reflects
  # the specifier delegation as a first-class, disk-routed step (docs only).
  Scenario: flow-10
    When the reader reads "docs/orchestrator.md"'s derived-state table
    Then the "What change/slug is this?" row no longer describes diffing
      "spdd/changes/" before and after delegating a new request to the
      specifier — the specifier delegation is a first-class flow step routed
      from disk: the orchestrator delegates the change to the specifier when
      neither the change dir nor the archive exists, then re-probes
    And the row keeps the file's historical-record framing (an explanation of
      the design's reasoning, not living documentation)
    And no other row of that table is edited by this change
