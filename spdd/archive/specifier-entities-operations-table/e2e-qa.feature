Feature: End-to-end QA - a live specifier session applies the optional Entities/Operations table
  # Operates through the real product "UI" for this role: invoking the
  # specifier agent (Claude Code "antz-specifier" or OpenCode equivalent)
  # with a natural-language request, then inspecting the artifacts it
  # writes under spdd/changes/<slug>/ -- README.md, the numbered .feature
  # files, and OPEN_QUESTIONS.md (or its absence). For a role whose entire
  # product is written specification text, these produced files ARE the
  # observable output of "running the specifier" -- there is no other UI
  # surface to exercise. No internal API calls: every step is either an
  # agent invocation or a file the invocation produced, read back.
  #
  # These scenarios require a live specifier session and cannot be reduced
  # to a static grep on specifier.prompt (that is what
  # 01-entities-operations-table.feature covers instead) -- end-to-end
  # only, verified by the verifier during Integration Verification, not by
  # the coder's unit suite.

  Background:
    Given a local checkout of a test repo that is a git repository
    And the specifier's own tool grant is "Read, Grep, Glob, Bash" (readonly access, no Write/Edit tool) -- it authors files under spdd/changes/ via Bash

  ## Optional Entities/Operations table (live)

  # ADD - e2e-entities-01: a change introducing a new data shape and
  # multiple named operations gets a scannable table in README.md.
  Scenario: e2e-entities-01
    Given a request that introduces a new "Widget" entity and three named operations ("create", "list", "delete")
    When the user invokes the specifier
    Then "spdd/changes/<slug>/README.md" includes an Entities table with columns "Name", "Path", "New-or-Existing", "Notes" listing "Widget"
    And an Operations table with columns "Type", "Identifier", "Description" listing "create", "list", "delete"
    And the numbered ".feature" files still contain the actual testable behavior for each operation (the table never substitutes for the Gherkin scenarios)

  # ADD - e2e-entities-02: a change with no new data shape and a single
  # operation produces no table, and is not penalized for omitting it.
  Scenario: e2e-entities-02
    Given a request that only tweaks an existing single CLI flag's default value, introducing no new entity and no additional operation
    When the user invokes the specifier
    Then "spdd/changes/<slug>/README.md" contains no Entities/Operations table
    And the produced README.md is not flagged as incomplete for omitting it
