# Sub-spec 07 — the posixsh suite tests only the current version; posixsh-04
# re-keys to direct inventories
# Destination domain: `posixsh`. Dependency order: 7 (independent of
# sub-specs 02-06; the second root-failure fix; the retained render goes
# through the harness library per sub-spec 01).

Feature: the posixsh suite's expectations come from the current install.sh
  alone
  posixsh-04's two registrations diffed a base install.sh extracted from
  git history against the working render — a mechanism that cannot anchor
  a current-version-only suite, and whose counting helper reports an empty
  diff as one line, so the suite ships RED at exactly the committed state
  every future flow must be green in ("got: 1"). The durable checks — the
  console report's shape and the installed tree — are assertable directly
  against a documented inventory of the current install.sh's output.

  Background:
    Given install.sh's fresh hermetic --all console report, which is in
      order: two client status lines (Claude Code, OpenCode), four
      script-artifact report lines (antz-flow.sh, antz-probe.sh,
      antz-skills.sh, antz-set-model.sh), twelve "Installed <dest>" client
      lines (four agents and two commands per client), and four "Installed
      <libdir>" script lines — each status/report line matching the
      outcome vocabulary libdirinstall-04 pins (fresh / already up to date
      / old -> new), verified by rendering on disk
    And a fresh render's HOME tree, which is exactly the sixteen documented
      files (twelve client files plus the four libdir scripts)
    And that the suite's renders go through the harness library's render
      helper

  # ADD - posixshfix-01: the console half asserts the report inventory
  # directly.
  Scenario: posixshfix-01
    When posixsh-04's console half runs
    Then it asserts the fresh render's report against the documented line
      inventory and order
    And its expectation derives only from the current install.sh and that
      inventory — no second render of any other source, no base-vs-working
      diff
    And the empty-diff count bug cannot recur: no diff-derived line count
      remains anywhere in the suite

  # ADD - posixshfix-02: the base machinery and the tree-identity
  # registration retire.
  Scenario: posixshfix-02
    When the posixsh suite runs
    Then the tree-identity registration is gone: it byte-compared two
      renders of install.sh, an assertion about a second version the
      current-version-only suite no longer has; its real coverage — the
      sixteen-file tree — is pinned by the render and libdir suites
    And every render in the suite renders the current install.sh, and the
      base-extraction helpers (base_install_sh, prep_base_if_distinct,
      base_install_file) are gone from the suite
    And with them the base-derived clauses retire: posixsh-01's scan keeps
      its synthetic-fixture pin and drops the historical-fidelity clause,
      and posixsh-02's negative control is carried by the synthetic trap
      fixture alone
    And posixsh-01..03 keep their ids and registrations, green, otherwise
      unchanged

  # ADD - posixshfix-03: the suite is green with the retained id.
  Scenario: posixshfix-03
    When the posixsh suite runs
    Then it exits 0 with every registered id green
    And the retained posixsh-04 id keeps its name, now with the single
      console-inventory registration

  # ADD - posixshfix-04: the retained suite is free of git-HEAD and prose
  # pins.
  Scenario: posixshfix-04
    When the retained suite's source is scanned
    Then it contains no real-tree-vs-git-HEAD comparison — no
      `git merge-base`, no `show HEAD:`, no `diff --quiet HEAD`, no `cmp`
      against git-extracted content — and no byte-pin against HEAD
    And it contains no exact-phrase prose assertion of prompts or docs;
      assertions on install.sh itself and on installed product files are
      not prose pins

### Invariants
- This is a re-key, not a deletion-to-hide: the console report's shape is
  now pinned more strongly (a complete ordered inventory) than the old diff
  allowed, and the tree coverage lives in its owning suites.
- The suite keeps its parse halves (posixsh-01..03) with their ids; only
  the base-derived clauses inside them retire, the synthetic-fixture
  instruments carrying the negative proof.
- Current-version law for this suite: zero git-HEAD comparisons or
  byte-pins vs HEAD, zero exact-phrase prose pins of prompts/docs (the
  Working-Root triplication exception belongs to roles_test.sh, not here).

### Out of scope
- Any product change (install.sh stays byte-identical per this change's
  contract) and any other suite's content.
