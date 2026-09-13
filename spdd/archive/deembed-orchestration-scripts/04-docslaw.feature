# Change: deembed-orchestration-scripts — sub-spec 04 (policy docs and law)
#
# AGENTS.md is the law; its Gotchas bullets currently state the OLD runtime
# convention twice (the branch-marker gotcha's antz-flow.sh sentence and
# the probe gotcha's sourcing sentence both say install.sh "injects" the
# scripts into the rendered orchestrator body and that the runtime
# convention is "saved to a temp file and run via sh, rather than installed
# anywhere"). Decision 5 (2026-09-13): AGENTS.md Gotchas and
# docs/orchestrator.md are updated in this change. CLAUDE.md duplicates
# AGENTS.md and the governing specs pin several of these bullets
# byte-identical between the two files, so every edit here lands in both.
# The VERSION/CHANGELOG bump is sub-spec 06's, not this one's.

Feature: docslaw — the runtime law in AGENTS.md/CLAUDE.md and the orchestrator design notes describe installed scripts invoked by path

  Background:
    Given "AGENTS.md" and "CLAUDE.md", whose Gotchas bullets pin the
      orchestrator's script runtime convention, duplicated between the two
      files byte-for-byte wherever a spec pins them identical
    And "docs/orchestrator.md", the orchestrator design record that states
      up front it is historical and not kept in sync
    And the de-embed delivered by sub-specs 01-03: scripts installed to the
      resolved libdir, invoked by path, zero re-materialization

  # MODIFY - docslaw-01: the branch-marker gotcha's antz-flow.sh sentence
  # states the installed-library law, re-keying the render-injection
  # wording duty; the "created and checked out" phrase and the
  # never-commits law are kept so the docs-bump pin survives.
  Scenario: docslaw-01
    When the reader reads the branch-marker gotcha bullet in AGENTS.md and
      CLAUDE.md
    Then its antz-flow.sh sourcing sentence states the scripts' source of
      truth is "scripts/orchestration/<name>.sh", that install.sh installs
      them as files to the resolved antz scripts libdir
      ("${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/"), and that the
      orchestrator invokes them there by path ("sh \"<libdir>/antz-flow.sh\"
      ...") instead of re-materializing any script into the rendered body
      or saving any temp file
    And it keeps stating that the branch is created **and checked out** by
      the orchestrator's "antz-flow.sh", that nothing is installed as a
      standalone CLI on PATH, no hook or plugin, and that no role ever
      commits
    And the bullet is byte-identical between AGENTS.md and CLAUDE.md
    And this re-keys the wording duty flow-branch's renderinject-07 pinned
      for these two sentences (its identical-in-both-files rule survives)

  # MODIFY - docslaw-02: the probe gotcha's sourcing sentence states the
  # same law; the probe's deliberate-stops-short clause is untouched.
  Scenario: docslaw-02
    When the reader reads the probe gotcha bullet in AGENTS.md and CLAUDE.md
    Then its sourcing sentence states the probe's source of truth is
      "scripts/orchestration/antz-probe.sh", installed by install.sh to
      the resolved libdir and run by the flow script's "state" subcommand
      by path — replacing the "whose content install.sh injects ... same
      runtime convention as /antz-set-model's embedded script: saved to a
      temp file and run via sh, rather than installed anywhere" wording
    And the sentence about what the probe deliberately stops short of
      (never running the unit suite; receipts read as files) is unchanged
    And the bullet is byte-identical between AGENTS.md and CLAUDE.md

  # ADD - docslaw-03: the Client Integration section names the libdir among
  # what install.sh installs, with the same marker/backup/--check policy.
  Scenario: docslaw-03
    When the reader reads the Client Integration section of AGENTS.md and
      CLAUDE.md
    Then one sentence states that install.sh also installs the three
      orchestration scripts and the set-model script as files under the
      resolved "antz/scripts" libdir, shared by both clients, carrying the
      same "antz:generated" marker, backup, and --check reporting as every
      other installed file
    And the sentence is byte-identical between the two files

  # ADD - docslaw-04: docs/orchestrator.md gains a short dated note; its
  # historical-record framing is preserved.
  Scenario: docslaw-04
    When the reader reads "docs/orchestrator.md"
    Then a short dated note near the top states that, as of change
      deembed-orchestration-scripts, the runtime convention it describes
      changed: the orchestration scripts are installed to the resolved
      antz scripts libdir and invoked by path, and the "temp file" wording
      in the historical sections below is historical
    And the note does not rewrite the historical sections; the file's
      historical-record framing survives intact
