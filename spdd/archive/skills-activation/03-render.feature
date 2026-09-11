# Domain: skills grant render (install.sh layer)

## Goal
install.sh's access-to-frontmatter mapping is extended in exactly one place:
the Claude Code `readwrite` mapping gains the `Skill` tool, so an installed
antz agent with `access: readwrite` (specifier, coder, verifier) can invoke
  the Skill tool. On Claude Code, a subagent's `tools:` list is a strict,
enforced allowlist — without `Skill` listed, the tool is absent from the
session and no prompt wording can compensate (this is root-cause layer 2 of
the reported defect). The grant coexists with, rather than replaces, the
prompt-level duties: with the tool present the session discovers skills
natively (matching the mechanical, description-keyed approach gentle-ai
pins); without it (or when a delegation carries pre-resolved paths,
02-orchestrator) the directory-read fallback applies. The `readonly` and
`orchestrateonly` mappings stay
byte-for-byte unchanged, and the OpenCode render is unchanged in every
respect: the native skill tool is already granted to custom agents by
default, and adding a per-agent `permission.skill` block would silently
override the user's own global permission intent.

## Shared contracts
Consumes the same `access` field from `agents/meta/*.yaml` identically
before and after this change — only the `readwrite` branch of
`claude_tools_for_access` gains `, Skill`. The rendered tools string at
pre-change was `Read, Grep, Glob, Bash, Edit, Write` (spdd/specs/
access-model.md render-01; here MODIFIED). The docs description (04-docs)
picks up the new string from this layer; the delegation block of
02-orchestrator rides on top of the rendered agents without touching this
layer.

## Feature: the access-to-tools mapping grants the Skill tool to readwrite only

  Background:
    Given "install.sh"'s "claude_tools_for_access" function, which maps
      access levels to Claude Code "tools:" lists
    And the pre-change mapping: readwrite -> "Read, Grep, Glob, Bash, Edit,
      Write", readonly -> "Read, Grep, Glob, Bash", orchestrateonly ->
      "Read, Grep, Glob, Bash, Agent"

  # MODIFY - render-01: the readwrite mapping gains Skill, extending the
  # contract pinned by spdd/specs/access-model.md render-01 (that scenario
  # pinned the exact string "Read, Grep, Glob, Bash, Edit, Write").
  Scenario Outline: render-01
    When install.sh renders "agents/meta/<role>.yaml" for Claude Code
    Then the rendered frontmatter carries "tools: Read, Grep, Glob, Bash, Edit, Write, Skill"

    Examples:
      | role       |
      | specifier  |
      | coder      |
      | verifier   |

  # ADD - render-02: the readonly and orchestrateonly mappings are
  # byte-for-byte unchanged -- the Skill grant is readwrite-only.
  Scenario: render-02
    When the reader reads "claude_tools_for_access" in install.sh
    Then "readonly" still maps to "Read, Grep, Glob, Bash"
    And "orchestrateonly" still maps to "Read, Grep, Glob, Bash, Agent"

  # ADD - render-03: the OpenCode render is unchanged in every respect --
  # the native skill tool is granted to custom agents by default, and a
  # rendered "permission.skill" block would override the user's own global
  # permission intent.
  Scenario: render-03
    When install.sh renders any role's meta for OpenCode, before and after
      this change
    Then every rendered OpenCode file is byte-for-byte identical
    And no rendered OpenCode frontmatter carries a "permission.skill" block
      or a "tools:" entry restricting the skill tool

  # ADD - render-04: the marker format and render determinism survive --
  # the only rendered change anywhere is the readwrite Claude tools string.
  Scenario: render-04
    When install.sh renders any agent or command for either client
    Then the "antz:generated version=X -- do not edit by hand; regenerate
      with install.sh" marker format is unchanged
    And renders remain deterministic from (prompt body, meta access, source
      VERSION), with no other rendered output changed

  ### Invariants
  - No new access level; the taxonomy stays readonly | readwrite |
    orchestrateonly.
  - The access->OpenCode mappings (`edit`, `task`, `mode`) are unchanged.
  - The user's global skill-permission choice is respected on OpenCode: antz
    neither forbids nor masks skill permissions there.
  - Nothing else about install.sh changes (install paths, backup logic,
    --check, set-model command).

## End-to-end QA suite

  # ADD - e2e-render-01: after reinstall from a post-change checkout, the
  # installed Claude copies carry the Skill tool and the installed OpenCode
  # copies are unchanged in shape.
  Scenario: e2e-render-01
    Given the user's machine has the pre-change antz installed
    When the user runs "./install.sh --all" (or "./install.sh" with the
      clients detected) from the post-change checkout
    Then the installed "~/.claude/agents/antz-coder.md" carries "tools:
      Read, Grep, Glob, Bash, Edit, Write, Skill" (same grant on
      antz-specifier and antz-verifier)
    And the installed OpenCode copies keep their pre-change frontmatter
      shape ("mode:", "permission:" with "edit:"/"task:")
    And every installed file is marked "antz:generated version=<new
      VERSION>" in the unchanged marker format

## Out of scope
- Prompt bodies (01-prompts); docs; bump.
- OpenCode-side render changes of any kind.
- The /antz and /antz-set-model command renders.

## Relevant files
- install.sh:102-109 - "claude_tools_for_access" (the readwrite branch).
- install.sh:145-159 - "render_claude"/"render_opencode" (consumers; call
  sites unchanged).
- tests/installsh-posixsh_test.sh - harness pattern for render-level tests.
