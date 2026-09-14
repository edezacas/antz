# Sub-spec 06 — invocations-07 reads durable records (revised scope)
# Destination domain: `install-render` (the rendered-bodies domain the
# invocations suite belongs to; invocations-07 is currently spec-orphaned
# and its merge lands here). Dependency order: 6 (independent of sub-specs
# 02-05; one of the two root-failure fixes).
# Revised scope (supersedes the earlier README contracts): the suite area
# tests ONLY the current version's behavior; history/evolution calibration
# and prose pins are deleted, not relocated. The red clause's durable-record
# re-key stays; the deferred CHANGELOG clause is deleted with its SKIP stub.

Feature: the cache-effect check reads a record that does not move
  invocations-07's red clause greps
  "spdd/changes/deembed-orchestration-scripts/README.md" — a path that
  exists only while a change is in flight. That change is approved and
  archived, so the path is gone and the clause ships RED for process
  reasons, not product regressions. The record's durable, immutable home
  is the archived change README, and the clause is re-keyed to it. The
  clause's CHANGELOG half — a per-version entry-content pin, i.e.
  history/evolution calibration — is deleted outright with its SKIP stub
  per the revised scope, never activated.

  Background:
    Given the immutable archived record
      "spdd/archive/deembed-orchestration-scripts/README.md", which states
      the expected cache effect: the KV-cache priority, the ~335 embedded
      script lines leaving the rendered orchestrator body, and per-session
      script re-materialization dropping to zero (verified on disk)
    And the invocations suite's invocations-07 id, carried today by three
      registrations: the stable-prefix check (green), the record clause
      (RED — it reads the in-flight path), and the CHANGELOG clause (a
      SKIP stub deferring to the since-landed, since-superseded bump
      sub-spec)

  # ADD - invocationsfix-01: the record clause re-keys to the archived,
  # immutable path.
  Scenario: invocationsfix-01
    When invocations-07's record clause runs
    Then it reads "spdd/archive/deembed-orchestration-scripts/README.md"
      and still requires the three recorded facts: the KV-cache priority,
      the ~335 embedded lines, and the per-session re-materialization that
      drops to zero
    And the clause is green at the current disk state, where it was RED
      reading the in-flight path
    And the read is a durable-record read of the immutable archive — it
      introduces no real-tree-vs-git-HEAD comparison, no byte-pin vs git
      HEAD, and no exact-phrase prose assertion of agents/prompts or
      product docs

  # ADD - invocationsfix-02: the deferred CHANGELOG clause is deleted with
  # its SKIP stub.
  Scenario: invocationsfix-02
    When the invocations suite's registrations are scanned
    Then the CHANGELOG clause of invocations-07 no longer exists — its
      skip_test stub and its stale deferral reason are gone
    And no invocations-07 registration asserts CHANGELOG content; the
      VERSION-to-newest-entry agreement of sub-spec 05 remains the area's
      only CHANGELOG-touching assertion
    And invocations-07 is carried by exactly two registrations — the
      stable-prefix check and the re-keyed record clause — both keeping
      the invocations-07 id at the start of their reported names
    And the invocations suite exits 0 at the current disk state

### Invariants
- Re-key, not deletion: every fact the red clause checked is still
  checked, against the immutable archived record — never deleted to hide
  a real check.
- Revised-scope compliance: what this fix introduces performs no
  real-tree-vs-git-HEAD comparison, no byte-pin vs git HEAD, and no
  exact-phrase prose assertion of prompts or product docs; the archived
  change record is read solely as the durable record of the expected
  cache effect (the spdd/archive/ immutable-record channel).
- History calibration is deleted, not relocated: the [4.8.0] entry's
  measured content is pinned by no suite, and no CHANGELOG-content check
  regrows under this fix (sub-spec 05 keeps the only version assertion).
- Id stability: both retained registrations keep the invocations-07 id at
  the start of their reported names, per the repo convention.
- Scope law: this sub-spec changes exactly the two things above in
  tests/invocations_test.sh — the record clause's re-key and the deferred
  CHANGELOG clause's removal; no other invocations-0x scenario is in
  scope here.

## Out of scope
- Any other invocations-0x scenario, and any suite-wide scrub of
  tests/invocations_test.sh beyond the two changes above.
- Any VERSION or CHANGELOG.md edit, and any edit to spdd/specs/ or
  spdd/archive/ content.
