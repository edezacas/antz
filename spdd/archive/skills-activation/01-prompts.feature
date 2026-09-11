# Domain: role skills activation (prompts layer)

## Goal
`agents/prompts/coder.prompt` and `agents/prompts/verifier.prompt` carry a
`## Skills` section that makes skill discovery and activation a standing duty
of both roles: discover the available skills before starting the work;
before writing, modifying, or reviewing any code/config, activate every
available skill whose description matches that work (`angular-conventions`
in an Angular project, `omarchy` for desktop config, `customize-opencode`
when editing opencode's own configuration — matched by description, never by
a hardcoded name). The wording stays framework-neutral: "the session's
skill-loading capability, when it exists" plus a directory-listing fallback,
so the same body renders into both Claude Code and OpenCode unchanged.

## Shared contracts
Same wording consumed identically by `03-render` (the `Skill` tool grant is
inert without this prompt duty) and `04-docs` (the gotcha describes exactly
this behavior). Never-fork rule: the duty text is stated once per role
prompt, and the docs restate it without contradiction.

## Feature: coder discovers and activates matching skills before working

  Background:
    Given "agents/prompts/coder.prompt" as the role instructions rendered
      verbatim into every installed antz-coder copy on both clients
    And the pre-change prompt contains no mention of skills at all

  # ADD - prompts-01: the coder prompt gains a Skills section establishing
  # discovery before planning and mandatory activation before writing or
  # modifying code/config a skill covers, with a neutral fallback when no
  # skill-loading tool exists.
  Scenario: prompts-01
    When the reader reads "agents/prompts/coder.prompt"
    Then it contains a "## Skills" section stating that before planning the
      coder discovers the available skills, using the session's
      skill-loading capability when it exists
    And it states the fallback for when no such tool exists: list the
      project's and the user's skills directories (e.g. ".agents/skills/",
      "~/.agents/skills/", ".claude/skills/", "~/.claude/skills/",
      ".opencode/skills/", "~/.config/opencode/skills/") and read the
      matched SKILL.md's content
    And it states that before writing, modifying, or investigating any code
      or files a skill covers, the coder activates that matching skill
      first
    And it states that activation is mandatory when a match exists and a
      no-op when none does

  # ADD - prompts-02: the activation duty is keyed to each skill's own
  # description only -- no specific skill name is hardcoded into the
  # generic role prompt.
  Scenario: prompts-02
    When the reader reads the "## Skills" section of "agents/prompts/coder.prompt"
    Then matching is driven by each skill's own "description" (including the
      description's own trigger language), not by a fixed skill list
    And no concrete skill name (e.g. "angular-conventions") appears as a
      requirement or trigger in the prompt

## Feature: verifier and the untouched roles

  Background:
    Given "agents/prompts/verifier.prompt" revived by the same duty, for
      judging implementations, and the pre-change prompts with no mention
      of skills anywhere (confirmed by grep across agents/, install.sh,
      and the installed copies)

  # ADD - prompts-03: the verifier prompt carries the identical duty for
  # its layer: discover before verifying, activate matching skills before
  # reviewing or judging code the skill covers.
  Scenario: prompts-03
    When the reader reads "agents/prompts/verifier.prompt"
    Then it contains a "## Skills" section stating that before verification
      the verifier discovers the available skills the same way, with the
      same tool-when-present and directory-fallback wording
    And it states that before reviewing or judging any code or files a
      skill covers, the verifier activates that matching skill first, and
      that a warning is in order when covered code was judged without the
      matched skill ever being activated

  # ADD - prompts-04: the added wording is framework-neutral so the same
  # body renders into both clients unchanged.
  Scenario: prompts-04
    When the reader reads the added "## Skills" sections of both prompts
    Then neither names a client-specific tool exclusively (no "Skill" tool
      of Claude Code nor client-specific invocations of OpenCode's skill
      tool are the only path -- both are covered by the neutral
      "skill-loading capability" wording and the directory fallback)
    And neither file contains client-specific syntax that would make the
      body render differently per client

  # MODIFY - prompts-05: only the specifier prompt body stays byte-for-byte
  # unchanged. The orchestrator prompt is no longer untouched: it gains the
  # delegation skills-block duty (specified fully in 02-orchestrator).
  Scenario: prompts-05
    When the reader compares "agents/prompts/specifier.prompt" and
      "agents/prompts/orchestrator.prompt" before and after this change
    Then "agents/prompts/specifier.prompt" is byte-for-byte unchanged
    And "agents/prompts/orchestrator.prompt" differs only by its delegation
      skills-block wording (the "## Skills to load before work" duty the
      orchestrator-01 contract defines)

  # ADD - prompts-06: activation means reading the full SKILL.md (paths, not
  # summaries), the activated resolution outcome is reported in the role's
  # own Output report, and it is never a routing state machine input.
  Scenario: prompts-06
    When the reader reads the "## Skills" section of either prompt
    Then activation is defined as reading the full "SKILL.md" content of
      the matched skill (never acting from a summary or the description
      alone) before the covered work
    And "## Output" of each of the two prompts gains a requirement that the
      report states which skills were activated (by name) or that none
      matched -- a mandatory line, never silently omitted
    And the report line is not an input to any routing state or count: any
      orchestrator re-routing decision is made from disk state, not from
      it

  # ADD - prompts-07: when a delegation carries pre-resolved skill paths
  # (the orchestrator's block, per 02-orchestrator), the session reads
  # exactly those files before task work.
  Scenario: prompts-07
    When the reader reads the "## Skills" section of either the coder or
      the verifier prompt
    Then it states that when the delegation message carries a "## Skills
      to load before work" block with SKILL.md paths, those exact files
      are read first, before any task-specific reading, writing,
      reviewing, or testing
    And it states that only when the delegation carries no such block (a
      direct, non-orchestrated invocation) does the session run its own
      discovery per prompts-01's fallback wording

  ### Invariants
  - The "## Skills" sections are additive: no existing bullet of either
    prompt is reworded or removed.
  - The Tool-grant asymmetry is handled entirely by install.sh's render
    (03-render), never by client-specific prompt text.
  - TDD/verification flow, path-ownership rules, Working Root conventions
    and all existing prompt sections stay intact.

## End-to-end QA suite

  # ADD - e2e-prompts-01: in an Angular project, an antz-coder
  # sub-spec session actually loads the angular-conventions skill before
  # writing Angular code (the reported defect, at the real product UI).
  Scenario: e2e-prompts-01
    Given a project whose relevant sources are Angular (e.g. components,
      templates, forms) and the "angular-conventions" skill installed
    And antz installed and re-generated from a post-change checkout
    When the user delegates one small sub-spec that writes Angular code to
      the antz-coder agent
    Then the session visibly loads/activates the angular-conventions skill
      before writing Angular code
    And the produced Angular code follows the skill's conventions

  # ADD - e2e-prompts-02: skill activation survives the orchestrated flow -
  # a coder session delegated by the orchestrator (via /antz) still
  # activates matching skills.
  Scenario: e2e-prompts-02
    Given the same Angular project setup
    When the user runs the "/antz" command with a change request whose
      sub-specs touch Angular code
    Then the orchestrated coder sessions for those sub-specs activate the
      angular-conventions skill before writing Angular code
    And the flow's other steps (folder spec, verify, archive) proceed as
      normal

## Out of scope
- Installer changes (render layer, 03-render); docs; bump.
- Skills for the specifier or orchestrator prompts.
- Authoring or editing any skill itself.

## Relevant files
- "agents/prompts/coder.prompt" - new "## Skills" section.
- "agents/prompts/verifier.prompt" - new "## Skills" section.
- "agents/prompts/specifier.prompt", "agents/prompts/orchestrator.prompt" -
  byte-for-byte guards (prompts-05).
- Few example skills live at "~/.agents/skills/*/SKILL.md" (discovery-fallback
  wording must find them there).
