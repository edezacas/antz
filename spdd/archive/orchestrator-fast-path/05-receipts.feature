# Change: orchestrator-fast-path — sub-spec 05 (receipts: classify without re-running tests)
#
# New disk artifact + new classification source of truth:
#   - The coder, at the end of each session that finishes or advances a
#     sub-spec, writes spdd/changes/<slug>/NN-<feature>.result — named after
#     the sub-spec file (01-api.feature → 01-api.result).
#   - Receipt grammar (fixed, grep-able):
#       test_command=<discovered unit-suite run command>
#       id=<feature>-<index> result=green|skip|blocked reason=<text>
#     exactly one test_command line (non-empty value), then one id line per
#     declared scenario id, each with a non-empty reason; a blocked line's
#     reason starts with "BLOCKED: " (the existing skip-reason convention).
#   - The orchestrator's probe reads the receipts and extends each subspec
#     line with receipt=/covered=/complete=/class=; classification becomes
#     file reading. The orchestrator never runs the unit suite for
#     classification and never as a pre-verifier gate; the only exception
#     is a missing/incomplete/mismatched receipt, where it re-runs the
#     suite once for that doubtful sub-spec.
#   - Test-command discovery moves to the coder (recorded in the receipt).
#
# Classification mapping (mechanical, from the probe):
#   done         ← complete=yes AND every id result is green or ordinary skip
#   blocked      ← any id line has result=blocked (checked first, regardless
#                  of coverage — a partial receipt with a blocked id is
#                  blocked, never in_progress)
#   in_progress  ← receipt missing/incomplete/mismatched (complete=no), or
#                  complete=yes with a non-green/non-skip outcome otherwise
#                  unaccounted for
#
# Directory ownership unchanged: the receipt lives under
# spdd/changes/<slug>/, written by the coder like every other role artifact;
# the orchestrator never writes anything itself.

Feature: receipts — the coder records per-scenario results; the orchestrator classifies by reading them

  Background:
    Given a change directory "spdd/changes/<slug>/" holding sub-spec files
      "NN-<feature>.feature" whose declared scenario ids the probe already
      extracts from their tag comments
    And a coder session implementing one sub-spec tags each unit test with
      its scenario's "<feature>-<index>" id (existing convention)

  # ADD - receipts-01: the coder writes the receipt at session end, named
  # after the sub-spec, with the discovered test command recorded.
  Scenario: receipts-01
    When a coder session finishes or advances its sub-spec
    Then it writes "spdd/changes/<slug>/NN-<feature>.result", mirroring the
      sub-spec's filename
    And the receipt contains exactly one "test_command=" line whose value is
      the unit-suite run command the coder discovered and used for this
      sub-spec (the way any contributor would: "package.json" test script, a
      "Makefile" test target, the language's standard convention)
    And the receipt contains one id line per scenario id the sub-spec
      declares, each of the form
      "id=<feature>-<index> result=<green|skip|blocked> reason=<text>"

  # ADD - receipts-02: the result vocabulary and reason forms, worked per
  # outcome.
  Scenario Outline: receipts-02
    When the coder records the outcome row's scenario in the receipt
    Then the receipt carries the row's line for that id

    Examples:
      | outcome                                                        | receipt line                                                     |
      | the scenario's unit test passes                                | id=<id> result=green reason=<unit test name>                     |
      | the scenario is an ordinary skip (not unit-testable, no stub)  | id=<id> result=skip reason=<why>                                 |
      | the scenario is a "BLOCKED:" skip/reason stub                  | id=<id> result=blocked reason=BLOCKED: <why>                     |

  # ADD - receipts-03: the receipt's id set equals the sub-spec's declared
  # id set exactly — no foreign id, no missing id, no duplicate.
  Scenario: receipts-03
    Given the sub-spec declares the ids <declared>
    Then the receipt's id lines name exactly <declared>, each once, in the
      sub-spec's scenario order
    And an id not declared in the sub-spec never appears in its receipt
    And a declared id with no test yet still gets its line (result=skip or
      result=blocked with an honest reason), never a silent omission

  # ADD - receipts-04: a later coder session on the same sub-spec updates
  # the same receipt in place — the file always holds the newest session's
  # state.
  Scenario: receipts-04
    Given "NN-<feature>.result" already exists from an earlier coder session
    When a fresh coder session finishes or advances the same sub-spec
    Then the same file is rewritten (never a second, accumulated
      "NN-<feature>.result-2" or sibling file)
    And the rewritten receipt reflects that session's outcomes and test
      command

  # ADD - receipts-05: a planning-stage refusal (the existing "BLOCKED:"
  # whole-sub-spec convention) still produces a truthful receipt.
  Scenario: receipts-05
    When the coder refuses a sub-spec at the planning stage, before any
      test exists, and writes the stub reasoned "BLOCKED: <why>" tagged
      with the sub-spec's first scenario id (existing convention)
    Then the receipt lists every declared id with "result=blocked" and the
      same "BLOCKED: <why>" reason
    And "test_command=" still records the discovered (or honestly
      undiscoverable) suite command, so the receipt is never empty

  # MODIFY - receipts-06: the probe reads the receipts and extends each
  # subspec line — the state probe's output vocabulary grows mechanically.
  Scenario: receipts-06
    Given the probe (now "scripts/orchestration/antz-probe.sh") runs with
      CHANGE_DIR pointed at the change directory
    Then each "subspec=<file> ids=<id,...>" line additionally carries
      "receipt=<NN-<feature>.result|missing> covered=<n>/<N>
      complete=<yes|no> class=<done|blocked|in_progress>", where N is the
      sub-spec's declared id count and n the count of declared ids present
      in the receipt
    And "complete=yes" requires the receipt to exist, carry exactly one
      non-empty "test_command=" line, and name exactly the declared id set
      (a foreign id is a mismatch: covered may still read N/N but
      complete=no)
    And "class=" applies the mapping: any "result=blocked" line → blocked;
      else complete=yes with all results green or skip → done; else
      in_progress
    And the probe's other outputs are unchanged ("open_questions=",
      "rejected_count=", the "change_dir=missing" short-circuit, and the
      empty-ids stop-and-ask rule)

  # MODIFY - receipts-07: classification becomes file reading — the
  # orchestrator's step 3 no longer discovers or runs the unit suite.
  Scenario: receipts-07
    When the reader reads the orchestrator prompt's step 3 after this
      sub-spec
    Then it classifies each sub-spec from the probe's receipt fields alone:
      "done" (complete receipt, green/ordinary-skip), "blocked" (any
      "result=blocked" line — stop at the first one found, relay its
      "BLOCKED:" reason, route to specifier as today), "in_progress"
      (missing/incomplete/uncovered — delegate to a fresh coder session as
      today)
    And it no longer instructs discovering the unit-suite command or
      running the suite for classification

  # ADD - receipts-08: the one suite exception — a doubtful receipt is
  # settled by re-running the suite for that sub-spec only.
  Scenario: receipts-08
    Given a sub-spec whose receipt is missing, incomplete, or mismatched
      (complete=no)
    When the orchestrator classifies that sub-spec
    Then it re-runs the unit suite once, for that doubtful sub-spec only —
      using the receipt's "test_command=" value when the receipt carries
      one, else discovering the command the way any contributor would
    And it classifies that sub-spec from the actual run result (all
      green/ordinary-skip → done; any "BLOCKED:" skip → blocked; any red →
      in_progress, delegating a fresh coder session), and reports the
      receipt doubt in its report
    And it never writes, fixes, or fabricates the receipt itself — the
      receipt stays the coder's artifact

  # MODIFY - receipts-09: no pre-verifier gate — receipts alone route to the
  # verifier; the verifier's e2e suite remains the independent gate.
  Scenario: receipts-09
    Given every sub-spec classified "done" from its receipt
    When the orchestrator routes to step 4
    Then it delegates to the verifier without running the unit suite at
      all — there is no "final gate" re-test
    And the verifier's own e2e Integration Verification suite remains the
      independent gate (its prompt duty unchanged)

  # ADD - receipts-10: the receipt convention is documented identically in
  # both policy docs (docs need no bump).
  Scenario: receipts-10
    When the reader reads "AGENTS.md" and "CLAUDE.md"'s gotchas
    Then each carries an identical receipt-convention bullet: the file name
      "spdd/changes/<slug>/NN-<feature>.result" written by the coder at
      session end, the "test_command=" + per-id "result=green|skip|blocked"
      grammar, "BLOCKED:" as the blocked reason, and that the orchestrator
      classifies by reading receipts — running the unit suite only for a
      doubtful receipt, never as a pre-verifier gate

### Invariants
- The disk receipt is the classification authority; a role's conversational
  report is never an input to it (the governing rule holds).
- The probe still runs no tests and no git: receipts are read as files,
  like OPEN_QUESTIONS.md and REJECTED.md before them.
- The unit suite is run by the orchestrator in exactly one situation: the
  doubtful-receipt exception of receipts-08 — never for classification of a
  well-formed receipt, never as a pre-verifier gate.
- Sequential coder sessions, the bounded REJECTED.md retry, the BLOCKED:
  stop-and-relay behavior, and directory ownership are all unchanged.
- The sub-spec's empty-ids case keeps its existing stop-and-ask outcome
  (never vacuously done) — with no ids, the receipt has no id lines and the
  orchestrator stops and asks.

## Out of scope
- A formalized Result Contract beyond the receipt grammar and the closing
  block (sub-spec 06): no new status vocabulary for the verifier, no
  machine-readable merge of receipts into spdd/specs/.
- Any change to the verifier's duties, the e2e QA suite's role, or the
  rejection machinery's bounds.
- Receipts for the specifier's or verifier's own artifacts (receipts cover
  coder sub-spec sessions only).

## Relevant files
- "agents/prompts/coder.prompt" — the receipt-writing duty (## Output or a
  dedicated section) plus test-command discovery.
- "agents/prompts/orchestrator.prompt" — step 3's file-reading
  classification, the doubtful-receipt exception, the removed
  suite-discovery prose.
- "scripts/orchestration/antz-probe.sh" — the extended subspec line
  (receipts-06).
- "AGENTS.md", "CLAUDE.md" — the identical receipt gotcha bullet
  (receipts-10).
- "tests/orchestrator-status-probe_test.sh" — coverage for the extended
  probe output (coder-delivered, ids receipts-*).
