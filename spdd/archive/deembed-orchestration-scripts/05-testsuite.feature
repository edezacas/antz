# Change: deembed-orchestration-scripts — sub-spec 05 (test suites)
#
# Ten suites pin today's embedded-script shapes. The request brief named
# five ("renderinject, sessionguards, skills-block, status-probe, flow");
# repo verification found five more with the same exposure:
# orchestrator-render-sync_test.sh (rendered-fence drift guard),
# set-model-command_test.sh and installsh-posixsh_test.sh (embedded
# set-model script — those two ride sub-spec 03), roles_test.sh (the
# "state <slug> <probe-tempfile>" prompt pin), and refpin_test.sh (the
# include-injection fetch sentence — rides sub-spec 01). This sub-spec
# covers the six suites that pin the ORCHESTRATOR PROMPT's shape plus the
# whole-suite coherence clause. Every script-behavior assertion passes
# unmodified, because the scripts are byte-identical.
#
# Established re-scope conventions apply: loud notes for retired
# byte-identity gates, structural assertions enforced, change_pending-era
# guards retiring vacuously once HEAD carries the change.

Feature: testsuite — the suites pinning the embedded-script shape are re-scoped to the invocation shape, loudly and without losing coverage

  Background:
    Given the de-embed delivered by sub-spec 02 (prompt invokes by path;
      inject_includes() and the markers retired) and sub-spec 03 (the
      set-model script de-embedded)
    And the repo's suite conventions: self-contained bash harnesses,
      reported test names carrying their scenario ids, all filesystem
      work in temp dirs, byte-identity gates era-gated with loud notes

  # MODIFY - testsuite-01: tests/antz-flow_test.sh — the flow-fence and
  # structure pins re-key to the de-embedded prompt; every script-behavior
  # assertion passes unmodified.
  Scenario: testsuite-01
    When tests/antz-flow_test.sh runs
    Then its flow-fence-body assertion (the prompt's first 3-space fence
      holding exactly the flow include marker) is re-keyed to assert the
      prompt's step 1 references the flow script by its
      "__ANTZ_SCRIPTS_DIR__" path form
    And its "sh <tempfile> release <slug>" prose pin re-keys to the path
      form of the release invocation
    And its structural pins (14 fence lines / 7 blocks / one ```sh fence)
      re-key to 8 fence lines / 4 blocks / no ```sh fence, with the four
      tables and the steps-ending-at-6 pins unchanged
    And every ensure/discover/state/release behavior assertion passes
      unmodified against the byte-identical script file

  # MODIFY - testsuite-02: tests/orchestrator-status-probe_test.sh — the
  # probe-fence pin re-keys; the probe matrix passes unmodified.
  Scenario: testsuite-02
    When tests/orchestrator-status-probe_test.sh runs
    Then its file-source guard's probe-fence assertion (the "```sh" fence
      holding exactly the probe include marker) re-keys to the prompt
      referencing the probe by its "__ANTZ_SCRIPTS_DIR__" path form
    And every probe-behavior assertion (open questions, rejections,
      receipts classification, change_dir=missing, empty ids) passes
      unmodified against the byte-identical probe file

  # MODIFY - testsuite-03: tests/orchestrator-skills-block_test.sh — the
  # fence-locator machinery is reworked; the derivation assertions pass
  # unmodified.
  Scenario: testsuite-03
    When tests/orchestrator-skills-block_test.sh runs
    Then its fence-region locator and include-marker guard are reworked to
      assert the prompt's three invocation lines reference
      "__ANTZ_SCRIPTS_DIR__/antz-flow.sh", ".../antz-skills.sh", and
      ".../antz-probe.sh", each naming an existing scripts/orchestration/
      file
    And its additive-vs-HEAD guard is re-scoped to permit exactly this
      change's declared removals (the three former fenced bodies, their
      fence lines, and the replaced temp-file instruction prose), still
      failing on any removal outside them, and retiring vacuously per the
      change_pending pattern once HEAD carries the change
    And every block/derivation/matching/none-matched/constraint and
      body-never-read assertion passes unmodified against the
      byte-identical skills script

  # MODIFY - testsuite-04: tests/orchestrator-sessionguards_test.sh — the
  # marker-count pins re-key; the guards' law assertions pass unmodified.
  Scenario: testsuite-04
    When tests/orchestrator-sessionguards_test.sh runs
    Then its per-script include-marker count assertions re-key to the
      invocation-line forms (one path reference per script, no marker
      anywhere)
    And sessionguards-03's shape clause ("the prompt's three script fences
      still carry exactly their include markers") is re-scoped to the
      invocation lines, with "scripts/orchestration/" still holding
      exactly the three pre-existing script files
    And the dedup/latch law assertions and the no-delegation-ledger checks
      pass unmodified

  # MODIFY - testsuite-05: tests/renderinject_test.sh — the marker
  # reconstruction retires; the no-survivor and structural assertions
  # re-key; the docs runtime-wording checks follow sub-spec 04's wording.
  Scenario: testsuite-05
    When tests/renderinject_test.sh runs
    Then its marker-substitution reconstruction assertion retires with a
      loud note (no markers exist to reconstruct)
    And its no-survivor assertion re-keys to: no "# antz-include:" marker
      AND no script-content fence in any rendered file
    And its prompt usage-line pins ("sh <tempfile> discover | ensure <slug>
      | state <slug> <probe-path> | release <slug>" and "sh <tempfile>
      <working-root> <match keyword>") re-key to the path-based forms
    And its AGENTS.md/CLAUDE.md runtime-wording check ("sh <tempfile> ...")
      re-keys to the installed-library wording of sub-spec 04
    And its set-model command byte-identity masks retire with a loud note
      (those command bodies legitimately changed in sub-spec 03)
    And the structural assertions that stay enforced (frontmatter shape,
      install inventory, orchestrator-keyed rendering, quoted
      descriptions) keep passing

  # MODIFY - testsuite-06: tests/roles_test.sh — the invocation-form hard
  # constraints re-key; the machine-line grammars hold.
  Scenario: testsuite-06
    When tests/roles_test.sh runs
    Then its "state <slug> <probe-tempfile>" prompt pin re-keys to the
      path-based state invocation form, and the ensure/release invocation
      pins keep matching the prompt's (unchanged) subcommand forms
    And every hard machine-line constraint passes unmodified: the
      delegation-header lines, the probe's "subspec=" line, the receipt
      grammar, the closing-block grammar, the stop-state tokens

  # MODIFY - testsuite-07: tests/orchestrator-render-sync_test.sh — the
  # drift guard compares installed libdir files against sources instead of
  # rendered fences.
  Scenario: testsuite-07
    When tests/orchestrator-render-sync_test.sh runs
    Then its rendered-fence comparison is replaced by: each installed
      libdir script equals its "scripts/orchestration/" source
      byte-for-byte after stripping the single inserted marker line
    And its drift half still works: tampering one byte of one installed
      libdir script makes the guard report exactly that script out of sync
    And its antz-skills.sh fence-indent carve-out logic is gone (nothing
      left to re-apply)

  # ADD - testsuite-08: whole-suite coherence — nothing outside the
  # re-scoped suites breaks, and no test extracts a script from a prompt
  # or command body anymore.
  Scenario: testsuite-08
    When the repo's full unit suite runs
    Then every suite not named by sub-specs 01, 03, and 05 of this change
      passes unmodified
    And every suite exits 0 with its scenario ids reported
    And no test extracts script content from agents/prompts/ or from any
      rendered command body — scripts are tested as installed files and
      as sources
