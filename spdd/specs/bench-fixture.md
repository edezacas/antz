# Domain: bench-fixture

The checked-in benchmark fixture and its per-repetition materialization.

## Contract
- The fixture is data, not code: "bench/fixture/scenario.txt" holds the exact
  request text the runner passes as the client prompt; "bench/fixture/repo/"
  holds the toy project the request is written against.
- Materialization is per repetition and side-effect-free on the source tree:
  copy repo/ files byte-for-byte into a fresh temp directory, git init, one
  initial commit. Every repetition starts from the identical state, so runs
  and versions are comparable.
- The runner records the exact request bytes it passed into the run dir, so
  any record is auditable against the fixture.

## Feature: the checked-in benchmark fixture and its per-repetition materialization

  Background:
    Given the bench tree under "bench/" with the fixture under "bench/fixture/"
    And the harness runner "bench/antz-bench.sh" that materializes fixture
      repositories for each repetition

  # ADD - fixture-01: the checked-in fixture is self-contained: one request
  # file, the toy repo files, and no nested git data anywhere under it.
  Scenario: fixture-01
    When the fixture area "bench/fixture/" is inspected
    Then "bench/fixture/scenario.txt" exists, is non-empty, and holds the
      benchmark request text (the exact prompt the runner passes to the client)
    And "bench/fixture/repo/" exists and holds a small toy project the request
      references, including a "README.md"
    And a mechanical scan over "bench/fixture/" finds no ".git" file and no
      ".git" directory anywhere beneath it

  # ADD - fixture-02: each repetition gets a fresh, identical git repo
  # materialized under temp space -- the only git the fixture ever has.
  Scenario: fixture-02
    When the runner materializes the fixture twice, into two fresh temp
      directories
    Then each materialization is a git repository whose working tree carries
      the "bench/fixture/repo/" files byte-for-byte, plus nothing else
    And each materialization has exactly one commit ("git rev-list --count
      HEAD" reads 1), a clean "git status --porcelain", no "spdd/" directory,
      and no "antz/*" branch
    And mutating one materialization leaves the other unchanged -- the two
      repos share no state

  # ADD - fixture-03: the request is passed verbatim and recorded, so every
  # record is auditable against the fixture and repetitions are comparable.
  Scenario: fixture-03
    When a repetition runs, for the dry-run client
    Then the client prompt is exactly the content of
      "bench/fixture/scenario.txt"
    And the repetition's run dir carries a copy of that request (the same
      bytes), so the record can be audited against the fixture after the run
    And two repetitions of the same fixture pass byte-identical requests

## Invariants
- The checked-in fixture never gains or requires git state; git lives only in
  per-repetition materialized copies under temp space.
- The fixture request is fixed data: byte-stable across repetitions so runs,
  clients, and antz versions are comparable.
- Materialization never writes inside the antz checkout: source fixture files
  are only ever read.
