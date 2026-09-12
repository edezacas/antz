# Change: fix-orchestrator-flow — sub-spec 02 (receipts: the test_command=none
# sentinel)
#
# Plan item 1.7 of docs/plan-revision-2026-09.md §3 Cambio A.
#
# Layer: the receipt grammar's one gap — today the coder prompt says to record
# "honestly undiscoverable" when no unit suite is discoverable but defines no
# value, so the orchestrator's doubtful-receipt path could try to execute an
# arbitrary non-empty string. This sub-spec defines the literal sentinel
# test_command=none, pins that the probe accepts it as a well-formed non-empty
# value (complete may be yes), and forbids the orchestrator from ever
# executing it.
#
# Declared boundaries: agents/prompts/coder.prompt's "## Receipt" section and
# the grammar bullets only; agents/prompts/orchestrator.prompt's step-3
# doubtful-receipt bullet only (sub-spec 01-flow owns the rest of that file's
# edits). scripts/orchestration/antz-probe.sh is byte-unchanged — any
# non-empty test_command= value is already well-formed, so the probe accepts
# the sentinel with no code change; the probe scenario pins that property so
# a future grammar tightening cannot silently reject the sentinel.
#
# Merge map: receipts-01 and receipts-05 (MODIFY) merge into
# spdd/specs/receipts.md (the grammar they define lives there); receipts-06
# (MODIFY) and receipts-11 (ADD) merge into spdd/specs/flow-branch.md, beside
# receipts-06..09 (the probe and step-3 flow edges), per the split precedent
# recorded in receipts.md's Origin.

Feature: the receipt's test_command= line carries the literal none sentinel when no suite is discoverable, the probe accepts it, and the orchestrator never executes it

  Background:
    Given the receipt grammar as merged: exactly one non-empty
      "test_command=" line whose value is the unit-suite run command the
      coder discovered and used, plus one
      "id=<feature>-<index> result=<green|skip|blocked> reason=<text>" line
      per declared scenario id
    And the probe's mechanical grammar check: "complete=yes" requires the
      receipt to exist with exactly one non-empty "test_command=" line and
      exactly the declared id set
    And the orchestrator's doubtful-receipt exception: a sub-spec whose
      receipt is missing, incomplete, or mismatched ("complete=no") gets
      exactly one suite re-run, for that doubtful sub-spec only

  # MODIFY - receipts-01: the test_command= value gains the literal none
  # sentinel for the genuinely-undiscoverable case — never empty, never
  # guessed.
  Scenario: receipts-01
    When the reader reads the coder prompt's "## Receipt" section
    Then the "test_command=" line's value is the unit-suite run command the
      coder discovered and used for this sub-spec
    And when nothing is genuinely discoverable, the value is the literal
      sentinel "none" — the line reads exactly "test_command=none"
    And an empty value is still never written: "none" replaces the previous
      "record that honestly rather than leaving the line empty" guidance as
      the one defined way to record honest undiscoverability
    And every other part of the receipt duty is unchanged: the file name and
      location, the rewrite-in-place rule, the per-id lines, the result
      vocabulary, and the planning-stage refusal's truthful receipt

  # MODIFY - receipts-05: a planning-stage refusal records the discovered
  # command or the literal none sentinel — the receipt is never empty.
  Scenario: receipts-05
    When the reader reads the planning-stage-refusal bullet of the coder
      prompt's "## Receipt" section
    Then a planning-stage refusal still produces a truthful receipt: every
      declared id gets "result=blocked" with the same "BLOCKED: <why>" reason
    And the "test_command=" line still records the discovered suite command,
      or the literal "none" sentinel when nothing is genuinely discoverable
    And the receipt is never empty in either case

  # MODIFY - receipts-06: the probe accepts the sentinel as a well-formed
  # non-empty value — complete may be yes. No probe code change; the property
  # is pinned.
  Scenario: receipts-06
    When the probe classifies a change dir whose sub-spec's receipt reads
      "test_command=none" followed by one "id=" line per declared scenario
      id, each "result=green" or an ordinary "result=skip" with a non-empty
      reason
    Then the probe accepts the sentinel as a well-formed non-empty
      "test_command=" value: the "subspec=" line reports "complete=yes"
    And the classification mapping applies unchanged: with no
      "result=blocked" line, the sub-spec classifies "class=done"
    And nothing else about the probe's grammar check changes: an empty
      "test_command=" value is still a mismatch ("complete=no"), a receipt
      with no "test_command=" line or two of them is still incomplete, and
      the id-set, reason, and result checks are untouched

  # ADD - receipts-11: the orchestrator never executes the sentinel — with
  # none and a doubtful receipt it classifies from the id lines or asks the
  # user once.
  Scenario: receipts-11
    When the reader reads the orchestrator's step-3 doubtful-receipt bullet
    Then the sentinel is never executed: a doubtful receipt whose
      "test_command=" value is the literal "none" is never run by the
      orchestrator
    And with "none" and a doubtful receipt, the orchestrator classifies from
      the receipt's "id=" lines where they settle the outcome: any
      "result=blocked" line still stops at the first one found and relays its
      "BLOCKED:" reason the same way a well-formed blocked receipt would
    And when the id lines cannot settle it, the orchestrator asks the user
      once rather than guessing — the receipt-doubt stop, reported
      "status=waiting-user"
    And the rest of the doubtful-receipt exception is unchanged: a doubtful
      receipt carrying a real command is still re-run once for that doubtful
      sub-spec only, a receipt carrying no "test_command=" line at all still
      falls to discovering the command the way any contributor would, the
      sub-spec is classified from the actual run result, the doubt is
      reported, and the orchestrator still never writes, fixes, or fabricates
      the receipt
