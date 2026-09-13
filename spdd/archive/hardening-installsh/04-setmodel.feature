# Domain: set-model (existing; modifies spdd/specs/set-model.md)

## Feature: The /antz-set-model embedded script: anchored marker check and temp-file cleanup trap

  Background:
    Given the embedded set-model script extracted from a rendered
      /antz-set-model command file (the tests/set-model-command_test.sh
      harness precedent), run against fixture agent files under an
      isolated HOME and an isolated TMPDIR
    And the header-marker contract from the marker sub-spec: a file is
      antz-managed when its content carries "# antz:generated " as a
      line-start header comment

  # MODIFY - setmodel-01: the script's managed-file check is anchored to
  # the line-start header marker (refining spdd/specs/set-model.md's
  # "Target file / marker contract" and the detection basis of
  # set-model-cmd-07). Conforming files behave exactly as before; a file
  # that only mentions the marker mid-body is now refused as not
  # antz-managed.
  Scenario: setmodel-01
    Given a fixture antz-coder.md that carries the header marker line and
      a fixture antz-coder.md that mentions "antz:generated" only inside
      its body (no line-start header marker)
    When the script runs with "--agent coder --model opus" against each
    Then the header-marked fixture gains "model: opus" at the fixed
      frontmatter position and the reply confirms success
    And the mid-body-mention fixture is refused with the existing
      not-antz-managed error, exits non-zero, and is left byte-for-byte
      unchanged

  # ADD - setmodel-02: the mktemp scratch file is cleaned up on every
  # normal exit path: after a successful set or a successful clear (and
  # after the nothing-to-clear no-op, which never creates one), no
  # mktemp-style file remains in TMPDIR.
  Scenario: setmodel-02
    When the script runs successfully with "--agent coder --model opus",
      then with "--agent coder --clear" on a configured file, and then
      with "--agent coder --clear" on an unconfigured file
    Then each run exits 0 with the documented reply
    And TMPDIR contains no leftover scratch file after any of the runs

  # ADD - setmodel-03: the cleanup holds on failure too: if the rewrite
  # dies mid-run (the target file made read-only so the write fails), the
  # script exits non-zero, the target file is byte-for-byte unchanged, and
  # no scratch file survives.
  Scenario: setmodel-03
    Given a header-marked fixture antz-coder.md made read-only
    When the script runs with "--agent coder --model opus"
    Then it exits non-zero
    And the fixture is byte-for-byte unchanged
    And TMPDIR contains no leftover scratch file

  # ADD - setmodel-04: the emitted script's token constraint survives the
  # changes: it still contains no dollar-digit token and no "$ARGUMENTS"
  # anywhere (both clients template the command body at invocation time),
  # so the trap addition cannot reintroduce the corruption class
  # command-install-06 guards against.
  Scenario: setmodel-04
    When both clients' rendered command bodies are inspected
    Then the embedded script in each contains no `$<digit>` token and no
      "$ARGUMENTS" sequence
    And both clients' command bodies still carry exactly the one intended
      "Arguments: $ARGUMENTS" injection line

### Invariants
- set-model-cmd-01..12's unit behavior is unchanged: every existing
  fixture in tests/set-model-command_test.sh carries the header marker,
  so the anchored check accepts exactly what it accepted before among
  conforming files.
- The scratch file is created only in the rewrite phase; the trap is set
  when it is created and removes exactly that file -- never the target
  file, never a backup.
- The script stays POSIX sh and parses under bash 3.2 --posix like the
  rest of the emitted bodies.
- The command-level flows (picker, bypass, relay rule) are untouched:
  only the embedded script's marker check and cleanup change.

## Out of scope
- Any change to the /antz-set-model command's argument contract, picker,
  ordering contract, or frontmatter position rules.
- Any change to install_file / installed_version_of (sub-spec 01's sites).
- Temp-file handling anywhere else in install.sh (the only mktemp in the
  emitted set-model script is this one; install.sh's own suites cover the
  rest).
