# Domain: skills docs (documentation layer)

## Goal
AGENTS.md and CLAUDE.md document the skills-activation behavior so a user
reading either file derives the real capabilities: the coder and verifier
roles discover and activate matching skills (stated identically in both
files, per the two-docs never-fork rule), enabled mechanically by the
readwrite Claude grant's `Skill` tool and by OpenCode's native skill tool,
and restated in the Client Integration mapping bullets so the `readwrite`
description names the new Claude grant. No doc statement may contradict the
prompts (01) or the render (02).

## Shared contracts
The new gotcha bullet is a verbatim-identical twin across AGENTS.md and
CLAUDE.md (docs-02 pins the sync), mirroring the pattern of the access-model
gotcha. The Client Integration bullets reference exactly the tools string defined
by 03-render's render-01 (MODIFY of spdd/specs/access-model.md's docs
contracts).

## Feature: the behavior is documented identically in both policy files

  Background:
    Given "AGENTS.md" and "CLAUDE.md", each carrying "## Gotchas" and
      "## Client Integration" sections, currently containing no mention of
      skills at all (verified by grep)

  # ADD - docs-01: AGENTS.md gains a skills-activation gotcha stating the
  # duty and its mechanical enablement, without contradiction to the render.
  Scenario: docs-01
    When the reader reads the "## Gotchas" section of "AGENTS.md"
    Then it contains a bullet stating that the antz coder and verifier roles
      discover the available skills before planning/verifying and activate
      any skill whose description matches the code or files about to be
      written, modified, or judged - matched by description, never by a
      hardcoded skill name
    And it states the mechanical enablement: the rendered "readwrite" Claude
      grant includes the "Skill" tool (a subagent "tools:" list is an
      enforced allowlist there), while OpenCode agents get its native skill
      tool by default
    And the same bullet yields the working-root fallback wording for
      clients without a skill tool (directory listing fallback)

  # ADD - docs-02: CLAUDE.md states the identical bullet (the two docs
  # duplicate each other and must not fork).
  Scenario: docs-02
    When the reader compares the skills-activation gotcha of "AGENTS.md" and
      "CLAUDE.md"
    Then they are stated identically

  # ADD - docs-04: the documented mechanism register states what antz
  # adopted from gentle-ai's working pattern and what it deliberately
  # rejected, so the docs preempt future drift toward a persistent
  # registry or refresh automation.
  Scenario: docs-04
    When the reader reads the skills-activation gotcha of "AGENTS.md" and
      "CLAUDE.md"
    Then it states that orchestrated (via "/antz") delegations carry a
      pre-resolved "## Skills to load before work" block with absolute
      SKILL.md paths, derived mechanically from the standard skills
      directories at delegation time (paths, not summaries)
    And it states a "Skills: none matched" line appears explicitly when no
      skill matches
    And it states that no persistent registry file is kept and no refresh
      hook, plugin, or CLI is introduced: freshness comes from
      per-delegation derivation, and "install.sh" never mutates user
      configuration (settings.json, permission blocks) for this
    And it states the roles' report states which skills were activated
      (by name) or that none matched

  # MODIFY - docs-03: the Client Integration mapping bullets are corrected
  # for the new readwrite grant - the pre-change wording says the
  # "readwrite" level maps to "full edit access" alone; after this change it
  # maps to full edit access plus the Skill tool on Claude Code (MODIFY of
  # spdd/specs/access-model.md docs-03's "Client Integration" contract).
  Scenario: docs-03
    When the reader reads the "## Client Integration" sections of
      "AGENTS.md" and "CLAUDE.md"
    Then the "readwrite" mapping sentence states "full edit access" plus,
      on Claude Code, the "Skill" tool grant - with the OpenCode side
      described as inheriting the native skill tool by default
    And the "orchestrateonly" mapping sentence and both files' statement of
      the never-commits law and boundary statement are unchanged
    And no doc statement contradicts the "## Skills" sections of the two
      edited role prompts or the "readwrite" Claude tools string

  ### Invariants
  - Both docs' Governing rule, structure, and all other gotcha bullets stay
    intact (only added bullets + the readwrite mapping sentence changed).
  - The two docs carry identical skills-activation statements.
  - No skill name is named as a rule or trigger in the docs (examples may
    illustrate with names; the duty itself stays name-agnostic).

## End-to-end QA suite

  # ADD - e2e-docs-01: a user reading the docs derives the real capability,
  # with no contradiction left against the installed agents.
  Scenario: e2e-docs-01
    Given antz installed and re-generated from a post-change checkout
    When the user reads "AGENTS.md" and "CLAUDE.md" and inspects their
      installed "~/.claude/agents/antz-coder.md"
    Then the doc statement of the "Skill" grant matches the installed
      frontmatter exactly
    And no doc statement contradicts the prompts' "## Skills" sections

## Out of scope
- All other doc platforms (docs/orchestrator.md, docs/worktree-isolation-plan*.md,
  historical sibling variant docs).
- The docs' own Versioning section wording (05-bump consumes it, unmodified).

## Relevant files
- AGENTS.md (## Gotchas, ## Client Integration) - the corrected bullets.
- CLAUDE.md - the identical corrected bullets.
- spdd/specs/access-model.md - the domain receiving the merge (docs-03
  MODIFY).
