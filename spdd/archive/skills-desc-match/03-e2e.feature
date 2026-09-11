# Domain: end-to-end QA for change skills-desc-match (e2e layer)

## Goal
Operate the fix at the real product surfaces: an orchestrated `/antz`
delegation's "## Skills to load before work" block (derived by the
orchestrator's embedded snippet from the real user skills tree), and
install.sh's drift report / marker stamping for the bump. No internal API
calls: the observable states are the delegation block text, the
"Skills: none matched" line, the "--check" report, and the rendered
frontmatter markers. The verified real-tree evidence this suite encodes
(checked 2026-09-11 against the live `~/.agents/skills/` tree): angular-
conventions matches "angular" via its description; omarchy matches "hypr"
and "keybinding" only via its "description: >" continuation lines (a naive
line-only extraction returns just ">" and would miss it);
diagnose-crash/find-skills/init-project score 0 for those keywords; and
under the pre-fix snippet "apache" and "edezacas" falsely listed
angular-conventions and init-project — exactly the defect this change
closes.

## Feature: the delegation block matches descriptions only, end to end, and the bump reports

  Background:
    Given antz installed and re-generated from a post-change checkout
      (installed files carry the "antz:generated" marker)
    And the user's real skills tree at "~/.agents/skills/" carrying at
      least the five real skills: angular-conventions, diagnose-crash,
      find-skills, init-project, omarchy

  # ADD - e2e-01: an orchestrated /antz flow's delegation block reflects
  # description-only, block-scalar-aware matching on the real skills tree.
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
  # CLI affordances.
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
