Feature: install.sh renders specifier and verifier with full edit capability, coder and orchestrator unchanged
  # Layer: install.sh rendered output. install.sh's access-mapping functions
  # (claude_tools_for_access, opencode_edit_perm_for_access,
  # opencode_mode_for_access, opencode_task_perm_for_access) already map
  # readwrite correctly; this sub-spec pins the rendered result for the two
  # corrected roles and guards the other two against drift. The readonly
  # mapping branches stay in the code even though, after this change, no
  # meta file declares readonly anymore -- dropping them would change the
  # access-to-frontmatter mapping (a major-grade contract change) for zero
  # benefit.
  #
  # Verification: run install.sh's render path against the meta files in
  # isolated temp dirs (never the real ~/.claude or ~/.config/opencode) and
  # assert on the produced frontmatter.

  Background:
    Given "agents/meta/specifier.yaml" and "agents/meta/verifier.yaml" declare "access: readwrite" (meta-01, meta-02)
    And "agents/meta/coder.yaml" declares "access: readwrite" and "agents/meta/orchestrator.yaml" declares "access: orchestrateonly"
    And the pre-change (readonly) renders of specifier and verifier carried "tools: Read, Grep, Glob, Bash" on Claude Code and "edit: deny" on OpenCode

  # ADD - render-01: the corrected roles render on Claude Code with Edit and
  # Write granted.
  Scenario Outline: render-01
    When install.sh renders "agents/meta/<role>.yaml" for Claude Code
    Then the rendered frontmatter carries "tools: Read, Grep, Glob, Bash, Edit, Write"

    Examples:
      | role       |
      | specifier  |
      | verifier   |

  # ADD - render-02: the corrected roles render on OpenCode with edit
  # allowed, task delegation denied, subagent mode kept.
  Scenario Outline: render-02
    When install.sh renders "agents/meta/<role>.yaml" for OpenCode
    Then the rendered frontmatter carries "mode: subagent"
    And "permission:" carries "edit: allow"
    And "permission:" carries "task: deny"

    Examples:
      | role       |
      | specifier  |
      | verifier   |

  # ADD - render-03: regression guard -- the two untouched roles render
  # byte-for-byte identically to the pre-change render.
  Scenario: render-03
    When install.sh renders "agents/meta/coder.yaml" and "agents/meta/orchestrator.yaml" for both clients
    Then every rendered file is byte-for-byte identical to rendering the pre-change meta files for both clients

  # ADD - render-04: the readonly mapping semantics are preserved in
  # install.sh even though no meta file declares readonly anymore -- the
  # mapping is a defined contract (kept verbatim), not dead-code bait.
  Scenario: render-04
    When the reader reads install.sh's access-mapping functions
    Then "readonly" still maps to "Read, Grep, Glob, Bash" (no Edit/Write) on Claude Code
    And "readonly" still maps to "edit: deny" and "task: deny" on OpenCode
    And the mapping functions' behavior is unchanged from the pre-change install.sh

  ### Invariants
  - The "antz:generated version=X -- do not edit by hand; regenerate with
    install.sh" marker format is unchanged (changing it would be a
    major-grade contract break and would break the /antz-set-model
    management check).
  - install.sh's mapping code is byte-for-byte unchanged: this change
    touches meta files only; install.sh itself is not edited at all.
  - After this change no meta file declares readonly, yet the readonly
    mapping remains a defined level (docs and mapping both keep it).
  - Renders are still deterministic from (prompt body, meta access, source
    VERSION); nothing else about the render pipeline changes.

## End-to-end QA suite

  # Operates at the user's own machine-level UI: install.sh's CLI and the
  # installed agent files. e2e only -- SKIP stubs at unit level.

  Background:
    Given the user's machine has the pre-change antz installed (installed copies marked "antz:generated version=<pre-change VERSION>", specifier/verifier without edit capability)

  # ADD - e2e-render-01: reinstalling overwrites the hand-patched temporary
  # edit grants with the real ones, same marker format.
  Scenario: e2e-render-01
    When the user runs "./install.sh --all" from the post-change checkout
    Then the installed "~/.claude/agents/antz-specifier.md" and "~/.claude/agents/antz-verifier.md" carry "tools: Read, Grep, Glob, Bash, Edit, Write"
    And the installed OpenCode copies carry "edit: allow" and "task: deny" and "mode: subagent"
    And every installed file is marked "antz:generated version=<new VERSION>" in the unchanged marker format
    And the installed coder and orchestrator copies carry their unchanged grants

  # ADD - e2e-render-02: --check sees the drift and prints the changelog
  # before reinstall, and reports up to date after.
  Scenario: e2e-render-02
    When the user runs "./install.sh --check" before reinstalling
    Then it reports the installed-to-source version drift for both clients and prints the new "CHANGELOG.md" entry
    When the user runs "./install.sh --all" and then "./install.sh --check" again
    Then "--check" reports "already up to date" for both clients
