Feature: AGENTS.md, CLAUDE.md, and docs/orchestrator.md access-model wording matches reality
  # Layer: documentation. AGENTS.md and CLAUDE.md's Gotchas state "the
  # specifier/verifier roles are readonly ... the coder role is the only
  # role that modifies files" -- the sentence this change's bug disproved.
  # The correction keeps the actual safety boundary intact in wording: no
  # role ever commits, and each role's writable surface is owned by its own
  # prompt's path rules (prompt-level, not tool-enforced). The "Governing
  # rule" narrative (no role depends on another role's conversational
  # output) is untouched. docs/orchestrator.md's delegation-scoping section
  # argues "the specifier/verifier readonly boundary is real" -- that
  # parenthetical becomes false and is corrected too.
  #
  # Verification: deterministic content assertions on the three doc files,
  # same style as tests/versioning-rule_test.sh.

  Background:
    Given "AGENTS.md" and "CLAUDE.md", each carrying a "## Gotchas" bullet that currently reads (in its access-model part): "access is readonly | readwrite | orchestrateonly. The specifier/verifier roles are readonly (no edit/write capability); the coder role is readwrite (the only role that modifies files); the orchestrator role is orchestrateonly -- readonly plus a delegation capability, used only by it."
    And "docs/orchestrator.md"'s "Platform delegation scoping" section currently states: "the specifier/verifier readonly boundary is real"

  # ADD - docs-01: AGENTS.md's access-model gotcha states the corrected
  # model -- three readwrite roles with their artifact surfaces, one
  # orchestrateonly role, boundary at prompt level.
  Scenario: docs-01
    When the reader reads the "## Gotchas" section of "AGENTS.md"
    Then its access-model bullet states that the specifier, coder, and verifier roles are "readwrite" (edit capability, each for its own prompt-owned artifact surfaces: the specifier authors "spdd/changes/<slug>/", the coder implements sub-specs, the verifier merges into "spdd/specs/" and owns "spdd/archive/" moves and "REJECTED.md" appends)
    And it states that the orchestrator role remains "orchestrateonly" -- readonly-equivalent tools plus a delegation capability, used only by it
    And it states that the safety boundary is prompt-level path ownership per role plus the never-commits law, not tool absence -- framework permissions cannot scope edits to paths
    And it does not state that any of specifier, coder, or verifier is "readonly" or that the coder is "the only role that modifies files"

  # ADD - docs-02: CLAUDE.md states the identical corrected model (the two
  # policy docs duplicate each other and must not fork).
  Scenario: docs-02
    When the reader compares the access-model gotcha bullets of "AGENTS.md" and "CLAUDE.md"
    Then they state the identical corrected model: specifier/coder/verifier "readwrite", orchestrator "orchestrateonly", prompt-level boundary, never-commits law intact

  # ADD - docs-03: the wrong claim is gone everywhere in both policy docs,
  # not only from the gotcha bullet.
  Scenario: docs-03
    When the reader reads "AGENTS.md" and "CLAUDE.md" in full
    Then neither file anywhere states that the specifier or verifier role is "readonly", lacks edit/write capability, or that the coder is the only role that modifies files
    And the "## Client Integration" mapping description still states the defined mapping levels ("access: readonly" maps to no edit/write capability, "readwrite" to full edit access, "orchestrateonly" to readonly plus delegation) -- now noting that after this change no role declares readonly, while install.sh keeps the mapping

  # ADD - docs-04: docs/orchestrator.md's delegation-scoping paragraph is
  # corrected without weakening its verified platform claim.
  Scenario: docs-04
    When the reader reads "docs/orchestrator.md"'s "Platform delegation scoping" section
    Then it no longer states that a specifier/verifier readonly boundary is real
    And it still states that Claude Code's subagent "tools:" list is a strict, enforced allowlist (the verified platform fact, which is why the old readonly denial was real)

  ### Invariants
  - The Governing-rule narrative is untouched: no role, including the
    orchestrator, may depend on another role's conversational output.
  - The never-commits law is untouched and restated where the access model
    is described: granting Edit/Write grants artifact authorship, never
    commit authority (no role carries a commit fence; committing is always
    the human's follow-up).
  - Coder ownership rules stay as-is: the coder only reads "spdd/changes/"
    and never touches "spdd/specs/" or "spdd/archive/" -- readwrite for the
    verifier does not weaken that.
  - The historical sibling-variant docs ("docs/worktree-isolation-plan*.md")
    are not corrected: they describe the "worktree" branch's variant
    historically.
  - The stale e2e Background line in "spdd/specs/specifier-role.md" ("the
    specifier's own tool grant is Read, Grep, Glob, Bash -- readonly
    access") becomes drift the verifier should touch up during its merge of
    this change; it is not edited by the coder.

## End-to-end QA suite

  # Operates at the user-visible surface: reading the docs. e2e only.

  # ADD - e2e-docs-01: a user reading the docs derives the real access
  # model, with no contradiction left against the meta files or the roles'
  # prompts.
  Scenario: e2e-docs-01
    When the user reads the "## Gotchas" sections of "AGENTS.md" and "CLAUDE.md" and then the four "agents/meta/*.yaml" files
    Then the documented access values match the declared ones for all four roles
    And no doc statement contradicts a role prompt's own artifact-writing requirements
