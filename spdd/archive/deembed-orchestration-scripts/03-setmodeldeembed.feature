# Change: deembed-orchestration-scripts — sub-spec 03 (set-model side)
#
# /antz-set-model's two command files today embed the ~155-line set-model
# script (set_model_script -> emit_set_model_script, with the
# __CLIENT__/__AGENTS_DIR__ per-client substitution and the bash-3.2
# emitter workaround that exists because the heredoc is captured inside
# $(...)). This sub-spec installs that script as the fourth libdir file
# (sub-spec 01) and turns both command bodies into path invocations of it.
#
# Fact-checked corrections against the request brief, applied here:
# - The command copies measure ~192/~186 rendered lines today (not ~300);
#   the drop lands near ~90.
# - Only the SET-MODEL script's emitter loses its $(...) capture. The two
#   picker emitters (emit_picker_claude / emit_picker_opencode) and
#   set_model_flow_head keep theirs — the pickers are instruction prose
#   that stays embedded in the command bodies, so their bash-3.2-safe
#   capture rationale survives. The brief's claim that the 567-571
#   workaround disappears is therefore only half true; this spec pins the
#   accurate state.
# - The script becomes client-parameterized (decision: goal 1 enumerates
#   exactly four installed artifacts, "el de set-model" singular — one
#   file). The client arrives as the script's first positional argument,
#   supplied by each per-client command body. The user-facing client
#   binding (the invoker never supplies a client flag) is preserved at the
#   command level, where it is defined.

Feature: setmodeldeembed — the set-model script installs as a libdir file and both command bodies invoke it by path

  Background:
    Given the set-model script text emitted today by install.sh's
      emit_set_model_script (a self-contained POSIX sh editor of one
      installed agent file's "model:" frontmatter line)
    And the resolved libdir from sub-spec 01, holding the installed
      "antz-set-model.sh" with its "antz:generated" marker
    And the two installed command copies
      ("~/.claude/commands/antz-set-model.md" and
      "~/.config/opencode/commands/antz-set-model.md"), each permanently
      scoped to its own client

  # ADD - setmodeldeembed-01: the script installs as one file, gains a
  # required first positional client argument, and keeps its entire
  # behavior contract.
  Scenario: setmodeldeembed-01
    When the installed script runs as
      "sh \"<libdir>/antz-set-model.sh\" <claude|opencode> --agent <name>
      (--model <value>|--clear)"
    Then it resolves the agents directory internally from that first
      argument (claude -> "$HOME/.claude/agents", opencode ->
      "$HOME/.config/opencode/agents") and applies the unchanged editing
      contract: add after "description:" before "tools:"/"mode:", replace
      in place, or remove on --clear; byte-preserving everything else;
      anchored line-start marker check refusing unmanaged files; temp-file
      trap cleanup on every exit path; verbatim, never-validated model
      values
    And a missing or unknown client argument is a usage error naming the
      two valid values, writing nothing
    And every success and failure message is byte-identical to today's
      (the client name now comes from the argument where it once came from
      the render-time substitution)

  # REMOVE - setmodeldeembed-02: the command bodies embed no script.
  Scenario: setmodeldeembed-02
    When the reader reads either installed command copy
    Then the ```sh script fence and the "saving it below to a temp file"
      run instruction are gone
    And the run instruction instead invokes the installed script by its
      concrete resolved libdir path with the copy's own client as the
      first argument — the Claude copy passes "claude", the OpenCode copy
      passes "opencode" — so the invoker still never supplies a client
      flag or argument (the Client-binding shared contract is preserved)
    And "Arguments: $ARGUMENTS" remains the single argument-injection
      point, exactly as today
    And each copy still never references the other client's directory or
      frontmatter position

  # ADD - setmodeldeembed-03: the emitter capture retires for the script
  # only; the pickers' capture rationale survives; install.sh stays
  # bash-3.2-safe.
  Scenario: setmodeldeembed-03
    When install.sh's executable code is inspected
    Then set_model_script()'s command-substitution capture and its
      per-client __CLIENT__/__AGENTS_DIR__ sed substitution are gone: the
      script text is written straight to the libdir file (plain
      redirection, no capture), so the emit_set_model_script workaround
      comment loses its subject and retires with the capture
    And emit_picker_claude, emit_picker_opencode, and set_model_flow_head
      keep their command-substitution captures with their bash-3.2
      rationale intact (their content stays embedded in the command
      bodies)
    And install.sh still parses under "sh -n" and under the bash 3.2
      POSIX-mode parse check (the posixsh-01 mechanical scan still finds
      zero heredoc bodies inside command substitutions)

  # MODIFY - setmodeldeembed-04: the token-templating scope moves with the
  # script; the command-body constraint holds and the embedded-script
  # prohibition re-scopes to the standalone file.
  Scenario: setmodeldeembed-04
    When the rendered command bodies are inspected
    Then each body still carries no client-substitutable dollar-digit
      token, and the "$ARGUMENTS" placeholder appears exactly once as the
      injection point (command-install-06 holds unchanged)
    And the installed script file may use dollar-digit positional
      parameters — it is a standalone file, never templated by any client
      — so the embedded-script dollar-digit and $ARGUMENTS prohibitions
      (setmodel-01..04's extraction-based checks) are re-scoped from "the
      embedded copy inside the command body" to "the installed file runs
      the same observable contract"
    And the exactly-one-of --model/--clear invocation contract, the
      fail-fast ordering (validate, pre-flight, then question), the
      interactive picker flow, and the relay rule (reply exactly what the
      script printed) are all unchanged

  # MODIFY - setmodeldeembed-05: the suites and spec clauses that pin the
  # embedded script re-scope to the installed file.
  Scenario: setmodeldeembed-05
    When the repo's full unit suite runs
    Then tests/set-model-command_test.sh's embedded-script extraction is
      replaced by running the installed libdir file, with the same
      scenario ids still reported and passing (editing behavior,
      refusals, marker check, trap, token scope)
    And tests/installsh-posixsh_test.sh's posixsh-04 assertions re-key:
      the "for arg do" line is asserted in the installed
      "antz-set-model.sh" file instead of the command bodies, and the
      documented inventory gains the four libdir files
    And spdd/specs/posixsh.md's e2e-qa-01 clauses re-scope the same way
      (the twelve-installs inventory becomes sixteen; the embedded
      set-model script clause becomes the installed-file clause) — merged
      into the posixsh domain

  # ADD - setmodeldeembed-06: the command files' shape after the de-embed.
  Scenario: setmodeldeembed-06
    When install.sh renders both command copies into an isolated HOME
    Then each copy's frontmatter is unchanged (marker, quoted description,
      argument-hint on Claude, no "agent:" field anywhere), and each body
      keeps the intro, fail-fast steps, pre-flight, its client's picker
      block, and the apply/relay tail
    And each body drops its script fence: the rendered command files
      measure roughly half their current size (from the measured ~192 /
      ~186 lines today toward ~90), the picker alias vocabulary (Claude)
      and the "opencode models" enumeration instruction (OpenCode)
      unchanged
    And re-running install.sh overwrites both copies in place with no
      backup (marker convention) — e2e-qa-16 of the set-model domain
      still holds
