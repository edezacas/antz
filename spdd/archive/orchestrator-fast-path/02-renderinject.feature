# Change: orchestrator-fast-path — sub-spec 02 (render layer, no behavior change)
#
# install.sh currently renders each agent's body verbatim from
# agents/prompts/<name>.prompt. With sub-spec 01, the orchestrator prompt's
# three script fences carry include markers instead of script bodies, so
# install.sh must substitute the marker lines with the content of the
# scripts/orchestration/ files when rendering the antz-orchestrator agent —
# for both Claude Code and OpenCode. The runtime contract is unchanged: the
# agent still saves each script to a temp file and runs `sh <tempfile> ...`.
# Nothing new is installed as a standalone CLI, hook, or plugin.
#
# Also carries the recorded versioning.md drift fix: install.sh's line-21
# header comment still restates the old tracked set; versioning.md's
# invariant says the next change that legitimately touches install.sh
# corrects it as part of its mandatory-bump commit — this change touches
# install.sh, so it does.

Feature: renderinject — install.sh injects the orchestration scripts into the rendered orchestrator body

  Background:
    Given "scripts/orchestration/" holds antz-flow.sh, antz-probe.sh, and
      antz-skills.sh (sub-spec 01)
    And "agents/prompts/orchestrator.prompt" carries one include-marker line
      per script fence ("# antz-include: scripts/orchestration/<name>.sh")
    And install.sh renders each agent from its prompt body verbatim, for
      Claude Code ("render_claude") and OpenCode ("render_opencode")

  # ADD - renderinject-01: the rendered Claude Code orchestrator body carries
  # the three scripts verbatim at their fences, byte-identical to the
  # pre-change render.
  Scenario: renderinject-01
    When install.sh renders the orchestrator agent for Claude Code
    Then the body of the rendered "antz-orchestrator" file contains, inside
      each of the three script fences, the verbatim content of the
      corresponding "scripts/orchestration/" file (each line carrying the
      fence's own three-space indentation, exactly as the embedded snippet
      was rendered before)
    And no "# antz-include:" line survives anywhere in the rendered body
    And the rendered body is byte-for-byte identical to the pre-change
      render of the same agent (same version marker), so the rendered
      runtime contract is provably unchanged

  # ADD - renderinject-02: the same injection for OpenCode, at OpenCode's own
  # frontmatter; the two bodies share the injected script content.
  Scenario: renderinject-02
    When install.sh renders the orchestrator agent for OpenCode
    Then the body of "~/.config/opencode/agents/antz-orchestrator.md"
      contains the same three verbatim script contents at the same fences,
      with no "# antz-include:" line surviving
    And the frontmatter keeps its pre-change shape ("mode: primary",
      "permission:" with "edit: deny" and the "task:" allowlist) — only the
      body's script-fence lines differ from the pre-change render, and only
      by their source (files instead of inline snippets)

  # ADD - renderinject-03: the runtime contract is unchanged — temp file +
  # sh, nothing new installed standalone.
  Scenario: renderinject-03
    When the rendered orchestrator body is read for either client
    Then it still instructs saving each script to a temp file and running
      "sh <tempfile> ..." (flow: "discover | ensure <slug> | state <slug>
      <probe-path> | release <slug>"; skills:
      "sh <tempfile> <working-root> <match keyword> ..."; the probe run by
      the flow script's "state" subcommand with CHANGE_DIR pointed at the
      change directory)
    And the install writes no file beyond its pre-change set (four agent
      files plus "/antz" and "/antz-set-model" per client): no standalone
      script, CLI, hook, or plugin is installed anywhere

  # ADD - renderinject-04: the scripts are fetched through the same source
  # path as prompts, and a failure never renders a marker left in place.
  Scenario: renderinject-04
    Given install.sh running from a local checkout resolves the three script
      files from disk like every other fetched file
    And install.sh running via "curl | sh" fetches each of the three files
      from RAW_BASE like every other fetched file
    When any of the three files is missing or cannot be fetched
    Then install.sh exits non-zero with an error naming the missing file
    And no rendered orchestrator body is written containing an
      "# antz-include:" line (no silent marker fallback, no partial render)

  # ADD - renderinject-05: the injection is keyed to the orchestrator only —
  # every other rendered file is untouched by this mechanism.
  Scenario: renderinject-05
    When install.sh renders all agents and commands for both clients
    Then the rendered specifier, coder, and verifier bodies and both
      "/antz" and "/antz-set-model" command copies are byte-for-byte
      identical to their pre-change renders (same version marker)
    And no other prompt contains an "# antz-include:" line, and install.sh
      substitutes markers only for the orchestrator agent

  # MODIFY - renderinject-06: the recorded versioning.md drift is corrected
  # (versioning.md invariant: "the next change that legitimately touches
  # install.sh ... should correct line 21 as part of its mandatory-bump
  # commit").
  Scenario: renderinject-06
    When the reader reads install.sh's header comment
    Then it states that VERSION + CHANGELOG.md track changes to
      "agents/prompts/", "agents/meta/", AND "install.sh" (the stale
      tracked-set sentence naming only agents/prompts/ and agents/meta/ is
      gone)
    And no other line of install.sh's header comment changes meaning

  # MODIFY - renderinject-07: the docs' "embedded script" wording follows the
  # move (AGENTS.md and CLAUDE.md are byte-identical twins; docs need no
  # bump).
  Scenario: renderinject-07
    When the reader reads the orchestrator-script gotcha bullets of
      "AGENTS.md" and "CLAUDE.md" (the branch-marker gotcha's antz-flow.sh
      sentence and the probe gotcha's embedded-script convention sentence)
    Then they state the scripts' source of truth is
      "scripts/orchestration/<name>.sh" and that install.sh injects their
      content into the rendered "antz-orchestrator" body for both clients
    And they keep the unchanged runtime wording: saved to a temp file and
      run via "sh <tempfile> ...", nothing installed as a standalone
      CLI/hook/plugin
    And the two files state it identically (byte-identical gotcha bullets)

### Invariants
- No behavior change: the rendered orchestrator body is byte-identical to
  the pre-change render (same version marker), so the flow's runtime
  contract, law wording, and output vocabulary are untouched.
- --check stays keyed off the installed specifier agent's marker version;
  the injection adds no new report line.
- install.sh stays POSIX sh and bash-3.2-safe: script content is read from
  files (fetch_file), never pasted into heredocs captured inside command
  substitutions (the posixsh-01 hazard).
- Nothing is ever installed outside the orchestrator's rendered body: the
  scripts remain repo source files.

## Out of scope
- Any change to the scripts' behavior or the orchestrator prose (sub-specs
  01, 04, 05, 06).
- Any change to the access model, marker format, install locations, or
  detection logic.
- tests/ changes (sub-spec 03).

## Relevant files
- "install.sh" — the injection (keyed to the orchestrator render, both
  clients) plus the fetch path for "scripts/orchestration/*.sh"; header
  comment line 21 corrected (renderinject-06).
- "AGENTS.md", "CLAUDE.md" — the gotcha wording following the move
  (renderinject-07).
- "scripts/orchestration/*" — the injected sources (sub-spec 01).
- "spdd/specs/versioning.md" — the recorded drift this sub-spec closes.
