Feature: End-to-end QA - the versioning rule as a user-checkable repo policy
  # Operates through the real product UI: the repo's policy docs read by a
  # user, and install.sh's own CLI (its flags are a UI affordance, not an
  # internal API call - same convention as spdd/specs/set-model.md's e2e
  # suite). All scenarios are ADD against the NEW domain file
  # spdd/specs/versioning.md (created by the verifier at merge; no prior e2e
  # series exists, so ids start at 01).
  #
  # Scenarios e2e-qa-02 and e2e-qa-05 deliberately simulate rule violations
  # and rule compliance inside the QA exercise and then restore the working
  # tree; their restore steps are part of each scenario, not cleanup
  # hand-waving.

  Background:
    Given a local checkout of the antz repo with this change applied
      ("AGENTS.md" and "CLAUDE.md" stating the new rule; "install.sh",
      "VERSION", "CHANGELOG.md" body, "agents/", "tests/", "docs/", "spdd/"
      all at their pre-change state)
    And Claude Code and OpenCode both detected, with clean, empty
      "~/.claude/agents", "~/.claude/commands", "~/.config/opencode/agents",
      and "~/.config/opencode/commands" directories
    And the user has already run "./install.sh --all", installing all 4
      agents plus the "/antz" and "/antz-set-model" commands for both
      clients, every installed file marked "antz:generated version=<current
      VERSION>"

  # ADD - e2e-qa-01: the rule is discoverable, correct, and identical in both
  # policy docs; the wrong sentence is gone; the docs-only clause survived.
  # This is the change's primary user-visible outcome.
  Scenario: e2e-qa-01
    When the user opens "AGENTS.md" and then "CLAUDE.md"
    Then each "## Versioning" section states that a commit changing
      "agents/prompts/", "agents/meta/", or "install.sh" bumps "VERSION" and
      adds a matching "CHANGELOG.md" entry in the same commit
    And neither file contains the sentence "Changes elsewhere (install.sh,
      docs) don't require a bump"
    And each section states that docs-only changes - including "AGENTS.md"
      and "CLAUDE.md" themselves - require no bump
    And the two sections state the identical rule

  # ADD - e2e-qa-02: the motivating staleness is real today, observed through
  # install.sh's own CLI. The user simulates exactly the practice the new
  # rule forbids - an install.sh-only change that alters rendered output with
  # no bump - and watches the tooling stay silent. This is why the rule
  # exists; after the restore step the repo and installs are back to the
  # committed state.
  Scenario: e2e-qa-02
    When the user edits "install.sh" only, adding one sentence to the
      "/antz" command description rendered by "render_claude_command" and
      "render_opencode_command", without touching "VERSION" or
      "CHANGELOG.md"
    And the user runs "./install.sh --check"
    Then "--check" reports "already up to date (antz <current VERSION>)" for
      both clients - the rendered-command drift is invisible to it
    And the user runs "./install.sh --all"
    Then both clients' installed "~/.claude/commands/antz.md" and
      "~/.config/opencode/commands/antz.md" carry the altered description
      but are still marked "antz:generated version=<current VERSION>"
    And a fresh "./install.sh --check" still reports "already up to date
      (antz <current VERSION>)" for both clients
    When the user restores "install.sh" to its committed state (e.g. "git
      checkout -- install.sh") and re-runs "./install.sh --all"
    Then the installed copies once again match the committed "install.sh",
      still marked "antz:generated version=<current VERSION>", and
      "install.sh" itself matches its committed state again

  # ADD - e2e-qa-03: the documented rule alone resolves the gradation for
  # install.sh-only changes - a reader never needs tribal knowledge. Each row
  # is answerable purely from the "## Versioning" section.
  Scenario Outline: e2e-qa-03
    When the user, reading only the "## Versioning" section, considers a
      future commit whose only change is <change>
    Then the documented rule predicts: <prediction>

    Examples:
      | change                                                                            | prediction                                                                  |
      | a comment-only or wording-only install.sh tweak with no rendered-output change    | a patch bump + matching CHANGELOG.md entry in the same commit + local vX.Y.Z tag |
      | an install.sh behavior change to the rendered commands (e.g. the interactive-picker rendering shipped by set-model-interactive-picker) | a minor bump + matching CHANGELOG.md entry in the same commit + local vX.Y.Z tag |
      | an install.sh contract break (e.g. changing the "antz:generated" marker format)   | a major bump + matching CHANGELOG.md entry in the same commit + local vX.Y.Z tag |

  # ADD - e2e-qa-04: this change itself is the worked example of the
  # preserved docs-only clause - a user can predict from the docs that a
  # commit touching only AGENTS.md/CLAUDE.md bumps nothing, and the repo's
  # actual state confirms the prediction.
  Scenario: e2e-qa-04
    When the user considers this change's diff - only "AGENTS.md" and
      "CLAUDE.md" edited (plus the single "CHANGELOG.md" scope line per
      README.md decision 3)
    Then the documented docs-only clause predicts no "VERSION" bump
    And the repo confirms it: "VERSION" still reads the pre-change value,
      and "CHANGELOG.md" contains no entry describing this change

  # ADD - e2e-qa-05: positive control for the recorded rationale - when the
  # rule IS followed (install.sh change + bump, same commit), the existing
  # --check machinery the docs describe does flag the drift and print the
  # changelog. The rationale in the docs is thus verifiable, not aspirational.
  # Restore steps return the repo AND the installed copies to the committed
  # state.
  Scenario: e2e-qa-05
    When the user simulates a rule-following install.sh-only change in the
      working tree: the same rendered-description edit as e2e-qa-02, plus
      bumping "VERSION" (e.g. to <next minor>) and prepending a matching
      "CHANGELOG.md" entry describing it
    And the user runs "./install.sh --check"
    Then "--check" reports "Claude Code: antz <current VERSION> -> <next
      minor>" and "OpenCode: antz <current VERSION> -> <next minor>"
    And "--check" prints the newly added "CHANGELOG.md" entry
    And the user runs "./install.sh --all"
    Then every installed agent and command file for both clients is
      regenerated with the altered "/antz" description and marked
      "antz:generated version=<next minor>"
    And a fresh "./install.sh --check" reports "already up to date (antz
      <next minor>)" for both clients
    When the user restores "install.sh", "VERSION", and "CHANGELOG.md" to
      their committed states (e.g. "git checkout -- install.sh VERSION
      CHANGELOG.md") and re-runs "./install.sh --all"
    Then the installed copies are again rendered from the committed source
      and marked "antz:generated version=<current VERSION>", and
      "install.sh", "VERSION", and "CHANGELOG.md" each match their committed
      states again
