# Domain: skills-activation

## Origin
- Specced and delivered from change `skills-activation` (merged 2026-09-11,
  archived in `spdd/archive/skills-activation/`). This is a **new standalone
  spec domain**: before this change no spec domain covered role skills
  activation, the orchestrator's pre-resolved delegation skills block, or
  the adoption/rejection register. Only the access-model render/docs edges
  of the change merged into `spdd/specs/access-model.md` (its render-01 and
  docs-03 MODIFIED there).
- Reported defect it fixes: an installed antz-coder session never loaded the
  user's `angular-conventions` skill (or any skill) before writing Angular
  code, because (1) not one prompt/installer file mentioned skills at all,
  and (2) on Claude Code the `readwrite` `tools:` allowlist omitted the
  `Skill` tool, so even a willing subagent could not invoke it. OpenCode's
  gap was layer 1 only — its native skill tool is granted to custom agents
  by default.
- Pattern reconciled from `gentle-ai`'s skill registry: adopted the
  pre-resolved delegation block, mechanical capped description-keyed
  matching, and mandatory resolution reporting — adapted to antz (no
  persistent registry, no refresh automation, no hardcoded instances); the
  registry-based freshness maintenance, install-time configuration mutation,
  per-agent skill instances, and a `skill_resolution` routing vocabulary
  were deliberately rejected.

## Goal
The coder and verifier roles discover the available skills before
planning/verifying and activate any skill whose description matches the code
or files about to be written, modified, or judged — matched by description,
never by a hardcoded skill name. Activation = reading the matched
`SKILL.md` in full (paths, not summaries) before the covered work. The
enablement is mechanical: install.sh's Claude `readwrite` mapping grants the
`Skill` tool (03-render, merged into `spdd/specs/access-model.md`), OpenCode
agents get the client's native skill tool by default, and Pi's readwrite
render carries `inheritSkills: true` so the child sees the client's
discovered skills catalog (Pi's analogue of the `Skill` grant; without it
the catalog is a silent no-op). Skill
locations are the client's own concern: no prompt names a skills directory.
Each role's own report states which skills were activated (by name) or that
none matched — a transparency line only, never a routing input.
**The orchestrator-side detection — the `## Skills to load before work`
delegation block and `scripts/orchestration/antz-skills.sh` — was retired by
change `retire-skills-detection` (v5.0.0, 2026-09-15). The features below
that describe it are historical; the retirement record at the end of this
file is the current contract.**

## Shared contracts
The discovery/activation duty is stated once per role prompt (`## Skills`
sections of `specifier.prompt`, `coder.prompt`, and `verifier.prompt`), is
tool-based (no directory enumeration), and is restated without contradiction
by `docs/law-notes.md`. `agents/meta/*` stay byte-for-byte unchanged.
**Superseded**: the pre-change contract had the orchestrator prompt produce
a `## Skills to load before work` block (the `antz-skills.sh` snippet) that
both role prompts consumed; that block is gone (change
`retire-skills-detection`, v5.0.0).

## Feature: coder and verifier discover and activate matching skills before working (prompts)

  Background:
    Given "agents/prompts/coder.prompt" and "agents/prompts/verifier.prompt"
      as the role instructions rendered verbatim into every installed copy on
      both clients (pre-change: no mention of skills anywhere)

  # ADD - prompts-01: discovery before planning, directory fallback, and
  # mandatory activation before covered work.
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
  # description only — no skill name hardcoded into the generic prompt.
  Scenario: prompts-02
    When the reader reads the "## Skills" section of "agents/prompts/coder.prompt"
    Then matching is driven by each skill's own "description" (including the
      description's own trigger language), not by a fixed skill list
    And no concrete skill name (e.g. "angular-conventions") appears as a
      requirement or trigger in the prompt

  # ADD - prompts-03: the verifier carries the identical duty for its layer,
  # with a warning when covered code was judged without the matched skill.
  Scenario: prompts-03
    When the reader reads "agents/prompts/verifier.prompt"
    Then it contains a "## Skills" section stating that before verification
      the verifier discovers the available skills the same way, with the
      same tool-when-present and directory-fallback wording
    And it states that before reviewing or judging any code or files a
      skill covers, the verifier activates that matching skill first, and
      that a warning is in order when covered code was judged without the
      matched skill ever being activated

  # ADD - prompts-04: the added wording is framework-neutral.
  Scenario: prompts-04
    When the reader reads the added "## Skills" sections of both prompts
    Then neither names a client-specific tool exclusively (no "Skill" tool
      of Claude Code nor client-specific invocations of OpenCode's skill
      tool are the only path — both are covered by the neutral
      "skill-loading capability" wording and the directory fallback)
    And neither file contains client-specific syntax that would make the
      body render differently per client

  # MODIFY - prompts-05: only the specifier prompt body stays byte-for-byte
  # unchanged; the orchestrator prompt gains exactly the delegation
  # skills-block duty (orchestrator-01).
  Scenario: prompts-05
    When the reader compares "agents/prompts/specifier.prompt" and
      "agents/prompts/orchestrator.prompt" before and after this change
    Then "agents/prompts/specifier.prompt" is byte-for-byte unchanged
    And "agents/prompts/orchestrator.prompt" differs only by its delegation
      skills-block wording (the "## Skills to load before work" duty
      orchestrator-01 defines)

  # ADD - prompts-06: activation = reading the full SKILL.md; the role's
  # own report gains a mandatory activated-skills line, never a routing
  # input.
  Scenario: prompts-06
    When the reader reads the "## Skills" section of either prompt
    Then activation is defined as reading the full "SKILL.md" content of
      the matched skill (never acting from a summary or the description
      alone) before the covered work
    And the report section of each of the two prompts (the coder's
      "## Output" and the verifier's "## Report Format") gains a
      requirement that the report states which skills were activated (by
      name) or that none matched — a mandatory line, never silently omitted
    And the report line is not an input to any routing state or count: any
      orchestrator re-routing decision is made from disk state, not from
      it

  # ADD - prompts-07: pre-resolved delegation paths are read first; own
  # discovery only on a direct, non-orchestrated invocation.
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
    **Partially superseded** by change `orchestrator-fast-path`
    (closingblock-05): the specifier prompt's historical byte-for-byte pin
    (prompts-05) was lifted for exactly one additive edit — the closing-block
    requirement added to its output/report section; no existing bullet was
    reworded or removed, and the additive-shape guard enforces the shape.
  - The Tool-grant asymmetry is handled entirely by install.sh's render,
    never by client-specific prompt text.
  - TDD/verification flow, path-ownership rules, Working Root conventions
    and all existing prompt sections stay intact.

## Feature: orchestrated delegations carry pre-resolved skill paths (orchestrator)

> **RETIRED by change `retire-skills-detection` (v5.0.0, 2026-09-15).** The
> `scripts/orchestration/antz-skills.sh` script and the `## Skills to load
> before work` delegation block no longer exist. Kept for history; not a
> current contract. See the retirement record at the end of this file.

  Background:
    Given "agents/prompts/orchestrator.prompt"'s "Every delegation prefixes
      it:" preamble block carrying "Working root: <repo root absolute path>"
      and "Change slug: <slug>" lines, and the pre-change orchestrator
      prompt containing no mention of skills

  # ADD - orchestrator-01: every role delegation gains a mechanically
  # derived, pre-resolved skills block with absolute SKILL.md paths,
  # re-derived from disk per delegation.
  Scenario: orchestrator-01
    When the reader reads "agents/prompts/orchestrator.prompt"
    Then its delegation preamble gains a "## Skills to load before work"
      element that the orchestrator resolves at delegation time
    And the paths are absolute "SKILL.md" file paths - passed verbatim and
      never summarized, matching gentle-ai's "paths, not summaries" rule
    And the listing is re-derived from disk per delegation (the standard
      skills directories of the working root and the user's home, e.g.
      ".agents/skills/", "~/.agents/skills/", ".claude/skills/",
      "~/.claude/skills/", ".opencode/skills/",
      "~/.config/opencode/skills/"), never cached across changes or
      persisted anywhere under "spdd/"

  # ADD - orchestrator-02: the matching is mechanical and capped —
  # triggered by code/task context, best 5, deterministic tie-break.
  Scenario: orchestrator-02
    When the reader reads the derived listing's matching rule
    Then each skill is a candidate whose "SKILL.md" description matches
      the change's file types/languages/areas or the delegated task's
      work type
    And the delegated block carries at most the five best-matching skills,
      ordered with a deterministic tie-break (alphabetical by skill name)
    And each entry's match reason is legible from the generation steps
      (descriptions read by the same mechanical enumeration), never an
      unexplained include

  # ADD - orchestrator-03: no-match is explicit, never silent.
  Scenario: orchestrator-03
    When the orchestrator resolves the listing and no skill matches
    Then the delegation still carries an explicit "Skills: none matched"
      line (the subagent must not wonder whether skills were considered)
    And an unresolvable enumeration (no skills directory exists at all)
      yields the same explicit line, never a silent omission or an
      invented one

  # ADD - orchestrator-04: implementation constraints pinned — temp-file
  # POSIX sh snippet, nothing written to disk, orchestrator never reads or
  # follows a SKILL.md itself.
  Scenario: orchestrator-04
    When the reader reads "agents/prompts/orchestrator.prompt"
    Then the orchestrator's derivation runs as a saved-to-temp-file
      POSIX sh snippet (the antz-flow.sh/status-probe convention), never
      a new antz binary or installed CLI command
    And nothing is written to disk by it: no "spdd/skill-registry.md" (or
      any registry file) is created, read back later, or relied on across
      sessions
    And the orchestrator never parses skill contents itself — it lists
      paths and descriptions only; reading and following a SKILL.md
      remains the delegated session's job (prompts-06)

  ### Invariants
  - The Governing rule survives unchanged: the block is derived from disk,
    not from any role's conversational report; roles still report their
    "skills" resolution line for transparency only (prompts-06).
  - The delegation preamble's two existing lines keep their exact format;
    the block is additive.
  - No client-specific syntax enters the orchestrator prompt body; the
    same body renders into both clients.
  - The orchestrator's embedded scripts remain POSIX sh, temp-file
    executed; command-body templating hazards (no dollar-digit / no
    $ARGUMENTS inside install.sh-rendered command bodies) do not extend to
    agent-file snippets, as install.sh's set-model script documents.
    **Superseded in part** by change `orchestrator-fast-path`
    (scriptsource-01..03, renderinject-01..03): the three scripts — including
    antz-skills.sh — now live as source files under `scripts/orchestration/`,
    the prompt's fences carry `# antz-include:` marker lines, and install.sh
    injects the file content into the rendered `antz-orchestrator` body for
    both clients. Still true: POSIX sh, temp-file executed at runtime,
    nothing installed standalone.
  - The orchestrator never reads or follows a SKILL.md's instructions
    itself; nothing in this layer adds tools to its grant (install.sh's
    orchestrateonly mapping stays unchanged).

## Feature: matching is keyed to the description field only, with block-scalar support (descmatch)

> **RETIRED by change `retire-skills-detection` (v5.0.0, 2026-09-15).**
> `antz-skills.sh` and its description-keyed matcher were deleted whole.
> Kept for history; not a current contract.

  Background:
    Given the embedded antz-skills.sh snippet inside
      "agents/prompts/orchestrator.prompt", extracted marker-to-fence and
      run as POSIX sh ("sh <tempfile> <working-root> <keyword> ...")
    And a temp skills tree with fixture SKILL.md files whose frontmatter
      carries the fields named in each scenario
    And the output contract of the snippet is unchanged: the same
      "skill=<name> path=<path> matched=<kw,...>" lines, the same
      "Skills: none matched" line, the same cap of five with the
      alphabetical tie-break, and case-insensitive keyword matching
    And this feature delivered by `skills-desc-match`, closing the
      Implementation caution recorded at the bottom of this spec

  # MODIFY - descmatch-01: matching is keyed to the description field only —
  # a keyword that appears only in the frontmatter name: no longer matches
  # (originally orchestrator-02's whole-frontmatter match text, re-keyed by
  # skills-desc-match).
  Scenario: descmatch-01
    Given a fixture skill whose "name:" field contains the keyword
      "searchtool" and whose "description:" field is a single line that
      does not contain it ("Reads configuration files.")
    When the snippet is run with the keyword "searchtool"
    Then the output is exactly "Skills: none matched" (exit 0)
    When the snippet is run with the keyword "configuration"
    Then that same skill is listed with "matched=configuration" and its
      absolute SKILL.md path — description hits still match exactly as
      before

  # ADD - descmatch-02: multi-line YAML block scalars are matched — the
  # extraction accumulates indented continuation lines of the description
  # until the next top-level key or the end of the frontmatter, so a
  # keyword living only in a continuation line matches (the real omarchy
  # and diagnose-crash skills use "description: >"; a naive line-only
  # extraction returns just ">" and would make them unmatchable).
  Scenario: descmatch-02
    Given a fixture skill whose frontmatter reads
      "description: >" followed by indented continuation lines, with the
      keyword "keybinding" appearing only on a continuation line
    When the snippet is run with the keyword "keybinding"
    Then that skill is listed with "matched=keybinding"
    Given a second fixture skill using the folded-strip style
      "description: >-" with the keyword "segfault" only in a continuation
      line
    When the snippet is run with the keyword "segfault"
    Then that skill is listed with "matched=segfault"
    Given a third fixture skill whose description block scalar is followed
      by a later top-level key ("license: Apache-2.0") and whose
      continuation lines end before it
    Then the extraction stops at the next top-level key: the description
      text contains neither the ">" indicator line nor any text after the
      "license:" key, so "license" as a keyword does not match that skill
    And the skill body below the closing "---" fence is still never matched
      (the body-never-read invariant keeps holding)

  # ADD - descmatch-03: other frontmatter keys are excluded from matching —
  # the false positives verified on the real tree (keyword "apache" only in
  # "license: Apache-2.0"; keyword "edezacas" only in "metadata:" author)
  # become no-matches (real-tree positives pinned by e2e-01; these fixture
  # scenarios are the deterministic unit-level twins).
  Scenario: descmatch-03
    Given a fixture skill whose frontmatter carries
      "license: Apache-2.0" and a "metadata:" block (author, version) and
      whose description does not mention them
    When the snippet is run with the keyword "apache"
    Then the output is exactly "Skills: none matched"
    When the snippet is run with the keyword "edezacas"
    Then the output is exactly "Skills: none matched"
    When the snippet is run with a keyword that appears in that skill's
      description
    Then the skill is listed with that keyword as its match reason

  # MODIFY - descmatch-04: scope of the descmatch edit — only the lines
  # inside the antz-skills.sh fenced snippet changed (transient
  # change-time verification, verified at the skills-desc-match merge
  # review; not a permanent regression test).
  Scenario: descmatch-04
    When the diff of "agents/prompts/orchestrator.prompt" against the
      pre-change tree is inspected
    Then every changed line lies inside the antz-skills.sh fenced snippet
      (between the fence that follows the "# antz-skills.sh" marker comment
      and the closing fence)
    And the derivation prose bullets (the "## Skills to load before work"
      duty, the derivation-keywords bullet, the none-matched shape, the
      match-reason shape, the temp-file convention bullet) are
      byte-for-byte unchanged
    And "agents/prompts/specifier.prompt", "agents/prompts/coder.prompt",
      "agents/prompts/verifier.prompt", "agents/meta/" (all four),
      "install.sh", "AGENTS.md", and "CLAUDE.md" are byte-for-byte
      unchanged

  # MODIFY - descmatch-05: the runtime tests evolve with the fix —
  # tests/orchestrator-skills-block_test.sh keeps its pre-existing
  # orchestrator-01..04 and body-never-read tests green, gains the
  # descmatch-01..03 ids in its reported test names, and its
  # additive-vs-HEAD guard is scoped: removed lines are permitted only
  # inside the antz-skills.sh fenced snippet, any removal outside it still
  # fails the guard.
  Scenario: descmatch-05
    When "tests/orchestrator-skills-block_test.sh" is run directly
    Then it passes, reporting every pre-existing test (orchestrator-01..04
      block/derivation/matching/none-matched/constraint tests and the
      body-never-read invariant) as still passing with the fixed snippet
    And it reports new tests embedding the ids "descmatch-01", "descmatch-02",
      and "descmatch-03" covering the name-only negative, the block-scalar
      positives, and the license/metadata exclusions
    And its orchestrator.prompt additive-vs-HEAD guard no longer asserts
      that no lines were removed repo-wide: removed lines are permitted only
      inside the antz-skills.sh fenced snippet, and the guard still fails if
      any line outside it is removed
    And the snippet still parses as POSIX sh ("sh -n") in the constraint
      test

  ### Invariants
  - The output contract is unchanged: line shapes, "Skills: none matched"
    (exit 0), cap of five, alphabetical-by-name tie-break, best-score-first
    ordering, per-entry match reasons, case-insensitive matching.
  - The derivation stays stateless: nothing written to disk, no registry,
    nothing under "spdd/", no cache; re-derived fresh per run.
  - The orchestrator still never reads or follows a SKILL.md's instructions:
    only frontmatter name/description data is parsed; skill bodies are
    never matched.
  - The snippet remains a temp-file-executed POSIX sh snippet embedded in
    the prompt — no installed CLI, hook, or plugin. **Superseded** by change
    `orchestrator-fast-path` (scriptsource-01..03, renderinject-01..03): the
    snippet is now the source file `scripts/orchestration/antz-skills.sh`,
    carried into the rendered orchestrator body by install.sh's include-marker
    injection; the temp-file runtime contract and the no-installed-CLI rule
    are unchanged.
  - No role commits anything; the human's follow-ups are unchanged.
  - YAML coverage beyond plain single-line and folded (">" / ">-")
    descriptions (literal "|", quoted multi-line, anchors) is out of scope:
    a non-matching description can only under-include, never falsely match.

## Feature: the adoption/rejection register and the mapping bullets are documented identically in both policy files (docs)

  Background:
    Given "AGENTS.md" and "CLAUDE.md", each carrying "## Gotchas" and
      "## Client Integration" sections, containing no mention of skills
      before this change
    And docs-03 (the Client Integration readwrite bullet) merged into
      "spdd/specs/access-model.md" as its MODIFY edge

  # ADD - docs-01: the skills-activation gotcha states the duty and its
  # mechanical enablement, without contradiction to the render.
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

  # ADD - docs-04: the documented mechanism register states what was
  # adopted and what was deliberately rejected, preempting drift toward a
  # persistent registry or refresh automation.
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

  ### Invariants
  - Both docs' Governing rule, structure, and all other gotcha bullets stay
    intact (only added bullets + the readwrite mapping sentence changed).
  - The two docs carry identical skills-activation statements.
  - No skill name is named as a rule or trigger in the docs (examples may
    illustrate with names; the duty itself stays name-agnostic).

## Feature: the bump to 4.2.0 layered above 4.1.0 (bump)

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/" or "install.sh" bumps "VERSION" and adds a
      matching "CHANGELOG.md" entry in the same commit
    And "CHANGELOG.md" carried "[4.1.0] - 2026-09-11" as its top section

  # ADD - bump-01: the bump is present — VERSION reads 4.2.0 and
  # CHANGELOG.md gains a matching [4.2.0] section above [4.1.0].
  Scenario: bump-01
    When the reader reads "VERSION"
    Then it reads exactly "4.2.0"
    And "CHANGELOG.md" contains a "[4.2.0] - <date>" section above the
      "[4.1.0]" section
    And that section lists the Added/Changed entries matching this change:
      skills-activation learning in the coder and verifier prompts (new
      "## Skills" sections), the orchestrator's pre-resolved "## Skills
      to load before work" delegation block, and the "Skill" tool added to
      the readwrite Claude tools string in install.sh

  # ADD - bump-02: the grade is minor, stated and justified against the
  # versioning table.
  Scenario: bump-02
    When the reader reads the "[4.2.0]" entry against the grading scale
    Then the change grades as "minor": behavior changes to the roles'
      prompts ("## Skills" sections) and to install.sh's rendered agent
      capability (the "Skill" grant) — not "patch" (that grades only
      non-behavioral tweaks), and not "major" (the workflow contract, the
      marker format, the access taxonomy, the rendered command contract,
      and the install locations are all unchanged)

  ### Invariants
  - No role commits anything; the "v4.2.0" tag is the human's commit-time
    follow-up.
  - The CHANGELOG entry follows Keep a Changelog format and file style.
  - "VERSION" is the only content of the "VERSION" file ("4.2.0" with
    trailing newline).
  - "agents/meta/*" are byte-for-byte unchanged (only non-meta edits are
    involved here).

## Feature: the patch bump 4.2.1 layered above 4.2.0 (bump421)

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/" bumps "VERSION" and adds a matching
      "CHANGELOG.md" entry in the same commit
    And "CHANGELOG.md" carried "[4.2.0] - 2026-09-11" as its top section
    And this feature delivered by `skills-desc-match`, tracking the
      descmatch fix

  # ADD - bump421-01: the bump is present — VERSION agrees with a new
  # [4.2.1] section above [4.2.0], carrying a Fixed entry that describes
  # exactly the descmatch narrowing.
  Scenario: bump421-01
    When the reader reads "VERSION" and the top of "CHANGELOG.md"
    Then "VERSION" is a semver string that equals the version of the
      newest (topmost) "CHANGELOG.md" section, which is "[4.2.1] - <date>"
      sitting above the "[4.2.0]" section
    And the "[4.2.1]" section has a "### Fixed" heading whose entry states
      that the orchestrator's embedded antz-skills.sh matching is keyed to
      each skill's "description:" field only — a keyword appearing only in
      the frontmatter "name:", "license:", or "metadata:" no longer lists
      the skill (previously the whole lowercased frontmatter block was
      matched, producing false positives such as "apache" via
      "license: Apache-2.0")
    And that entry states the multi-line support: "description: >" and
      ">-" block scalars match via their indented continuation lines,
      accumulated until the next top-level key or the end of the
      frontmatter (so the real omarchy and diagnose-crash skills stay
      matchable)
    And the entry states nothing else changed — the output shapes, the cap
      of five, the tie-break, the prose, the docs, and install.sh are
      untouched

  # ADD - bump421-02: the grade is patch, stated and justified against the
  # versioning table.
  Scenario: bump421-02
    When the reader reads the "[4.2.1]" entry against the grading scale
    Then the change grades as "patch": the snippet is aligned to
      already-specced behavior with no contract change — the rendered
      prose, the delegation-block contract, the output shapes, the
      workflow contract, the "antz:generated" marker format, the access
      model, and install.sh's mechanics are all unchanged, so no consumer
      breaks (not "minor": no new role behavior, render mechanic, or
      install mechanic is introduced; not "major": nothing in the workflow
      or rendered command contract changes)
    And the entry records that this closes the "Implementation caution"
      recorded in this spec at merge time

  ### Invariants
  - No role commits anything; the "v4.2.1" tag is the human's commit-time
    follow-up (created against the bump commit, not pushed automatically).
  - The CHANGELOG entry follows Keep a Changelog format and the file's
    existing style (bold lead-in, self-contained prose).
  - "VERSION" is the only content of the "VERSION" file (the version with
    a trailing newline).
  - "agents/meta/*", "install.sh", "AGENTS.md", and "CLAUDE.md" are
    byte-for-byte unchanged (docs and tests don't require a bump; nothing
    else moved).

## End-to-end QA suite

Operates at the real product UI: an installed-ants machine, install.sh's
CLI, the orchestrator's delegation derivation, and (for the live-session
halves) a real agent session. All scenarios tagged ADD; delivered by
`skills-activation` and verified by the verifier at merge time:
e2e-render-01 and e2e-bump-01 executed fully against a temp HOME holding a
genuine pre-change install (git-HEAD tree rendered, marker 4.1.0) —
`--check` wrote nothing, reported 4.1.0 -> 4.2.0 on both clients and printed
the [4.2.0] entry; `--all` stamped version=4.2.0 markers, gave the three
readwrite Claude agents `tools: Read, Grep, Glob, Bash, Edit, Write, Skill`,
kept the orchestrator grant unchanged, and kept the OpenCode frontmatter
shape (mode:/permission:) with no skill mention in any OpenCode frontmatter
(real user HOME untouched — reinstall there is the user's follow-up).
e2e-orchestrator-01's delegation half executed live: the extracted
`antz-skills.sh` snippet, run against the real working root, matched
`/home/edezacas/.agents/skills/angular-conventions/SKILL.md` for `angular`
keywords and printed exactly `Skills: none matched` (exit 0) for
unmatched keywords. e2e-prompts-01/02's
discovery-fallback half verified the same way (the angular-conventions
SKILL.md exists and reads in full at ~/.agents/skills/); their live-session
  half (an
  installed antz-coder visibly loading the skill mid-session) is judged by
  the mechanism exactly above and remains machine-observability-limited
  (not reducible here — no role can spawn a live Claude/OpenCode session).
  Delivered by `skills-desc-match` and verified at its merge time:
  e2e-01's observable derivation half executed fully against the real
  `~/.agents/skills/` tree (angular-conventions, diagnose-crash,
  find-skills, init-project, omarchy): "angular" listed only
  angular-conventions; "hypr" and "keybinding" listed only omarchy (its
  "description: >" continuation lines — block-scalar handling proven at
  the real tree); "apache" and "edezacas" printed exactly
  "Skills: none matched" (exit 0), the pre-fix whole-frontmatter false
  positives gone. e2e-01's live-session half (a live /antz flow visibly
  carrying the block) is judged by the same mechanism and remains
  machine-observability-limited like e2e-orchestrator-01 above. e2e-02
  executed fully: a genuine pre-change install (marker 4.2.0) then
  `--check` reported 4.2.0 -> 4.2.1 drift on both detected clients,
  printed the [4.2.1] entry and wrote nothing (installed md5s unchanged);
  `--all` stamped "antz:generated version=4.2.1" markers in the unchanged
  format, and every rendered body was byte-identical to the 4.2.0 render
  except the marker version and the antz-skills.sh snippet lines
  (orchestrator only, both clients).

  # ADD - e2e-prompts-01
  Scenario: e2e-prompts-01
    Given a project whose relevant sources are Angular and the
      "angular-conventions" skill installed
    And antz installed and re-generated from a post-change checkout
    When the user delegates one small sub-spec that writes Angular code to
      the antz-coder agent
    Then the session visibly loads/activates the angular-conventions skill
      before writing Angular code
    And the produced Angular code follows the skill's conventions

  # ADD - e2e-prompts-02
  Scenario: e2e-prompts-02
    Given the same Angular project setup
    When the user runs the "/antz" command with a change request whose
      sub-specs touch Angular code
    Then the orchestrated coder sessions for those sub-specs activate the
      angular-conventions skill before writing Angular code
    And the flow's other steps (folder spec, verify, archive) proceed as
      normal

  # ADD - e2e-orchestrator-01
  Scenario: e2e-orchestrator-01
    Given an Angular project with the "angular-conventions" skill
      installed and antz installed from a post-change checkout
    When the user runs the "/antz" command with a change request whose
      sub-specs touch Angular code
    Then the orchestrator's coder delegation for such a sub-spec carries
      the "## Skills to load before work" block naming the
      angular-conventions SKILL.md absolute path
    And the delegated coder session reads that exact file before writing
      Angular code
    When no sub-spec of the flow touches anything a skill covers
    Then the delegations carry the explicit "Skills: none matched" line,
      never a silent omission

  # ADD - e2e-render-01
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

  # ADD - e2e-docs-01
  Scenario: e2e-docs-01
    Given antz installed and re-generated from a post-change checkout
    When the user reads "AGENTS.md" and "CLAUDE.md" and inspects their
      installed "~/.claude/agents/antz-coder.md"
    Then the doc statement of the "Skill" grant matches the installed
      frontmatter exactly
    And no doc statement contradicts the prompts' "## Skills" sections

  # ADD - e2e-bump-01
  Scenario: e2e-bump-01
    Given the user's machine has the pre-change antz installed (installed
      marker version "4.1.0")
    When the user reads "VERSION" and the top of "CHANGELOG.md", then runs
      "./install.sh --check"
    Then "VERSION" reads "4.2.0", the top section is "[4.2.0] - <date>"
    And "--check" reports the installed-to-source drift for both detected
      clients and prints the "[4.2.0]" entry
    And "./install.sh --all" reproducibly stamps every installed file with
      the "antz:generated version=4.2.0" marker

  # ADD - e2e-01: an orchestrated /antz flow's delegation block reflects
  # description-only, block-scalar-aware matching on the real skills tree
  # (delivered by skills-desc-match).
  Scenario: e2e-01
    When the user runs the "/antz" command with a change request whose
      sub-specs touch Angular code (.ts/.html files)
    Then the coder delegation carries a "## Skills to load before work"
      block naming the angular-conventions SKILL.md absolute path with
      "matched: angular"
    And no skill whose name or license/metadata alone contains a keyword
      is listed for it
    When the user runs "/antz" with a change request touching desktop
      config paths ("~/.config/hypr/", keybindings)
    Then the coder delegation lists the omarchy SKILL.md absolute path —
      the match came from its "description: >" continuation lines, so the
      block scalar handling is proven at the real UI
    When no sub-spec of the flow touches anything any skill's description
      covers
    Then the delegations carry the explicit "Skills: none matched" line,
      never a silent omission and never a name/license-only false positive
    And the observable derivation half may be exercised directly at the
      same UI affordance the orchestrator itself uses (the extracted
      antz-skills.sh temp-file snippet run as shown in the prompt):
      "angular" lists only angular-conventions; "hypr" and "keybinding"
      list only omarchy; "apache" and "edezacas" print exactly
      "Skills: none matched" (exit 0) — the pre-fix false positives are
      gone

  # ADD - e2e-02: the 4.2.1 bump is observable through install.sh's own
  # CLI affordances (delivered by skills-desc-match).
  Scenario: e2e-02
    Given the user's machine has the pre-change antz installed (installed
      marker version "4.2.0")
    When the user reads "VERSION" and the top of "CHANGELOG.md", then runs
      "./install.sh --check"
    Then "VERSION" reads "4.2.1", the top section is "[4.2.1] - <date>"
    And "--check" reports the installed-to-source drift for both detected
      clients and prints the "[4.2.1]" entry
    And "--check" writes nothing
    When the user runs "./install.sh --all"
    Then every installed file is stamped "antz:generated version=4.2.1"
      in the unchanged marker format
    And the rendered agent/command bodies are byte-identical to the 4.2.0
      render except for the antz-skills.sh snippet lines and the embedded
      marker version

## Out of scope
- A persistent skill registry file under "spdd/" or anywhere (rejected);
  refresh automation of any kind (hooks, plugins, CLI refresh commands);
  install-time configuration mutation.
- `skill_resolution` status vocabulary as a contract field or routing
  input; cap/orchestration machinery beyond the 5-best-match block.
- Preloading skills by name (Claude `skills:` preloaded frontmatter field)
  or any embedded catalog of known skills.
- Authoring or editing any skill itself; per-role skill tools changes
  beyond the readwrite `Skill` grant (that MODIFY lives in
  "spdd/specs/access-model.md" render-01); the "worktree" branch variant
  and its historical docs.
- The specifier prompt body. **Partially superseded**: the byte-for-byte
  guard (prompts-05) was lifted for the one additive closing-block bullet
  by `orchestrator-fast-path` (closingblock-05), and lifted again for the
  specifier's `## Skills` section and mandatory activated-skills report
  line by `skills-advisory` (advisory-02).

## Relevant files
- "agents/prompts/coder.prompt", "agents/prompts/verifier.prompt" — the
  new "## Skills" sections and report lines.
- "agents/prompts/orchestrator.prompt" — the delegation preamble's
  "## Skills to load before work" duty plus the `antz-skills.sh`
  temp-file snippet.
- "agents/prompts/specifier.prompt" — byte-for-byte guard (prompts-05).
- "install.sh" — `claude_tools_for_access`' readwrite branch gains `, Skill`
  (the MODIFY edge merged into "spdd/specs/access-model.md" render-01).
- "AGENTS.md", "CLAUDE.md" — the identical skills-activation gotcha and
  the corrected Client Integration readwrite bullet.
- "VERSION", "CHANGELOG.md" — the 4.2.0 bump (bump-01..02).
- "tests/orchestrator-skills-block_test.sh",
  "tests/skills-activation-{prompts,render,docs,bump}_test.sh" — one test
  per scenario id with an explicit SKIP stub for every e2e-only id;
  "tests/access-model_test.sh", "tests/antz-flow_test.sh",
  "tests/installsh-posixsh_test.sh" — minimal evolutions.
- "tests/skills-desc-match-bump_test.sh" — the bump421-01..02 tests
  (delivered by `skills-desc-match`; VERSION asserted as agreeing with
  the newest CHANGELOG entry, never a byte-exact pin);
  "tests/orchestrator-skills-block_test.sh" evolved by the same change
  with the descmatch-01..03 tests and the snippet-scoped
  additive-vs-HEAD guard (descmatch-05).
- "spdd/archive/skills-activation/" — the delivering change, preserved
  for history.
- "spdd/archive/skills-desc-match/" — the delivering change of the
  descmatch layer and the 4.2.1 bump, preserved for history.
- This change (`skills-advisory`, direct edit):
  "agents/prompts/{specifier,coder,verifier,orchestrator}.prompt" (the
  advisory block rule and the specifier's `## Skills` section plus report
  line), this spec file, and the 4.10.0 `VERSION`/`CHANGELOG.md` bump.
  **Superseded in part by `retire-skills-detection` (v5.0.0):** the advisory
  block rules were removed with the block itself; the specifier's `## Skills`
  section and the directory-free wording survive, and the libdir script set
  drops `scripts/orchestration/antz-skills.sh` (deleted).

## Feature: each skills-mandate line is mandatory-reporting only; the mirror principle is stated once per prompt (from 04-skillsline.feature, change `style-rewrite`)

  Background:
    Given "agents/prompts/coder.prompt"'s "## Output" skills bullet and
      "agents/prompts/verifier.prompt"'s "## Report Format" skills bullet,
      each ending with the mirror tail

  # MODIFY - skillsline-01: the coder's skills bullet keeps the
  # mandatory-reporting rule and drops the duplicated mirror tail.
  Scenario: skillsline-01
    When the coder's skills bullet is reworded
    Then it still states that the report says which skills were activated (by
      name) or that none matched — a mandatory line, never silently omitted
    And it no longer ends with the mirror tail

  # MODIFY - skillsline-02: the verifier's skills bullet gets the same edit.
  Scenario: skillsline-02
    When the verifier's skills bullet is reworded
    Then it still states that the report says which skills were activated (by
      name) or that none matched — a mandatory line, never silently omitted
    And it no longer ends with the mirror tail

  # ADD - skillsline-03: the mirror principle is now stated exactly once per
  # prompt, at the closing-block mirror statement.
  Scenario: skillsline-03
    When each of the four prompts is read whole
    Then the string "never an input to any routing state or count" appears
      exactly once in each of specifier.prompt, coder.prompt,
      verifier.prompt, and orchestrator.prompt
    And the string "disk state" appears exactly once in coder.prompt and
      verifier.prompt
    And in coder.prompt and verifier.prompt the single occurrence lives in
      the closing-block mirror statement, not in a skills bullet

  # MODIFY - skillsline-04: the skills suite follows, loudly and per role.
  Scenario: skillsline-04
    When tests/skills-activation-prompts_test.sh is updated and runs
    Then prompts-06's single test is split into per-role halves (coder and
      verifier)
    And each half keeps the mandatory-line pins and moves the not-a-routing-input
      pins to whole-prompt single-occurrence counts
    And the suite's other tests pass unmodified
    And tests/skills-activation-docs_test.sh passes unmodified
    And both suites exit 0

## Implementation caution (verifier, 2026-09-11) — RESOLVED by skills-desc-match
- The `antz-skills.sh` snippet matched against the whole YAML frontmatter
  block (lowercased), not strictly the `description:` field — a keyword
  appearing only in the frontmatter `name:` or another frontmatter key
  could list a skill. Over-inclusive in the permissive direction, match
  reason always legible; graded a warning at merge time, not blocking.
  Considered narrowing `desc_l` to the description line's text only if a
  later change touched this snippet.
- Resolution (verifier, 2026-09-11): change `skills-desc-match` narrowed
  the match text to the `description:` field's content only, with folded
  block-scalar continuation-line accumulation (descmatch-01..03 above;
  "apache"/"edezacas" false positives gone on the real tree, verified by
  e2e-01), and the fix is tracked by the patch bump 4.2.1 (bump421-01..02).
  The caution is closed; the description-keyed contract (orchestrator-02)
  and the implementation now agree.

## Supersession record — change `orchestrator-fast-path` (merged 2026-09-11)

- **The antz-skills.sh snippet is now a source file** (scriptsource-01..03,
  renderinject-01..03, merged into `spdd/specs/flow-branch.md`): the derivation
  runs from `scripts/orchestration/antz-skills.sh`, injected into the rendered
  `antz-orchestrator` body by install.sh's include-marker injection for both
  clients. The output contract (skill= lines, none-matched line, cap of five,
  tie-break, description-keyed matching, block-scalar support) is unchanged —
  the file is a byte-equal dedent of the former fenced snippet, and the suite
  runs it directly (testharness-03). The "extracted marker-to-fence" wording in
  the descmatch Background above describes the pre-change extraction affordance.
- **descmatch-05's additive-vs-HEAD guard re-scoped** (testharness-03): removed
  lines are now permitted only inside any of the three script fenced bodies
  (each must carry exactly its `# antz-include:` marker line naming an existing
  file); any removal outside them still fails the guard. The suite enforces
  this in `tests/orchestrator-skills-block_test.sh`.
- **prompts-05's specifier byte-for-byte pin lifted** (closingblock-05): the
  specifier prompt gains exactly one additive bullet (the closing-block
  requirement in its report section); no existing bullet reworded or removed;
  enforced by the additive-shape guard in `tests/skills-activation-prompts_test.sh`
  with the retirement-note convention.
- **Superseded again by `skills-advisory`**: the specifier prompt gains its
  `## Skills` section and its mandatory activated-skills report line
  (advisory-02), so the historical byte-for-byte clause no longer holds for
  the skills duty either.

## Feature: the pre-resolved block is a hint, never a suppression — a derivation miss never disables a role's own discovery (change `skills-advisory`, direct edit 2026-09-15)

> **advisory-01..03 RETIRED by change `retire-skills-detection` (v5.0.0,
> 2026-09-15)** with the block they qualify. advisory-04 (no prompt names a
> skills directory) survives and is strengthened below.

  Background:
    Given the four role prompts ("specifier", "coder", "verifier",
      "orchestrator")
    And the orchestrator's `## Skills to load before work` block, still
      derived per delegation by the installed
      `scripts/orchestration/antz-skills.sh`
    And the reported defect: the keyword-keyed derivation has a wide miss
      margin (the orchestrator invents the keywords), so a false
      `Skills: none matched` propagated into a skipped activation — the roles
      read a present block as authoritative and never ran their own discovery,
      and the specifier carried no discovery duty at all

  # MODIFY - advisory-01: the block is advisory; own discovery runs always.
  Scenario: advisory-01
    When the reader reads the "## Skills" section of
      "agents/prompts/coder.prompt" and "agents/prompts/verifier.prompt"
    Then a delegation block listing `SKILL.md` paths is still read first
    And the block is stated as a hint, never a substitute for the role's own
      discovery
    And the role runs its own discovery on every session — a direct
      invocation and a delegated one, with either block form, alike
    And a `Skills: none matched` block is stated never to excuse skipping
      that discovery, so a keyword miss upstream cannot become a skipped
      activation

  # ADD - advisory-02: the specifier carries the same duty.
  Scenario: advisory-02
    When the reader reads "agents/prompts/specifier.prompt"
    Then it carries a "## Skills" section with the same tool-when-present and
      directory-fallback wording, its activation duty keyed to each skill's
      own description, and activation defined as reading the full `SKILL.md`
    And its report section requires the mandatory activated-skills line
    And its delegation-block bullet states the same advisory rule (read the
      listed paths first, then still run its own discovery)

  # MODIFY - advisory-03: the orchestrator states the block is a hint.
  Scenario: advisory-03
    When the reader reads the orchestrator's delegation-block bullets
    Then the block is described as a hint, never a substitute for the role's
      own discovery, and a derivation miss never blocks an activation
    And the explicit `Skills: none matched` line survives, never silently
      omitted
    And the derivation stays description-keyed, capped at five with the
      alphabetical tie-break, invoked as the installed script by its
      resolved path, and stateless — the output contract itself is unchanged

  # MODIFY - advisory-04: no prompt names a skills directory.
  Scenario: advisory-04
    When the reader reads the "## Skills" section of the specifier, coder,
      and verifier prompts
    Then none of them names a skills directory (no `.agents/skills`,
      `.claude/skills`, `.opencode/skills`, or a home-relative variant)
    And discovery is stated as the session's own skill-listing capability,
      because the client already resolves its skills locations
    And the orchestrator prompt names no skills list at all: it states that
      skill discovery stays with the delegated role, and it carries no
      `## Skills to load before work` block

  ### Invariants
  - The derivation output contract is unchanged: `skill=`/`path=`/`matched=`
    lines, `Skills: none matched` at exit 0, cap of five, alphabetical
    tie-break, case-insensitive description matching, no registry, nothing
    written to disk, and the orchestrator never reading or following a
    SKILL.md itself.
  - The block's shape is unchanged: `## Skills to load before work` plus
    either the matched-path lines or the single none-matched line, and the
    machine-pinned strings (`paths, not summaries`, the invocation one-liner,
    `never a temp-file copy`, the installed-command clause, the never-read
    clause) stay byte-unchanged.
  - Skills-facing text is written in short imperative sentences, one rule per
    bullet, and names no skills directory: discovery is the client's own
    skill-listing capability. The enumeration lives in the installed
    `antz-skills.sh` only.
  - `agents/meta/*` are byte-for-byte unchanged; no new tool grant, no
    client-specific syntax, and no new CLI, hook, or plugin is introduced.

## Supersession record — change `skills-advisory` (direct, 2026-09-15)

- **prompts-07 superseded**: its "Only when the delegation carries no such
  block (a direct, non-orchestrated invocation) do you run your own
  discovery" rule is superseded by advisory-01. A delegation block — present
  with paths or reading `Skills: none matched` — never suppresses the role's
  own discovery; the block pre-resolves, the role still discovers.
- **orchestrator-03 refined**: the explicit `Skills: none matched` line
  survives byte-unchanged and is still never silently omitted; it is now
  stated to be the derivation's result and never a substitute for the role's
  own discovery, which runs regardless.
- **prompts-05's specifier clause lifted** (see advisory-02): the specifier
  prompt gains its `## Skills` section and its mandatory activated-skills
  report line. The earlier lift for the closing-block bullet was
  closingblock-05.
- **prompts-01's directory fallback superseded** (see advisory-04): the
  prompts no longer enumerate skills directories or describe a "when no skill
  tool exists" fallback. Discovery is the session's skill-listing capability;
  the installed `antz-skills.sh` keeps its own enumeration but no longer
  restates it in prose.
- **No test edit**: the repo's hygiene law forbids suites from pinning a
  role prompt's prose, and the derivation script's output contract is
  unchanged, so no suite changes with this change.
- **Legibility pass (same change)**: the four prompts' skills-facing text was
  rewritten as short imperative bullets — one rule per bullet, hedged and
  duplicated clauses removed, and the directory enumeration dropped from the
  prose — with the machine-pinned strings kept byte-identical so the
  rendered-output suite stays green.

## Feature: orchestrator-side skill detection retired — discovery is the delegated role's own (change `retire-skills-detection`, v5.0.0, direct 2026-09-15)

  Background:
    Given the four role prompts, the surviving per-role `## Skills` duty, and
      the delegation message's two header lines (`Working root`,
      `Change slug`)
    And the reported concern: the orchestrator's keyword-keyed derivation was
      a second, weaker discovery channel for a role that already has a
      native skill-listing capability and the full task context, and its
      recall was correlated against its usefulness — a keyword miss fired
      exactly when a nudge would have helped

  # ADD - retire-01: the script and the delegation block are gone.
  Scenario: retire-01
    When the repository is inspected
    Then `scripts/orchestration/antz-skills.sh` does not exist
    And `install.sh`'s libdir install set is `antz-flow.sh`, `antz-probe.sh`,
      and `antz-set-model.sh`, with no `antz-skills.sh` fetch, install call,
      or `--check` line
    And `agents/prompts/orchestrator.prompt` carries no
      `## Skills to load before work` block, no matched-path sample, and no
      `Skills: none matched` line, and its delegation message is exactly the
      `Working root` and `Change slug` lines plus the task

  # ADD - retire-02: discovery belongs to the role.
  Scenario: retire-02
    When the reader reads the `## Skills` section of the specifier, coder,
      and verifier prompts
    Then each states discovery through the session's skill-listing
      capability, matching by each skill's own description, activation by
      reading the full `SKILL.md`, and the mandatory activated-skills report
      line
    And none names a skills directory and none references a delegation
      skills block
    And the orchestrator prompt states that skill discovery stays with the
      delegated role and never derives or passes a skills list

  # ADD - retire-03: the removed contract is accounted for.
  Scenario: retire-03
    When the reader reads this domain's supersession records
    Then orchestrator-01..04, descmatch-01..05, advisory-01..03, prompts-07,
      and the docs-01..04 block clauses are marked retired with their
      replacement behavior named
    And the surviving behavior — per-role native discovery, description
      matching, full-`SKILL.md` activation, and the mandatory report line —
      is stated as the current contract

  ### Invariants
  - The delegated role is the only actor that discovers or activates skills.
    No orchestrator-side enumeration, keyword derivation, ranking, cap, or
    delegation block exists.
  - `agents/meta/*` are byte-for-byte unchanged; no new tool grant, no
    client-specific syntax, and no new CLI, hook, or plugin is introduced.
  - The `Skill` readwrite grant in `install.sh` is unchanged: it is what makes
    the role's own discovery possible.

## Supersession record — change `retire-skills-detection` (v5.0.0, direct, 2026-09-15)

- **orchestrator-01..04 retired**: the `## Skills to load before work`
  delegation block, its absolute-path listing, its match-reason lines, its
  none-matched line, and the `antz-skills.sh` invocation contract are gone.
  Skill discovery is the role's own.
- **descmatch-01..05 retired**: the description-keyed matcher, block-scalar
  handling, cap of five, alphabetical tie-break, and output contract were
  deleted with `scripts/orchestration/antz-skills.sh`.
- **advisory-01..03 retired**: they qualified a block that no longer exists.
  advisory-04 survives: no prompt names a skills directory, and now the
  orchestrator passes no skills list either.
- **prompts-07 retired**: there is no delegation block to read first. The
  surviving prompts-01 duty is tool-based discovery; the directory-fallback
  enumeration had already been removed by advisory-04.
- **docs-01..04 block clauses retired**: the docs no longer describe a
  pre-resolved delegation block; `docs/law-notes.md`'s skills section now
  states that discovery belongs to the client.
- **`install.sh`'s libdir set shrinks to three files**, and every file-count
  pin in the suites moves with it.
- **Grade: major (5.0.0)** — the orchestrator's delegation-message contract
  changes and an installed artifact is removed. Not minor: a consumer that
  expected the block, or the installed `antz-skills.sh`, breaks.

