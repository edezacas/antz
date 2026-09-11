Feature: agents/meta/specifier.yaml and agents/meta/verifier.yaml declare access: readwrite
  # Layer: role metadata only -- agents/meta/*.yaml. The access model itself
  # (the readonly|readwrite|orchestrateonly taxonomy and install.sh's
  # access-to-frontmatter mapping) is unchanged; what changes is which value
  # the specifier and verifier roles declare. The bug: both roles declared
  # readonly, which renders to NO edit capability on both clients, yet both
  # roles' own prompts require writing their core artifacts (specifier:
  # spdd/changes/<slug>/; verifier: spdd/specs/ merge, spdd/archive/ moves,
  # REJECTED.md appends) -- installed specifier sessions silently completed
  # with zero files written. Framework permission layers cannot scope edits
  # to paths (no "may write only spdd/"), so a path-restricted new access
  # level would map to nothing mechanically enforceable; the honest minimal
  # fix is readwrite for both, with prompt-level path ownership unchanged.
  #
  # Verification: deterministic content assertions against the four meta
  # files (grep-style), unit-testable by the coder's own suite.

  Background:
    Given the four role metadata files "agents/meta/specifier.yaml",
      "agents/meta/coder.yaml", "agents/meta/verifier.yaml", and
      "agents/meta/orchestrator.yaml", each carrying "name", "description",
      and "access" fields
    And "agents/meta/coder.yaml" declares "access: readwrite" and
      "agents/meta/orchestrator.yaml" declares "access: orchestrateonly"
      (both unchanged by this change)

  # ADD - meta-01: the specifier role's access is corrected from readonly to
  # readwrite -- it authors spdd/changes/<slug>/ (README.md, numbered
  # .feature files, OPEN_QUESTIONS.md), which no readonly grant can write.
  Scenario: meta-01
    When the reader reads "agents/meta/specifier.yaml"
    Then its "access" field reads "readwrite"
    And its "name" field still reads "antz-specifier"
    And its "description" field is unchanged

  # ADD - meta-02: the verifier role's access is corrected from readonly to
  # readwrite -- it merges into spdd/specs/, moves approved changes to
  # spdd/archive/, and appends spdd/changes/<slug>/REJECTED.md.
  Scenario: meta-02
    When the reader reads "agents/meta/verifier.yaml"
    Then its "access" field reads "readwrite"
    And its "name" field still reads "antz-verifier"
    And its "description" field is unchanged

  # ADD - meta-03: the other two roles are untouched -- coder stays
  # readwrite, orchestrator stays orchestrateonly, byte-for-byte.
  Scenario: meta-03
    When the reader reads "agents/meta/coder.yaml" and "agents/meta/orchestrator.yaml"
    Then "agents/meta/coder.yaml" still declares "access: readwrite" and is otherwise byte-for-byte unchanged
    And "agents/meta/orchestrator.yaml" still declares "access: orchestrateonly" and is otherwise byte-for-byte unchanged

  ### Invariants
  - No new access level is introduced: the taxonomy stays
    readonly | readwrite | orchestrateonly.
  - No prompt body changes: every file under "agents/prompts/" is
    byte-for-byte unchanged (the path-ownership rules there are already
    correct -- the boundary is prompt discipline, not tool absence).
  - install.sh is byte-for-byte unchanged by this sub-spec (the mapping
    functions already render readwrite correctly).
  - The safety boundary narrative survives: no role ever commits; each
    role's writable surface is owned by its own prompt's rules, enforced at
    the prompt level, never by a path-scoped permission (impossible on both
    target clients).

## End-to-end QA suite

  # Operates at the real product UI: invoking the installed agents and
  # reading the artifacts they produce. e2e only -- appears as SKIP stubs in
  # the coder's unit suite.

  Background:
    Given a local checkout of a test repo that is a git repository
    And antz installed for the current client (antz:generated markers
      present, version = the repo's current VERSION)

  # ADD - e2e-meta-01: a specifier invocation actually writes its artifacts.
  Scenario: e2e-meta-01
    When the user invokes the specifier with a small natural-language change request
    Then "spdd/changes/<slug>/" is populated with "README.md" and numbered ".feature" files
    And no error or silent no-op occurred for lack of edit permission

  # ADD - e2e-meta-02: a verifier invocation actually writes its artifacts.
  Scenario: e2e-meta-02
    Given a coder has completed one sub-spec of a change and the orchestrator has delegated verification
    When the user invokes the verifier for that change
    Then either "spdd/specs/" gained the merged domain content and the change dir moved to "spdd/archive/<slug>/"
    Or "spdd/changes/<slug>/REJECTED.md" was appended with a rejection entry
    And no error or silent no-op occurred for lack of edit permission
