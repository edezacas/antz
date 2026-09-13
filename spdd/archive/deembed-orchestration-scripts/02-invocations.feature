# Change: deembed-orchestration-scripts — sub-spec 02 (orchestrator side)
#
# orchestrator.prompt today embeds the three orchestration scripts as
# fences carrying "# antz-include:" markers; install.sh re-materializes
# their ~335 lines into the rendered antz-orchestrator body, and the
# rendered prose orders the agent to save each script to a temp file and
# run "sh <tempfile>" — so the agent re-emits the whole script text as
# tool-call output on every session and every resume. This sub-spec
# replaces the embed with one-line invocations of the installed files
# (sub-spec 01) and retires the include-marker mechanism. The routing law,
# the tables, the session guards, and every machine line stay as they are.
#
# Priority (KV-cache): the rendered orchestrator body must become a stable
# prefix — no embedded scripts, no volatile data — and the agent's script
# re-materialization output must drop to zero. Scenario 07 pins the
# verifiable "stable prefix" criteria; the expected cache effect is
# recorded in the change README and the CHANGELOG entry (sub-spec 06).

Feature: invocations — the orchestrator prompt invokes the installed scripts by resolved path; the include-marker embed mechanism is retired

  Background:
    Given "agents/prompts/orchestrator.prompt" as the single source of the
      orchestrator body, and install.sh rendering it for both clients
    And the placeholder token "__ANTZ_SCRIPTS_DIR__" naming the libdir
      position inside the prompt source (install.sh substitutes the
      concrete resolved path at render time; the token's shape carries no
      dollar-digit and no $ARGUMENTS sequence, so client command-body
      templating cannot corrupt it)
    And sub-spec 01 having installed antz-flow.sh, antz-probe.sh,
      antz-skills.sh, and antz-set-model.sh into the resolved libdir

  # ADD - invocations-01: the three script fences become one-line path
  # invocations of the installed files.
  Scenario: invocations-01
    When the reader reads "agents/prompts/orchestrator.prompt"
    Then step 1 runs discover, ensure, state, and release through the flow
      script by its path: "sh \"__ANTZ_SCRIPTS_DIR__/antz-flow.sh\"
      discover", "... ensure <slug>", "... state <slug>
      \"__ANTZ_SCRIPTS_DIR__/antz-probe.sh\"" (the state subcommand still
      receives the probe's path), and "... release <slug>"
    And the skills-derivation bullet runs "sh
      \"__ANTZ_SCRIPTS_DIR__/antz-skills.sh\" <working-root> <match
      keyword> ..." in place of the temp-file snippet instruction
    And every prior "save the script below to a temp file" instruction is
      gone, replaced by the one-line invocations
    And no "# antz-include:" marker survives anywhere under "agents/prompts/"

  # REMOVE - invocations-02: the include-marker embed mechanism is retired
  # wholesale — inject_includes(), its call site, and the antz-skills.sh
  # byte-identity carve-out that existed only for it.
  Scenario: invocations-02
    When install.sh's executable code is inspected
    Then inject_includes() and the orchestrator-keyed call site are gone
    And the antz-skills.sh under-fence-indent carve-out (the
      "s/^     done$/  done/" exception) is gone with them — there is no
      fence indentation to re-apply
    And the renderinject-01..05 mechanism this retires is superseded by the
      invocation contract of this sub-spec (the no-marker-survives and
      fail-loud clauses re-appear below in render-side form)

  # ADD - invocations-03: the rendered orchestrator bodies carry zero
  # script content, zero markers, and zero unresolved placeholders.
  Scenario: invocations-03
    When install.sh renders the orchestrator agent for each client into an
      isolated HOME
    Then each rendered "antz-orchestrator" body contains no fenced or
      unfenced line from any scripts/orchestration/ file
    And no "# antz-include:" marker and no "__ANTZ_SCRIPTS_DIR__"
      placeholder survives in any rendered or installed file
    And every invocation line carries the concrete resolved libdir path
    And the frontmatter of both clients keeps its shape (Claude: the
      orchestrateonly tools grant; OpenCode: mode primary and the
      deny-by-default task allowlist) with only the marker version changing

  # ADD - invocations-04: the runtime contract is invoke-by-path with zero
  # re-materialization, and the machine-line vocabulary is byte-identical.
  Scenario: invocations-04
    When the rendered body's instructions are followed in a session
    Then no script text is ever written by the agent — no temp file holds a
      script, no Write or Edit carries script content; each script run is
      a one-line Bash invocation of the installed file
    And the orchestrator's "Never writes anything itself" Owns bullet holds
      literally for the first time (the temp-file exception is gone)
    And the scripts' machine-line vocabulary is byte-identical to today:
      "candidate=branch slug=%s", "candidate=on-disk slug=%s",
      "state=created", "state=reused", "dirty=yes", "state=no_commits",
      "state=checkout_refused", "state=no_branch", "state=no_git",
      "state=no_repo", "state=tree_dirty", "state=bad_slug",
      "branch=missing", "change_dir=missing", "open_questions=",
      "rejected_count=", "subspec=... receipt=... covered=... complete=...
      class=...", "gate=refused reason=...", "released branch=antz/<slug>",
      "skill=... path=... matched=...", "Skills: none matched"

  # ADD - invocations-05: the routing surface keeps its pinned meaning.
  Scenario: invocations-05
    When the reader reads the rendered orchestrator body
    Then the discover-output, state-output, rejection-routing, and
      release-output tables keep their headers and machine lines
    And step 3's classification rules, step 4's rejection routing, the
      session guards (dedup with exactly two exceptions, latch), the
      Report Format, the byte-pinned delegation header ("Working root: ..."
      / "Change slug: ..."), and the human follow-up print are unchanged
    And the flow script still has exactly the four subcommands discover /
      ensure / state / release, and its scripts/orchestration/ file is
      byte-unchanged (its header usage comment therefore keeps the
      historical "sh <tempfile> ..." wording — byte-identity wins over
      cosmetic freshness; the prompt's invocation lines are the operative
      instruction)

  # MODIFY - invocations-06: the structural pins of the prompt shape are
  # re-scoped to the de-embedded shape; the tests themselves re-scope in
  # sub-spec 05.
  Scenario: invocations-06
    When the reader reads "agents/prompts/orchestrator.prompt"
    Then the three script fences are gone: the fenced blocks drop from
      seven to four (14 fence lines to 8) and no ```sh fence remains
    And the four tables survive, the steps still end at 6, and no new
      fenced block was added
    And the numbered steps' prose keeps its pinned wording everywhere
      except the replaced invocation instructions and the fence lines they
      referenced
    And the re-scope covers the fence-count clauses of flow-branch's
      flow-09 and orchprose-01 structure pins

  # ADD - invocations-07: verifiable "stable prefix" criteria (the
  # KV-cache priority), and the expected cache effect on record.
  Scenario: invocations-07
    When install.sh renders both clients twice with an unchanged VERSION
      into fresh isolated HOMEs
    Then the two rendered trees are byte-identical (the render is
      deterministic and idempotent), so a client caching the rendered
      system prompt sees a byte-stable prefix across sessions of the same
      installed version
    And the rendered orchestrator body carries no per-session or per-run
      data — no temp paths, no timestamps, no session state — its only
      version-bearing string being the frontmatter marker line
    And no line of any scripts/orchestration/ file appears in any rendered
      agent body, so a script edit can never dirty the prompt prefix
      (script and prompt are separately installed artifacts)
    And the expected cache effect is recorded in the change README and the
      CHANGELOG entry: the rendered orchestrator body drops from ~483
      measured lines today (145 prose + ~335 injected script lines +
      fences) to ~150 prose lines, and the per-session output
      re-materialization of ~335 script lines drops to zero (one-line
      invocations instead of three Writes plus runs); the version-marker
      invalidation on a VERSION bump is unchanged and accepted

  # MODIFY - invocations-08: the skills-derivation contract is re-scoped to
  # the installed file (skills-activation.md's temp-file invariant wording)
  # with the derivation output contract untouched.
  Scenario: invocations-08
    When the reader reads the rendered orchestrator body's skills bullets
    Then the derivation runs the installed antz-skills.sh by its resolved
      path — the same installed-library invocation convention as
      antz-flow.sh — never a new CLI on PATH, hook, or plugin, and never a
      temp-file copy
    And the derivation output contract is untouched: the "skill=<name>
      path=<absolute SKILL.md path> matched=<kw,...>" lines, "Skills: none
      matched" (exit 0), the cap of five with the alphabetical-by-name
      tie-break, per-entry match reasons, case-insensitive description
      matching
    And the orchestrator still never reads or follows a SKILL.md's
      instructions, still lists paths not summaries, and the "## Skills to
      load before work" block shapes are byte-unchanged
