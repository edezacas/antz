# Domain: orchestrator skills delegation (orchestrator layer)

## Goal
The orchestrator's delegation preamble (its only sanctioned cross-role
channel: "Working root" / "Change slug" lines) gains a third, mechanically
derived element — a `## Skills to load before work` block listing absolute
SKILL.md paths — so subagent sessions (which, no matter the client, arrive
with no skill awareness of their own) receive pre-resolved skill paths
instead of being left to weaker in-session discovery. The pattern is
adopted from gentle-ai (`.atl/skill-registry.md` + path injection), cut
down to antz's contract: no persistent registry file, no refresh CLI, no
hooks in user config — the orchestrator derives the listing statelessly at
each delegation from the standard skill discovery directories with the
same embedded-POSIX-sh convention as `antz-flow.sh` and the status probe,
writing nothing to disk itself. Paths, not summaries: exactly the delegate
compounding failure gentle-ai documents (subagents run with empty context;
"SKILL.md is the runtime contract") is the situation antz flows already
budget for via the Governing rule.

## Shared contracts
The block's shape is produced by 02-orchestrator and consumed identically
by the coder's and verifier's "## Skills" sections (prompts-07) and the
docs gotcha (04-docs docs-04). The block appears in every role delegation
(the specifier investigates code and writes conventions-sensitive specs as
often as the coder edits it). The same neutral orchestrator prompt body
renders into both clients.

## Feature: orchestrated delegations carry pre-resolved skill paths

  Background:
    Given "agents/prompts/orchestrator.prompt"'s "Every delegation prefixes
      it:" preamble block, currently carrying exactly "Working root:
      <repo root absolute path>" and "Change slug: <slug>" lines
    And the pre-change orchestrator prompt contains no mention of skills

  # ADD - orchestrator-01: every role delegation gains a mechanically
  # derived, pre-resolved skills block with absolute SKILL.md paths,
  # derived at delegation time from the standard discovery directories,
  # never from conversational memory.
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

  # ADD - orchestrator-02: the matching is mechanical and capped: triggered
  # by what the sub-spec touches (code context: extensions/paths; task
  # context: implementation, review, testing), the best 5 matches travel,
  # with a deterministic tie-break.
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

  # ADD - orchestrator-03: no-match is explicit, never silent -- the block
  # is present in every delegation either way.
  Scenario: orchestrator-03
    When the orchestrator resolves the listing and no skill matches
    Then the delegation still carries an explicit "Skills: none matched"
      line (the subagent must not wonder whether skills were considered)
    And an unresolvable enumeration (no skills directory exists at all)
      yields the same explicit line, never a silent omission or an
      invented one

  # ADD - orchestrator-04: implementation constraints pinned -- the
  # orchestrator stays delegate-only: it writes nothing under "spdd/", no
  # registry file, and the derivation is a temp-file embedded sh snippet
  # per the prompt's own convention, not a new installed command.
  Scenario: orchestrator-04
    When the reader reads "agents/prompts/orchestrator.prompt"
    Then the orchestrator's derivation runs as a saved-to-temp-file
      POSIX sh snippet (the antz-flow.sh/status-probe convention), never
      a new antz binary or installed CLI command
    And nothing is written to disk by it: no "spdd/skill-registry.md" (or
      any registry file) is created, read back later, or relied on across
      sessions
    And the orchestrator never parses skill contents itself - it lists
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
    executed, with the no-dollar-digit/no-$ARGUMENTS constraints
    (any new snippet in a client-templated body must respect the same
    templating hazard, as install.sh's set-model script documents).
  - The orchestrator never reads or follows a SKILL.md's instructions
    itself; nothing in this layer adds tools to its grant (install.sh's
    orchestrateonly mapping stays unchanged, render-02).

## End-to-end QA suite

  # ADD - e2e-orchestrator-01: an orchestrated /antz flow's coder delegation
  # message visibly carries the pre-resolved skills block, and the
  # delegated session reads those exact files.
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

## Out of scope
- A persistent skill registry file under "spdd/" or anywhere (rejected).
- Refresh automation of any kind (hooks in users' settings, plugins, CLI
  refresh commands) - rejected; stateless per-delegation derivation
  replaces freshness maintenance entirely.
- skill_resolution status vocabulary as a contract-level field or a
  routing input (the simplified Output line of prompts-06 is the adopted
  form).
- Extending any embedded orchestrator script's routing outputs.

## Relevant files
- "agents/prompts/orchestrator.prompt:133-138" - the delegation preamble
  block the "## Skills to load before work" duty extends.
- "agents/prompts/orchestrator.prompt" embedded scripts (antz-flow.sh,
  status probe) - the convention the derivation snippet follows.
- "agents/prompts/coder.prompt", "agents/prompts/verifier.prompt" - the
  delegated side of the contract (prompts-06, prompts-07).
