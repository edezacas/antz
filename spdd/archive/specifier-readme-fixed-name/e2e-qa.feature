Feature: End-to-end QA - a live specifier session always names its change overview file README.md
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
  # 01-readmefile.feature covers instead) -- end-to-end only, verified by
  # the verifier during Integration Verification, not by the coder's unit
  # suite.

  Background:
    Given a local checkout of a test repo that is a git repository
    And the specifier's own tool grant is "Read, Grep, Glob, Bash" (readonly access, no Write/Edit tool) -- it authors files under spdd/changes/ via Bash

  ## The overview file is always README.md (live)

  # ADD - e2e-readmefile-01: two differently-shaped requests -- one with no
  # new data shape and a single operation, one introducing a new entity and
  # multiple named operations -- both produce their overview under the same
  # fixed name, never any other name.
  Scenario Outline: e2e-readmefile-01
    Given a request that <request-shape>
    When the user invokes the specifier
    Then "spdd/changes/<slug>/README.md" is created with the change's overview (goal, contract, invariants, out-of-scope)
    And no other overview file (e.g. "OVERVIEW.md", "SUMMARY.md", "NOTES.md") is created in "spdd/changes/<slug>/"

    Examples:
      | request-shape                                                                          |
      | only tweaks an existing single CLI flag's default value, introducing no new entity      |
      | introduces a new "Widget" entity and three named operations ("create", "list", "delete") |

  # ADD - e2e-readmefile-02: when a change does include the optional
  # Entities/Operations table, that table lives inside this same
  # README.md, alongside the rest of the overview -- never in a separate
  # file.
  Scenario: e2e-readmefile-02
    Given a request that introduces a new "Widget" entity and three named operations ("create", "list", "delete")
    When the user invokes the specifier
    Then the Entities/Operations table appears inside "spdd/changes/<slug>/README.md", not in any separate file
    And the numbered ".feature" files still contain the actual testable behavior for each operation (the table never substitutes for the Gherkin scenarios)
